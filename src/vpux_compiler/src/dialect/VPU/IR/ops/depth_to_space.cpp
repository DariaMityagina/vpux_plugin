//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/utils/resources.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/const_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/distributed_tensor_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/explicit_distribution_utils.hpp"
#include "vpux/compiler/dialect/VPUIP/convert_to_dma_utils.hpp"
#include "vpux/compiler/utils/error.hpp"
#include "vpux/utils/core/checked_cast.hpp"

using namespace vpux;

//
// ClusteredOpInterface
//

bool vpux::VPU::DepthToSpaceOp::checkStrategyCompatibility(VPU::MultiClusterStrategy strategy) {
    const auto inputType = getInput().getType().cast<vpux::NDTypeInterface>();
    const auto inShape = inputType.getShape();

    if (strategy == VPU::MultiClusterStrategy::Clustering) {
        return false;
    }

    // Optimized DepthToSpace SW kernel implementation has no restriction on W and H (can be tiled on these dims), but
    // cannot split C-dim on multiple shaves, see E#86460.
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeight && inShape[Dims4D::Act::H] > 1) {
        return true;
    }

    if (strategy == VPU::MultiClusterStrategy::SplitOverWidth && inShape[Dims4D::Act::W] > 1) {
        return true;
    }

    return false;
}

vpux::VPU::DistributedTensorAttr vpux::VPU::DepthToSpaceOp::getExplicitDistributedTensorAttr(
        vpux::ShapeRef shape, vpux::VPU::DistributionMode distributionMode, mlir::ArrayAttr numTiles,
        mlir::IntegerAttr numClusters, mlir::ArrayAttr alignment, mlir::ArrayAttr /*kernel*/,
        vpux::VPU::PaddingAttr /*pad*/, mlir::ArrayAttr /*stride*/, mlir::UnitAttr uniformDistributedSegments) {
    return VPU::getSWExplicitDistributedTensorAttr(mlir::dyn_cast<VPU::SWOpInterface>(getOperation()), shape,
                                                   distributionMode, numTiles, numClusters, alignment,
                                                   uniformDistributedSegments);
}

void vpux::VPU::DepthToSpaceOp::build(::mlir::OpBuilder& odsBuilder, ::mlir::OperationState& odsState,
                                      ::mlir::Value input, ::mlir::IntegerAttr block_size,
                                      vpux::IE::DepthToSpaceModeAttr mode,
                                      /*optional*/ vpux::IE::ChannelPaddingAttr padded_channels) {
    build(odsBuilder, odsState, input, block_size, mode, padded_channels, {});
}

//
// SWOpInterface
//

bool vpux::VPU::DepthToSpaceOp::fitIntoCMX(llvm::ArrayRef<vpux::NDTypeInterface> buffers, Byte reservedMem) {
    VPUX_THROW_UNLESS(buffers.size() == 2,
                      "DepthToSpaceOp requires 1 input and 1 output, but the number of buffers is {0}", buffers.size());

    SmallVector<Byte> buffersSize;
    std::transform(buffers.begin(), buffers.end(), std::back_inserter(buffersSize), [](const auto buffer) {
        return buffer.getTotalAllocSize();
    });

    auto totalAvailableCMXSize = reservedMem.count() == 0 ? getTotalCMXSize(getOperation()).count()
                                                          : getTotalCMXFragmentationAwareSize(getOperation()).count();

    return vpux::VPU::calculateAlignedBuffersMemoryRequirement(getArch(getOperation()), buffersSize).count() +
                   reservedMem.count() <=
           totalAvailableCMXSize;
}

bool vpux::VPU::DepthToSpaceOp::fitIntoCMX(llvm::ArrayRef<vpux::NDTypeInterface> buffers) {
    return fitIntoCMX(buffers, Byte(0));
}

bool vpux::VPU::DepthToSpaceOp::supportCycleCostCalculation() {
    return false;
}

bool isDistributedOutputTypeOverlapped(VPU::ClusteredOpInterface op, int64_t numClusters) {
    auto resultType = op->getResult(0).getType().cast<vpux::NDTypeInterface>();
    auto numClustersAttr = mlir::IntegerAttr::get(getInt64Type(op->getContext()), numClusters);
    auto opStrategy = op.getMultiClusterStrategy().value();
    auto outputDistributedType = getDistributedOutputTypeFromOp(op, resultType, numClustersAttr, opStrategy);
    if (auto distributedTensor = outputDistributedType.dyn_cast<VPU::DistributedTensorType>()) {
        return distributedTensor.getDistribution().getMode().getValue() == VPU::DistributionMode::OVERLAPPED;
    }
    return false;
}

