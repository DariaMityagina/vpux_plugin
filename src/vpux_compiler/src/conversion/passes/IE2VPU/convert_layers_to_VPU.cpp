//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/conversion/passes/IE2VPU/convert_layers_to_VPU.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"

using namespace vpux;

//
// computeWeightForEmbeddingOp
//

void vpux::computeWeightForEmbeddingOp(mlir::MLIRContext* ctx, mlir::RankedTensorType& weightsTensorType,
                                       mlir::DenseElementsAttr& baseAttr, llvm::ArrayRef<int64_t> weightsShape,
                                       vpux::NDTypeInterface inType) {
    // Serialization of optional arguments for sw operators not supported
    // weight tensor is constructed when it is not provided
    const auto iType = inType.getElementType();

    if (iType.isUnsignedInteger(8)) {
        // netPrecision:U8
        weightsTensorType = mlir::RankedTensorType::get(
                weightsShape, mlir::IntegerType::get(ctx, 8, mlir::IntegerType::SignednessSemantics::Unsigned));
        baseAttr = mlir::DenseElementsAttr::get(weightsTensorType, (uint8_t)1);

    } else if (iType.isInteger(32)) {
        // netPrecision:int32
        weightsTensorType = mlir::RankedTensorType::get(
                weightsShape, mlir::IntegerType::get(ctx, 32, mlir::IntegerType::SignednessSemantics::Signed));
        baseAttr = mlir::DenseElementsAttr::get(weightsTensorType, 1);

    } else if (iType.isF16()) {
        // netPrecision:float16
        weightsTensorType = mlir::RankedTensorType::get(weightsShape, mlir::Float16Type::get(ctx));
        baseAttr = mlir::DenseElementsAttr::get(weightsTensorType, ov::float16(1));
    } else {
        VPUX_THROW("Unsupported element type: {0}", iType);
    }
}

//
// IfRewrite
//

mlir::LogicalResult IfRewrite::matchAndRewrite(IE::IfOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.debug("Found If Operation '{0}' at '{1}'", origOp->getName(), origOp->getLoc());

    mlir::IRMapping mapper;
    auto thenBlock = &origOp.getThenBranch().getBlocks().front();
    auto elseBlock = &origOp.getElseBranch().getBlocks().front();

    // Map then and else branch inputs
    for (auto valueIt : llvm::enumerate(origOp.getInputs())) {
        auto blockArg = thenBlock->getArgument(valueIt.index());
        mapper.map(blockArg, valueIt.value());
        blockArg = elseBlock->getArgument(valueIt.index());
        mapper.map(blockArg, valueIt.value());
    }

    // Then branch construct
    SmallVector<mlir::Value> thenBranchResults;
    SmallVector<mlir::Type> outTypes;
    for (auto& op : origOp.getThenBranch().getOps()) {
        mlir::Operation* newOp = rewriter.clone(op, mapper);
        if (mlir::isa<IE::YieldOp>(op)) {
            for (mlir::Value operand : newOp->getOperands()) {
                thenBranchResults.push_back(operand);
                outTypes.push_back(operand.getType());
            }
            rewriter.eraseOp(newOp);
            continue;
        }
        for (const auto& [result, newResult] : zip(op.getResults(), newOp->getResults())) {
            mapper.map(result, newResult);
        }
    }

    // Else branch construct
    SmallVector<mlir::Value> elseBranchResults;
    for (auto& op : origOp.getElseBranch().getOps()) {
        mlir::Operation* newOp = rewriter.clone(op, mapper);
        if (mlir::isa<IE::YieldOp>(op)) {
            for (mlir::Value operand : newOp->getOperands()) {
                elseBranchResults.push_back(operand);
            }
            rewriter.eraseOp(newOp);
            continue;
        }
        for (const auto& [result, newResult] : zip(op.getResults(), newOp->getResults())) {
            mapper.map(result, newResult);
        }
    }

    auto cond = origOp.getCond();
    SmallVector<mlir::Value> branchResults;
    int64_t numInputs = thenBranchResults.size();
    for (auto i = 0; i < numInputs; i++) {
        auto result = rewriter.create<VPU::ConditionalCopyOp>(origOp.getLoc(), outTypes[i], cond, thenBranchResults[i],
                                                              elseBranchResults[i]);
        branchResults.push_back(result);
    }
    rewriter.replaceOp(origOp, branchResults);

    return mlir::success();
}

