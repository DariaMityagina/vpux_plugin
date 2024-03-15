//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/VPU37XX/dialect/VPU/transforms/passes.hpp"
#include "vpux/compiler/core/tiling.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/transforms/passes.hpp"
#include "vpux/compiler/utils/attributes.hpp"
#include "vpux/compiler/utils/rewriter.hpp"
#include "vpux/compiler/utils/types.hpp"

#include <mlir/Pass/PassManager.h>
#include <mlir/Transforms/DialectConversion.h>

using namespace vpux;

namespace {

// This computes the buffers for the most granular tiling possible for the original MVN op.
// The decomposition happens if not even this tiling scheme fits in CMX.
SmallVector<vpux::NDTypeInterface> getTiledBuffers(vpux::NDTypeInterface input, vpux::NDTypeInterface output,
                                                   DimArr nonNormDims) {
    auto inputShape = to_small_vector(input.getShape());
    auto outputShape = to_small_vector(output.getShape());
    for (auto& dim : nonNormDims) {
        inputShape[dim.ind()] = 1;
        outputShape[dim.ind()] = 1;
    }
    return SmallVector<vpux::NDTypeInterface>{input.changeShape(ShapeRef(inputShape)),
                                              output.changeShape(ShapeRef(outputShape))};
}

mlir::FailureOr<OutputTiling> findNumOfTiles(VPU::MVNOp op) {
    const auto input = op.getInput().getType().cast<vpux::NDTypeInterface>();

    const auto inputShape = to_small_vector(input.getShape());

    const auto maxDim = std::distance(inputShape.begin(), std::max_element(inputShape.begin(), inputShape.end()));

    int64_t tilesNum = 1;
    auto newInputShape = to_small_vector(input.getShape());
    auto outputC = op.getAcrossChannels() ? 1 : inputShape[Dims4D::Act::C.ind()];
    SmallVector<int64_t> newOutputShape{inputShape[Dims4D::Act::N.ind()], outputC, 1};
    const auto newOutType = vpux::getTensorType(ShapeRef(newOutputShape), mlir::Float32Type::get(input.getContext()),
                                                DimsOrder::CWH, input.getMemSpace());
    newInputShape[maxDim] = inputShape[maxDim] / tilesNum;

    while (!op.fitIntoCMX(SmallVector<vpux::NDTypeInterface>{input.changeShape(ShapeRef(newInputShape)),
                                                             newOutType.cast<vpux::NDTypeInterface>()})) {
        tilesNum++;
        if (tilesNum > inputShape[maxDim]) {
            return errorAt(op.getLoc(), "Can't tiled MVN1SumOp over one dimension.");
        }

        newInputShape[maxDim] = divUp(inputShape[maxDim], tilesNum);
    }

    SmallVector<int64_t> divisors(newInputShape.size(), 1);
    divisors[maxDim] = tilesNum;

    return fillDividedTiles(op, ShapeRef(divisors), input.getShape());
}

mlir::Value reifyTileDecomposedMVN(VPU::MVNOp MVNOp, const TileInfo& inputTile, mlir::OpBuilder& builder, Logger log) {
    log.trace("{0}", inputTile);
    const auto valInputName = printToString("input");

    const auto tiledSliceInput =
            vpux::VPU::makeTile(builder, MVNOp.getLoc(), MVNOp.getInput(), inputTile, valInputName);
    auto tileMVN1SumOp = builder.create<VPU::MVN1SumOp>(MVNOp.getLoc(), tiledSliceInput, MVNOp.getAcrossChannels(),
                                                        MVNOp.getNormalizeVariance());

    return tileMVN1SumOp.getResult();
}

//
// applyTileStrategyDecomposedMVN
//

mlir::LogicalResult applyTileStrategyDecomposedMVN(VPU::MVNOp MVNOp, const OutputTiling& tiles,
                                                   mlir::PatternRewriter& rewriter, Logger log) {
    mlir::Operation* tileMVN1SumOp;
    if (tiles.size() > 1) {
        // apply the generated fake tiling strategy and convert MVN to Slice.
        SmallVector<mlir::Value> resultTileVals;

        for (const auto& inputTile : tiles) {
            const auto tiledRes = reifyTileDecomposedMVN(MVNOp, inputTile, rewriter, log);
            resultTileVals.push_back(tiledRes);
        }

        tileMVN1SumOp = rewriter.create<VPU::ConcatOp>(MVNOp.getLoc(), mlir::ValueRange(resultTileVals), 2);
    } else {
        tileMVN1SumOp = rewriter.create<VPU::MVN1SumOp>(MVNOp.getLoc(), MVNOp.getInput(), MVNOp.getAcrossChannels(),
                                                        MVNOp.getNormalizeVariance());
    }

    const auto outputType = MVNOp.getOutput().getType().cast<vpux::NDTypeInterface>();
    auto tileMVN1MeanVarOp = rewriter.create<VPU::MVN1MeanVarOp>(
            MVNOp.getLoc(), tileMVN1SumOp->getResult(0), getIntArrayAttr(rewriter, outputType.getShape().raw()),
            MVNOp.getAcrossChannels(), MVNOp.getNormalizeVariance(), MVNOp.getEps(), outputType.getElementType());
    rewriter.replaceOpWithNewOp<VPU::MVN1NormalizeOp>(MVNOp, MVNOp.getInput(), tileMVN1MeanVarOp.getResult(),
                                                      MVNOp.getAcrossChannelsAttr(), MVNOp.getNormalizeVarianceAttr());

    return mlir::success();
}
//
// DecomposeMVNPass
//

class DecomposeMVNPass final : public VPU::arch37xx::DecomposeMVNBase<DecomposeMVNPass> {
public:
    explicit DecomposeMVNPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

public:
    class MVNConverter;

private:
    void safeRunOnFunc() final;
};

//
// MVNConverter
//

class DecomposeMVNPass::MVNConverter final : public mlir::OpRewritePattern<VPU::MVNOp> {
public:
    MVNConverter(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<VPU::MVNOp>(ctx), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPU::MVNOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult DecomposeMVNPass::MVNConverter::matchAndRewrite(VPU::MVNOp origOp,
                                                                    mlir::PatternRewriter& rewriter) const {
    _log.trace("Got '{0}' at '{1}'", origOp->getName(), origOp->getLoc());
    const auto tiles = findNumOfTiles(origOp);

    if (mlir::failed(tiles)) {
        return mlir::failure();
    }

    return applyTileStrategyDecomposedMVN(origOp, tiles.value(), rewriter, _log);
}

//
// safeRunOnFunc
//

void DecomposeMVNPass::safeRunOnFunc() {
    auto& ctx = getContext();

    mlir::ConversionTarget target(ctx);

    target.addDynamicallyLegalOp<VPU::MVNOp>([&](VPU::MVNOp op) {
        const auto inputType = op.getInput().getType().cast<vpux::NDTypeInterface>();
        const auto outputType = op.getOutput().getType().cast<vpux::NDTypeInterface>();

        // Can't get feasible tiling strategy for MVNOp because it will not fit into CMX.
        if (!op.fitIntoCMX(getTiledBuffers(inputType, outputType, op.getNonNormDims()))) {
            _log.nest(1).trace("Can't still fit into CMX after tiling. The pass is used to decompose MVNOp.");
            return false;
        }
        return true;
    });

    target.addLegalOp<VPU::SliceOp>();
    target.addLegalOp<VPU::MVN1SumOp>();
    target.addLegalOp<VPU::MVN1MeanVarOp>();
    target.addLegalOp<VPU::MVN1NormalizeOp>();
    target.addLegalOp<VPU::ConcatOp>();

    mlir::RewritePatternSet patterns(&ctx);
    patterns.add<MVNConverter>(&ctx, _log);

    auto func = getOperation();
    if (mlir::failed(mlir::applyPartialConversion(func, target, std::move(patterns)))) {
        _log.debug("Failed to decompose MVNOp into 3 separete functions.");
        signalPassFailure();
    }
}

}  // namespace

//
// createDecomposeMVNPass
//

std::unique_ptr<mlir::Pass> vpux::VPU::arch37xx::createDecomposeMVNPass(Logger log) {
    return std::make_unique<DecomposeMVNPass>(log);
}