bool isCompatibleWithMultiClusterNNDMA(VPU::DepthToSpaceOp op, vpux::ShapeRef nTilesOnDim) {
    if (op.getMode() != IE::DepthToSpaceMode::BLOCKS_FIRST) {
        return false;
    }
    const auto inputType = op.getInput().getType().cast<vpux::NDTypeInterface>();
    const auto outputType = op.getOutput().getType().cast<vpux::NDTypeInterface>();
    const auto inOrder = inputType.getDimsOrder();
    const auto outOrder = outputType.getDimsOrder();
    if (inOrder != DimsOrder::NHWC || outOrder != DimsOrder::NHWC) {
        return false;
    }
    const auto inputShape = inputType.getShape();
    if (inputShape[Dims4D::Act::H] > VPUIP::DMA_MAX_NUMBER_PLANES) {
        // TODO: split more DMAs when the numPlanes is larger than 256 [Track number: E#57027]
        return false;
    }
    // Check previous op
    auto prevOp = op->getOperand(0).getDefiningOp<VPU::ClusteredOpInterface>();
    if (prevOp == nullptr) {
        return false;
    }
    auto prevOpStrategyAttr = prevOp.getMultiClusterStrategy();
    if (!prevOpStrategyAttr.has_value() || prevOpStrategyAttr.value() != VPU::MultiClusterStrategy::SplitOverHeight) {
        return false;
    }
    auto module = prevOp->getParentOfType<mlir::ModuleOp>();
    auto tileOp = IE::getTileExecutor(module);
    auto numClusters = tileOp.getCount();

    // Support for overlapped buffers will be addded with E#86818
    if (isDistributedOutputTypeOverlapped(prevOp, numClusters)) {
        return false;
    }
    // Check next ops
    for (auto nextOp : op->getUsers()) {
        while (VPU::isPureViewOp(nextOp)) {
            if (!nextOp->hasOneUse()) {
                return false;
            }
            nextOp = *nextOp->getUsers().begin();
        }
        auto nceOp = mlir::dyn_cast<VPU::ClusteredOpInterface>(nextOp);
        if (nceOp == nullptr) {
            return false;
        }

        auto strategyAttr = nceOp.getMultiClusterStrategy();
        if (!strategyAttr.has_value()) {
            return false;
        }
        auto strategy = strategyAttr.value();
        if (strategy != VPU::MultiClusterStrategy::SplitOverHeight && strategy != VPU::MultiClusterStrategy::HKSwitch) {
            return false;
        }
        if (isDistributedOutputTypeOverlapped(nceOp, numClusters)) {
            return false;
        }
    }

    // Only support SOH and when numTiles is smaller than numClusters
    if (nTilesOnDim[Dims4D::Act::H] > numClusters) {
        return false;
    }
    // No tile on other axis
    if (nTilesOnDim[Dims4D::Act::C] != 1 || nTilesOnDim[Dims4D::Act::W] != 1) {
        return false;
    }
    return true;
}

mlir::LogicalResult vpux::VPU::DepthToSpaceOp::inferReturnTypes(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties, mlir::RegionRange /*regions*/,
        mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::DepthToSpaceOpAdaptor depthToSpace(operands, attrs);
    if (mlir::failed(depthToSpace.verify(loc))) {
        return mlir::failure();
    }

    const auto inShape = getShape(depthToSpace.getInput());
    const auto inType = depthToSpace.getInput().getType().cast<vpux::NDTypeInterface>();
    const auto block_size = depthToSpace.getBlockSize();

    const auto elemType = inType.getElementType();
    if (!(elemType.isF16() || elemType.isF32() || elemType.isUnsignedInteger(8) ||
          elemType.isa<mlir::quant::QuantizedType>())) {
        return errorAt(loc, "DepthToSpace only support FP16, FP32, U8 data type");
    }

    if (inShape.size() < 3) {
        return errorAt(loc, "Invalid input tensor shape, dimension must be greater than 2.");
    }

    if (block_size <= 0) {
        return errorAt(loc, "Invalid block size {0}, should be greater than zero", block_size);
    }

    if (inShape[Dims4D::Act::C] % (block_size * block_size) != 0) {
        return errorAt(loc, "Invalid block size {0}, which is not divisible by input shape {1}", block_size,
                       inShape[Dims4D::Act::C]);
    }

    size_t W_out = inShape[Dims4D::Act::W] * block_size;
    size_t H_out = inShape[Dims4D::Act::H] * block_size;
    size_t C_out = inShape[Dims4D::Act::C] / (block_size * block_size);
    size_t N_out = inShape[Dims4D::Act::N];

    SmallVector<int64_t> outShape{checked_cast<int64_t>(N_out), checked_cast<int64_t>(C_out),
                                  checked_cast<int64_t>(H_out), checked_cast<int64_t>(W_out)};

    const auto outType = inType.changeShape(Shape(outShape));
    inferredReturnTypes.push_back(outType);

    return mlir::success();
}

//
// TilingBuilderOpInterface
//