//
// CTCGreedyDecoderSeqLenRewrite
//

mlir::LogicalResult CTCGreedyDecoderSeqLenRewrite::matchAndRewrite(IE::CTCGreedyDecoderSeqLenOp origOp,
                                                                   mlir::PatternRewriter& rewriter) const {
    _log.trace("Found CTCGreedyDecoderSeqLen Operation '{0}'", origOp->getLoc());

    mlir::Value blankIndexValue = origOp.getBlankIndex();
    if (blankIndexValue == nullptr) {
        // Default value is C-1
        auto* ctx = origOp->getContext();
        const auto inShape = getShape(origOp.getInput()).raw();

        if (inShape.size() != 3) {
            return errorAt(origOp.getLoc(), "ConvertLayers2VPU::CTCGreedyDecoderSeqLenRewrite: First input tensor "
                                            "should have 3 dimensions: [N, T, C]");
        }
        auto blankIndxDefValue = checked_cast<int32_t>(inShape.back() - 1);
        auto blankIndxShape = mlir::RankedTensorType::get(
                {1}, mlir::IntegerType::get(ctx, 32, mlir::IntegerType::SignednessSemantics::Signed));
        auto blankIndxAttr = mlir::DenseElementsAttr::get(blankIndxShape, blankIndxDefValue);
        blankIndexValue = rewriter.create<Const::DeclareOp>(origOp.getLoc(), blankIndxShape,
                                                            Const::ContentAttr::get(blankIndxAttr))
                                  .getOutput();
    }
    rewriter.replaceOpWithNewOp<VPU::CTCGreedyDecoderSeqLenOp>(origOp, origOp.getInput(), origOp.getSequenceLength(),
                                                               blankIndexValue, origOp.getMergeRepeatedAttr());
    return mlir::success();
}

//
// ProposalRewrite
//

mlir::LogicalResult ProposalRewrite::matchAndRewrite(IE::ProposalOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("Found Proposal Operation '{0}'", origOp->getLoc());

    rewriter.replaceOpWithNewOp<VPU::ProposalOp>(origOp, origOp.getClassProbs(), origOp.getBboxDeltas(),
                                                 origOp.getImageShape(), origOp.getProposalAttrsAttr());
    _log.trace("Replaced with 'VPU.ProposalOp'");

    return mlir::success();
}

//
// SplitRewrite
//

mlir::LogicalResult SplitRewrite::matchAndRewrite(IE::SplitOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("Found Split Operation '{0}'", origOp->getLoc());

    rewriter.replaceOpWithNewOp<VPU::SplitOp>(origOp, origOp.getInput(), origOp.getAxis(), origOp.getNumSplitsAttr(),
                                              origOp.getAxisValueAttr());

    return mlir::success();
}

mlir::LogicalResult StubRewrite::matchAndRewrite(IE::StubOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.debug("Found Stub Operation '{0}' at '{1}'", origOp->getName(), origOp->getLoc());

    rewriter.replaceOpWithNewOp<VPU::StubOp>(origOp, origOp.getOutputs().getTypes(), origOp.getInputs());

    return mlir::success();
}

//
// NonMaxSuppressionRewrite
//

mlir::LogicalResult NonMaxSuppressionRewrite::matchAndRewrite(IE::NonMaxSuppressionOp origOp,
                                                              mlir::PatternRewriter& rewriter) const {
    _log.trace("Found NonMaxSuppression Operation '{0}'", origOp->getLoc());

    rewriter.replaceOpWithNewOp<VPU::NonMaxSuppressionOp>(
            origOp, origOp.getInBoxCoords(), origOp.getInBoxScores(), origOp.getBoxEncoding(),
            origOp.getSortResultDescending(), origOp.getMaxOutputBoxesPerClassValueAttr(),
            origOp.getIouThresholdValueAttr(), origOp.getScoreThresholdValueAttr(), origOp.getSoftNmsSigmaValueAttr());

    _log.trace("Replaced with 'VPU.NonMaxSuppressionOp'");

    return mlir::success();
}