vpux::InputTiling vpux::VPU::DepthToSpaceOp::backInferTileInfo(const vpux::TileInfo& outputTile, vpux::Logger) {
    const auto origInputShape = getShape(getInput());

    int64_t blockSize = 0;
    if (getBlockSizeAttr() != nullptr) {
        blockSize = getBlockSizeAttr().getValue().getSExtValue();
    }
    VPUX_THROW_WHEN(blockSize == 0, "BlockSize is zero and used as a divisor");

    TileInfo inputTile(origInputShape);
    inputTile.shape[Dims4D::Act::N] = outputTile.shape[Dims4D::Act::N];
    inputTile.shape[Dims4D::Act::C] = outputTile.shape[Dims4D::Act::C] * (blockSize * blockSize);
    inputTile.shape[Dims4D::Act::W] = outputTile.shape[Dims4D::Act::W] / blockSize;
    inputTile.shape[Dims4D::Act::H] = outputTile.shape[Dims4D::Act::H] / blockSize;

    inputTile.offsets[Dims4D::Act::N] = outputTile.offsets[Dims4D::Act::N];
    inputTile.offsets[Dims4D::Act::C] = outputTile.offsets[Dims4D::Act::C] * (blockSize * blockSize);
    inputTile.offsets[Dims4D::Act::W] = outputTile.offsets[Dims4D::Act::W] / blockSize;
    inputTile.offsets[Dims4D::Act::H] = outputTile.offsets[Dims4D::Act::H] / blockSize;

    return InputTiling{inputTile};
}

void vpux::VPU::DepthToSpaceOp::adjustAttrs(const TilingInfo& /*inputTiling*/, const TileInfo& /*outputTile*/) {
}

mlir::FailureOr<OutputTiling> getD2STilingStrategy(mlir::Operation* op, TilingMode tilingMode, bool useDMA,
                                                   Logger log) {
    auto origOp = mlir::dyn_cast<VPU::DepthToSpaceOp>(op);
    auto tilingInfo = mlir::dyn_cast<VPU::TilingInfoOpInterface>(op);

    const auto outputType = op->getResult(0).getType().cast<vpux::NDTypeInterface>();
    const auto outputShape = outputType.getShape();

    int64_t blockSize = 0;
    if (origOp.getBlockSizeAttr() != nullptr) {
        blockSize = origOp.getBlockSizeAttr().getValue().getSExtValue();
    }
    VPUX_THROW_WHEN(blockSize == 0, "BlockSize is zero and used as a divisor");

    Shape nTilesOnDimforDepthToSpace(outputShape.size(), 1);
    tilingMode = TilingMode::ISOLATED;
    const auto tilingModeToCheck = tilingMode;

    auto tileDimOrder = getTileDimOrder(op, tilingMode, log);

    auto tileDimIter = tileDimOrder.begin();
    auto dimToTile = *tileDimIter;

    const auto isSupportedTileSize = [op, &tilingInfo, outputShape, log](ShapeRef nTilesOnDim,
                                                                         TilingMode tilingMode) -> bool {
        const auto tiles = fillDividedTiles(op, nTilesOnDim, outputShape);
        if (mlir::failed(tiles)) {
            return false;
        }
        return tilingInfo.isSupportedTiling(tiles.value(), tilingMode, log);
    };

    int64_t maxTile = 1;

    while (tileDimIter < tileDimOrder.end()) {
        if (dimToTile == Dims4D::Act::H || dimToTile == Dims4D::Act::W) {
            while (((maxTile * blockSize) <= outputShape[dimToTile]) &&
                   (!isSupportedTileSize(nTilesOnDimforDepthToSpace, tilingModeToCheck))) {
                if (outputShape[dimToTile] % (maxTile * blockSize) == 0) {
                    nTilesOnDimforDepthToSpace[dimToTile] = maxTile;
                    maxTile++;
                } else {
                    maxTile++;
                }
            }
            dimToTile = *(++tileDimIter);
            maxTile = 1;
        } else if (dimToTile == Dims4D::Act::C) {
            while (!isSupportedTileSize(nTilesOnDimforDepthToSpace, tilingModeToCheck)) {
                if (nTilesOnDimforDepthToSpace[dimToTile] >= outputShape[dimToTile]) {
                    break;
                } else {
                    ++nTilesOnDimforDepthToSpace[dimToTile];
                }
            }
            dimToTile = *(++tileDimIter);
        }
    }

    // Explicit tiling not needed, op will be converted to multicluster DMA
    if (useDMA && isCompatibleWithMultiClusterNNDMA(origOp, nTilesOnDimforDepthToSpace)) {
        nTilesOnDimforDepthToSpace = vpux::Shape(outputShape.size(), 1);
    }

    auto origTiles = fillDividedTiles(op, nTilesOnDimforDepthToSpace, outputShape);
    return origTiles;
}

mlir::FailureOr<OutputTiling> vpux::VPU::DepthToSpaceOp::getTilingStrategy(TilingMode tilingMode, Logger log) {
    auto op = this->getOperation();
    auto useDMA = vpux::VPUIP::isLegalAndBeneficialConvertToDMA(op, log);
    return getD2STilingStrategy(op, tilingMode, useDMA, log);
}