//
// GRUCellRewrite
//

mlir::LogicalResult GRUCellRewrite::matchAndRewrite(IE::GRUCellOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("Found GRUCell Operation '{0}'", origOp->getLoc());

    auto* ctx = origOp->getContext();
    const auto inputShape = getShape(origOp.getInputData()).raw();
    const auto batchSize = inputShape[0];
    const auto inputSize = inputShape[1];
    SmallVector<int64_t> newInputShape = {batchSize, 1, inputSize};
    const auto newInputShapeAttr = getIntArrayAttr(ctx, newInputShape);
    auto newInput =
            rewriter.create<VPU::ReshapeOp>(origOp->getLoc(), origOp.getInputData(), nullptr, false, newInputShapeAttr);

    const auto initialStateShape = getShape(origOp.getInitialHiddenState()).raw();
    const auto hiddenSize = initialStateShape[1];
    SmallVector<int64_t> newInitialStateShape = {batchSize, 1, hiddenSize};
    const auto newInitialStateShapeAttr = getIntArrayAttr(ctx, newInitialStateShape);
    auto newInitialState =
            rewriter.create<VPU::ReshapeOp>(origOp->getLoc(), origOp.getInitialHiddenState(), /*shape=*/nullptr,
                                            /*special_zero=*/false, newInitialStateShapeAttr);

    SmallVector<int64_t> newWeightsShape = {1, 3 * hiddenSize, inputSize};
    const auto newWeightsShapeAttr = getIntArrayAttr(ctx, newWeightsShape);
    auto newWeights =
            rewriter.create<VPU::ReshapeOp>(origOp->getLoc(), origOp.getWeights(), nullptr, false, newWeightsShapeAttr);

    SmallVector<int64_t> newReWeightsShape = {1, 3 * hiddenSize, hiddenSize};
    const auto newReWeightsShapeAttr = getIntArrayAttr(ctx, newReWeightsShape);
    auto newReWeights =
            rewriter.create<VPU::ReshapeOp>(origOp->getLoc(), origOp.getRecurrenceWeights(), /*shape=*/nullptr,
                                            /*special_zero=*/false, newReWeightsShapeAttr);

    const auto biasesShape = getShape(origOp.getBiases()).raw();
    SmallVector<int64_t> newBiasesShape = {1, biasesShape[0]};
    const auto newBiasesShapeAttr = getIntArrayAttr(ctx, newBiasesShape);
    auto newBiases = rewriter.create<VPU::ReshapeOp>(origOp->getLoc(), origOp.getBiases(), /*shape=*/nullptr,
                                                     /*special_zero=*/false, newBiasesShapeAttr);

    const auto seqLenAttr = getIntAttr(ctx, 1);
    const auto directionAttr = IE::RNNSequenceDirectionAttr::get(ctx, IE::RNNSequenceDirection::FORWARD);

    auto gruSeq =
            rewriter.create<VPU::GRUSequenceOp>(origOp->getLoc(), newInput, newInitialState, newWeights, newReWeights,
                                                newBiases, origOp.getHiddenSizeAttr(), seqLenAttr, directionAttr,
                                                origOp.getShouldLinearBeforeResetAttr(), origOp.getClipAttr());
    SmallVector<int64_t> newOutputShape = {batchSize, hiddenSize};
    const auto newOutputShapeAttr = getIntArrayAttr(ctx, newOutputShape);
    rewriter.replaceOpWithNewOp<VPU::ReshapeOp>(origOp, gruSeq.getOutputHiddenState(), /*shape=*/nullptr,
                                                /*special_zero=*/false, newOutputShapeAttr);

    return mlir::success();
}

//
// EmbeddingBagPackedSumRewrite
//

mlir::LogicalResult EmbeddingBagPackedSumRewrite::matchAndRewrite(IE::EmbeddingBagPackedSumOp origOp,
                                                                  mlir::PatternRewriter& rewriter) const {
    _log.trace("Found EmbeddingBagPackedSum Operation '{0}'", origOp->getLoc());

    auto* ctx = origOp->getContext();
    const auto weights = origOp.getPerSampleWeights();
    if (weights != nullptr) {
        rewriter.replaceOpWithNewOp<VPU::EmbeddingBagPackedSumOp>(origOp, origOp.getEmbTable(), origOp.getIndices(),
                                                                  origOp.getPerSampleWeights());
        return mlir::success();
    }

    mlir::RankedTensorType weightsTensorType;
    mlir::DenseElementsAttr baseAttr;
    const auto weightsShape = getShape(origOp.getIndices()).raw();
    const auto inType = origOp.getEmbTable().getType().cast<NDTypeInterface>();

    computeWeightForEmbeddingOp(ctx, weightsTensorType, baseAttr, weightsShape, inType);

    auto cst = rewriter.create<Const::DeclareOp>(origOp.getLoc(), weightsTensorType, Const::ContentAttr::get(baseAttr));
    rewriter.replaceOpWithNewOp<VPU::EmbeddingBagPackedSumOp>(origOp, origOp.getEmbTable(), origOp.getIndices(),
                                                              cst.getOutput());
    return mlir::success();
}

//
// InterpolateRewrite
//

mlir::LogicalResult InterpolateRewrite::matchAndRewrite(IE::InterpolateOp origOp,
                                                        mlir::PatternRewriter& rewriter) const {
    rewriter.replaceOpWithNewOp<VPU::InterpolateOp>(
            origOp, origOp.getType(), origOp.getInput(), origOp.getSizes(), origOp.getScales(), origOp.getAxes(),
            origOp.getSizesAttrAttr(), origOp.getScalesAttrAttr(), origOp.getAxesAttrAttr(),
            origOp.getTileOffsetAttrAttr(), origOp.getInitialInputDimsAttrAttr(), origOp.getInitialOutputDimsAttrAttr(),
            /*initial_input_offset_attr=*/nullptr, /*initial_output_offset_attr=*/nullptr,
            /*multiClusterStrategy=*/nullptr, origOp.getAttrAttr());
    return mlir::success();
}

//
// TopKRewrite
//

mlir::LogicalResult TopKRewrite::matchAndRewrite(IE::TopKOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("Found TopK Operation '{0}'", origOp->getLoc());

    rewriter.replaceOpWithNewOp<VPU::TopKOp>(origOp, origOp.getInput(), origOp.getK(), origOp.getKValueAttr(),
                                             origOp.getAxis(), origOp.getMode(), origOp.getSort(),
                                             origOp.getElementType(), /*multiClusterStrategy=*/nullptr);

    return mlir::success();
}

//
// TransposedConvRewrite
//

mlir::LogicalResult TransposedConvRewrite::matchAndRewrite(IE::TransposedConvolutionOp origOp,
                                                           mlir::PatternRewriter& rewriter) const {
    _log.trace("Found TransposedConvolution Operation '{0}'", origOp->getLoc());

    auto outType = origOp.getOutput().getType();

    rewriter.replaceOpWithNewOp<VPU::TransposedConvolutionOp>(
            origOp, outType, origOp.getInput(), origOp.getFilter(), origOp.getOutputShape(), origOp.getBias(),
            origOp.getStridesAttr(), origOp.getPadsBeginAttr(), origOp.getPadsEndAttr(), origOp.getDilationsAttr(),
            origOp.getOutputPaddingAttr(), origOp.getPostOpAttr(), origOp.getClampAttr());

    return mlir::success();
}

//
// NormalizeL2Rewrite
//

mlir::LogicalResult NormalizeL2Rewrite::matchAndRewrite(IE::NormalizeL2Op origOp,
                                                        mlir::PatternRewriter& rewriter) const {
    _log.trace("Found NormalizeL2 Operation '{0}'", origOp->getLoc());

    rewriter.replaceOpWithNewOp<VPU::NormalizeL2Op>(origOp, origOp.getData(), origOp.getAxesValueAttr(),
                                                    origOp.getEpsAttr(), origOp.getEpsModeAttr(),
                                                    /*multiClusterStrategy=*/nullptr);

    return mlir::success();
}
