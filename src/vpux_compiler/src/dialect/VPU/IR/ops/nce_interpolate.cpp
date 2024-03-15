//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/const_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/distributed_tensor_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/explicit_distribution_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/generate_tiling.hpp"
#include "vpux/compiler/dialect/VPU/utils/nce_interpolate_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/nce_invariant.hpp"
#include "vpux/compiler/dialect/VPU/utils/nce_sparsity.hpp"

#include "vpux/compiler/core/attributes/shape.hpp"
#include "vpux/compiler/core/layers.hpp"

#include "vpux/compiler/utils/empty_node.hpp"

#include <openvino/core/validation_util.hpp>

using namespace vpux;

//
// InferTypeOpInterface
//

mlir::LogicalResult vpux::VPU::NCEInterpolateOp::inferReturnTypes(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties, mlir::RegionRange,
        mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    NCEInterpolateOpAdaptor op(operands, attrs);
    if (mlir::failed(op.verify(loc))) {
        return mlir::failure();
    }

    auto inShape = getShape(op.getInput());

    const auto dataDilations = ov::Strides({1, 1});
    const auto dataPaddingBelow = ov::CoordinateDiff({0, 0});
    const auto dataPaddingAbove = ov::CoordinateDiff({0, 0});
    const auto filterShape = Shape(parseIntArrayAttr<int64_t>(op.getRawFilterShape()));
    const auto filterStrides = Shape(parseIntArrayAttr<int64_t>(op.getStrides()));
    const auto filterDilations = ov::Strides({1, 1});

    const auto outputShapeNG = ov::infer_convolution_forward(
            EmptyNode::instance(), ov::Shape(inShape.begin(), inShape.end()), dataDilations, dataPaddingBelow,
            dataPaddingAbove, ov::Shape(filterShape.begin(), filterShape.end()),
            ov::Strides(filterStrides.begin(), filterStrides.end()), filterDilations);

    const auto outShape = to_small_vector(outputShapeNG.get_shape() | transformed([](size_t val) {
                                              return checked_cast<int64_t>(val);
                                          }));

    auto inType = op.getInput().getType();

    // Output type is independent of input type - if the input type is sparse, the output type is not guaranteed to be
    // sparse as well
    if (auto sparseInputType = inType.cast<VPU::SparseTensorType>()) {
        inType = sparseInputType.getData();
    }

    auto outType = inType.cast<vpux::NDTypeInterface>().changeShape(Shape(outShape));

    inferredReturnTypes.push_back(outType);
    return mlir::success();
}

//
// Verifier
//

mlir::LogicalResult vpux::VPU::NCEInterpolateOp::verify() {
    auto sparseInput = getInput().getType().dyn_cast<VPU::SparseTensorType>();
    if (sparseInput == nullptr) {
        return mlir::failure();
    }

    auto seAttr = sparseInput.getSeAttr().dyn_cast_or_null<VPU::SEInterpolateAttr>();
    if (seAttr == nullptr) {
        return mlir::failure();
    }

    return mlir::success();
}

//
// NCEOpInterface
//

SmallVector<int64_t> vpux::VPU::NCEInterpolateOp::getKernelSizeVal() {
    const auto kernelShape = Shape(parseIntArrayAttr<int64_t>(getRawFilterShape()));

    const auto KY = kernelShape[Dims4D::Filter::KY];
    const auto KX = kernelShape[Dims4D::Filter::KX];

    return {KY, KX};
}

SmallVector<int64_t> vpux::VPU::NCEInterpolateOp::getStridesVal() {
    return parseIntArrayAttr<int64_t>(getStrides());
}

vpux::VPU::PaddingAttr vpux::VPU::NCEInterpolateOp::getPad() {
    return VPU::getPaddingAttr(getContext(), PadInfo(0, 0, 0, 0));
}

bool isNCEInterpolateSupported(vpux::NDTypeInterface inputType, vpux::NDTypeInterface outputType,
                               IE::InterpolateAttr attr, VPU::ArchKind arch, bool checkLayout,
                               bool checkChannelAlignment, vpux::LogCb logCb) {
    // TODO E#71403: remove dimension check
    auto dimOver8K = [](ShapeRef shape) {
        for (auto dim : shape) {
            if (dim > VPU::NCEInvariant::VPU_DIMENSION_LIMIT) {
                return true;
            }
        }
        return false;
    };
    auto inputShape = inputType.getShape();
    auto outputShape = outputType.getShape();
    if (dimOver8K(inputShape) || dimOver8K(outputShape)) {
        logCb(formatv("Dimension sizes over 8192 are not supported. Input shape {0}, output shape {1}", inputShape,
                      outputShape));
        return false;
    }

    if (attr == nullptr) {
        logCb(formatv("Missing Interpolate configuration information"));
        return false;
    }

    // Antialias is not supported
    if (attr.getAntialias() != nullptr && attr.getAntialias().getValue() == true) {
        logCb(formatv("Antialias is not supported"));
        return false;
    }

    // Only 4D interpolates are supported and the interpolation axes must be H and/or W
    auto potentialScales = VPU::getNCEInterpolateScales(inputType, outputType, attr.getCoordMode());
    if (!potentialScales.has_value()) {
        return false;
    }
    const auto scales = potentialScales.value();

    if (inputShape[Dims4D::Act::C] < 8) {
        // Interpolate layers with fewer than 8 channels may perform better on SHAVE than on DPU #E100988
        // A better cost model can be introduced in the future to clearly identify which scenarios
        // receive a hit in performance when executed on DPU
        logCb(formatv("Interpolate has less than than 8 channels: {0}", inputShape[Dims4D::Act::C]));
        return false;
    }

    // Check for the supported modes
    SmallVector<IE::InterpolateMode> supportedModes = {IE::InterpolateMode::NEAREST, IE::InterpolateMode::LINEAR,
                                                       IE::InterpolateMode::LINEAR_ONNX};
    if (llvm::find(supportedModes, attr.getMode().getValue()) == supportedModes.end()) {
        logCb(formatv("Mode {0} is not supported", attr.getMode().getValue()));
        return false;
    }

    // TODO E#107568: Add support for LINEAR TF_HALF_PIXEL_FOR_NN mode
    if (attr.getMode().getValue() == IE::InterpolateMode::LINEAR ||
        attr.getMode().getValue() == IE::InterpolateMode::LINEAR_ONNX) {
        if (attr.getCoordMode().getValue() == IE::InterpolateCoordMode::TF_HALF_PIXEL_FOR_NN) {
            logCb(formatv("Bilinear InterpolateOp with coordinate transformation mode {0} is not yet supported",
                          attr.getCoordMode().getValue()));
            return false;
        }
    }

    // TODO E#83681: Add support for NEAREST ALIGN_CORNERS mode
    if (attr.getMode().getValue() == IE::InterpolateMode::NEAREST) {
        if (attr.getCoordMode().getValue() == IE::InterpolateCoordMode::ALIGN_CORNERS) {
            logCb(formatv("Coordinate transformation mode {0} is not yet supported", attr.getCoordMode().getValue()));
            return false;
        }
    }

    // Only interpolate ops without padding are supported
    auto hasNonZeroPads = [&](mlir::ArrayAttr padsAttr) -> bool {
        if (padsAttr == nullptr) {
            return false;
        }
        auto pads = parseIntArrayAttr<int64_t>(padsAttr);
        return llvm::any_of(pads, [](int64_t pad) {
            return pad != 0;
        });
    };
    if (hasNonZeroPads(attr.getPadsBegin()) || hasNonZeroPads(attr.getPadsEnd())) {
        logCb(formatv("Padding is not supported"));
        return false;
    }

    // kernelSize must be in range [1-11]
    const auto kernelSize = VPU::getNCEInterpolateKernelSize(scales, VPU::getNCEInterpolateModeAttr(attr.getMode()),
                                                             attr.getCoordMode());
    for (auto kernel : kernelSize) {
        if (kernel > VPU::NCEInvariant::MAX_KERNEL_SIZE || kernel <= 0) {
            logCb(formatv("Only kernel size less than {0} are supported for nce interpolate. Got kernel Size {1}",
                          VPU::NCEInvariant::MAX_KERNEL_SIZE, kernel));
            return false;
        }
    }

    if (checkChannelAlignment) {
        if (!VPU::NCEInvariant::isInputActTypeSupported(arch, inputType,
                                                        VPU::NCEInterpolateOp::getInputChannelAlignmentImpl(inputType),
                                                        /*supportsInputActCompression=*/false) ||
            !VPU::NCEInvariant::isOutputActTypeSupported(
                    outputType, VPU::NCEInterpolateOp::getOutputChannelAlignmentImpl(outputType))) {
            logCb(formatv("Misaligned tensor shape"));
            return false;
        }
    }

    if (checkLayout) {
        if (!VPU::NCEInvariant::checkLayouts({inputType}, {outputType}, arch, 1, logCb)) {
            return false;
        }
    }

    return true;
}

bool VPU::NCEInterpolateOp::isSupported(IE::InterpolateOp op, vpux::LogCb logCb, bool checkLayout,
                                        bool checkChannelAlignment) {
    auto inputType = op.getInput().getType().cast<vpux::NDTypeInterface>();
    auto outputType = op.getOutput().getType().cast<vpux::NDTypeInterface>();
    return isNCEInterpolateSupported(inputType, outputType, op.getAttr(), VPU::getArch(op), checkChannelAlignment,
                                     checkLayout, logCb);
}

bool VPU::NCEInterpolateOp::isSupported(VPU::InterpolateOp op, vpux::LogCb logCb, bool checkLayout,
                                        bool checkChannelAlignment) {
    auto inputType = op.getInput().getType().cast<vpux::NDTypeInterface>();
    auto outputType = op.getOutput().getType().cast<vpux::NDTypeInterface>();
    return isNCEInterpolateSupported(inputType, outputType, op.getAttr(), VPU::getArch(op), checkChannelAlignment,
                                     checkLayout, logCb);
}

mlir::LogicalResult vpux::VPU::NCEInterpolateOp::verifyInputType(vpux::NDTypeInterface inputType) {
    return mlir::success(vpux::VPU::NCEInvariant::isInputActTypeSupported(
            VPU::getArch(*this), inputType, getInputChannelAlignment(), /*supportsInputActCompression=*/false));
}

//
// TilingBuilderOpInterace
//

TilingInfo vpux::VPU::NCEInterpolateOp::backInferTileInfo(const vpux::TileInfo& outputTile, vpux::Logger log) {
    const auto origInputShape = getShape(getInput());
    const auto origFilterShape = Shape(parseIntArrayAttr<int64_t>(getRawFilterShape()));

    // This op incorporates bias values in WeightsTable
    const auto origBiasShape = ShapeRef();
    const auto strides = getIntArrayAttr(getContext(), getStridesVal());
    const auto padding = VPU::toPadInfo(getPad());

    auto inputTiling = backInferConvTile(outputTile, origInputShape, origFilterShape, origBiasShape, strides, padding);
    VPUX_THROW_UNLESS(mlir::succeeded(checkAndAlignActInputTiling(
                              mlir::cast<VPU::NCEOpInterface>(*this->getOperation()), inputTiling, log)),
                      "Failed to get an aligned act input tiling");

    // Adjust filter tile for the aligned filter
    inputTiling.tiles[1].shape = getShape(getWeights()).toValues();
    inputTiling.tiles[1].shape[Dims4D::Filter::OC] = outputTile.shape[Dims4D::Act::C];

    inputTiling.tiles.push_back(VPU::getWeightsTableTile(this, outputTile));

    return inputTiling;
}

void vpux::VPU::NCEInterpolateOp::adjustAttrs(const vpux::TilingInfo&, const vpux::TileInfo& outputTile) {
    // Same as NCEConvolution, but without padding
    VPU::adjustRawFilterShape(this, outputTile);
}

mlir::FailureOr<OutputTiling> vpux::VPU::NCEInterpolateOp::getTilingStrategy(TilingMode tilingMode, Logger log) {
    return vpux::getHWLayerTilingStrategy(this->getOperation(), tilingMode, log);
}

//
// ClusteredOpInterface
//

bool vpux::VPU::NCEInterpolateOp::checkStrategyCompatibility(vpux::VPU::MultiClusterStrategy strategy) {
    return strategy == VPU::MultiClusterStrategy::Clustering ||
           strategy == VPU::MultiClusterStrategy::SplitOverHeight ||
           strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::HKSwitch;
}

vpux::VPU::DistributedTensorAttr vpux::VPU::NCEInterpolateOp::getExplicitDistributedTensorAttr(
        vpux::ShapeRef shape, vpux::VPU::DistributionMode distributionMode, mlir::ArrayAttr numTiles,
        mlir::IntegerAttr numClusters, mlir::ArrayAttr alignment, mlir::ArrayAttr kernel, vpux::VPU::PaddingAttr pad,
        mlir::ArrayAttr stride, mlir::UnitAttr uniformDistributedSegments) {
    return VPU::getNCEExplicitDistributedTensorAttr(mlir::dyn_cast<VPU::NCEOpInterface>(getOperation()), shape,
                                                    distributionMode, numTiles, numClusters, alignment, kernel, pad,
                                                    stride, uniformDistributedSegments);
}

// Each cluster should compute at least one output line. Therefore in order for a layer to be SOH
// compatible it must have an output height of at least the number of clusters
// specified for compilation.
// For example for 4 cluster compilation the output height must be a minimum of 4.
bool VPU::NCEInterpolateOp::isOperationSplitOverHeightCompatible(const vpux::TileInfo& oriOutputTile) {
    auto outputShape = ShapeRef(oriOutputTile.shape);
    auto offset = ShapeRef(oriOutputTile.offsets);
    auto axis = ShapeRef(oriOutputTile.axis);
    if (outputShape == ShapeRef()) {
        outputShape = getShape(getOutput());
    }
    vpux::TileInfo outputTile{outputShape, offset, axis, oriOutputTile.isCompletedTile};
    if (!VPU::isOperationSplitOverHeightCompatible(getOperation(), outputTile)) {
        return false;
    }

    auto nceOp = mlir::cast<NCEInterpolateOp>(getOperation());
    Shape inputShape = getShape(nceOp.getInput()).toValues();
    auto inputType = nceOp.getInput().getType().cast<NDTypeInterface>();
    // If has custom output shape, infer the input shape
    if (outputShape != getShape(nceOp->getResult(0))) {
        VPUX_THROW_UNLESS(offset != ShapeRef() && axis != ShapeRef(),
                          "Offsets and axis must have value when create TileInfo. Loc: {0}", nceOp->getLoc());
        outputTile.isCompletedTile = true;
        auto computerShape = nceOp.backInferTileInfo(outputTile, Logger::global());
        inputShape = computerShape.tiles.front().shape;
        auto inputOffset = computerShape.tiles.front().offsets;
        inputType = inputType.extractDenseTile(inputOffset, inputShape);
    }

    auto moduleOp = nceOp->getParentOfType<mlir::ModuleOp>();
    auto tileOp = IE::getTileExecutor(moduleOp);
    const auto numTiles = tileOp.getCount();

    return isSOHSupportedByDPU(inputType, inputShape, numTiles, false, VPU::getArch(nceOp.getOperation()));
}

bool VPU::NCEInterpolateOp::isOperationSplitOverWidthCompatible(ShapeRef outputShape, ShapeRef offset, ShapeRef axis) {
    return VPU::isOperationSplitOverWidthCompatible(getOperation(), outputShape, offset, axis);
}

bool VPU::NCEInterpolateOp::isOperationSplitOverKernelCompatible(ShapeRef outputShape, ShapeRef offset, ShapeRef axis) {
    return VPU::isOperationSplitOverKernelCompatible(getOperation(), outputShape, offset, axis);
}

bool VPU::NCEInterpolateOp::doesLayerFitIntoCMX(VPU::MultiClusterStrategy strategy, Byte reservedMem) {
    auto nceOp = mlir::cast<VPU::NCEInterpolateOp>(getOperation());
    const auto outputType = nceOp->getResult(0).getType().cast<vpux::NDTypeInterface>();
    auto numClusters = VPU::getOptimalNumClusters(nceOp, outputType.getShape()[Dims4D::Act::C], strategy);
    auto distInputType = getDistributedActivationTypeFromOp(nceOp, nceOp.getInput().getType(), numClusters, strategy);
    auto distFilterType =
            (nceOp.getWeights() != nullptr)
                    ? getDistributedFilterTypeFromOp(nceOp, nceOp.getWeights().getType(), numClusters, strategy)
                    : nullptr;
    auto distOutputType = getDistributedOutputTypeFromOp(nceOp, nceOp.getOutput().getType(), numClusters, strategy);
    return fitIntoCMX(distInputType, distFilterType, distOutputType, reservedMem);
}

bool VPU::NCEInterpolateOp::doesLayerChangeOutputAlignmentFitIntoCMX(
        VPU::MultiClusterStrategy strategy, VPU::DistributedTypeInterface newDistributedTensorType) {
    auto nceOp = mlir::cast<NCEInterpolateOp>(getOperation());
    auto numClusters = VPU::getOptimalNumClusters(
            nceOp, nceOp.getOutput().getType().cast<vpux::NDTypeInterface>().getShape()[Dims4D::Act::C], strategy);
    auto distributedInputType =
            getDistributedActivationTypeFromOp(nceOp, nceOp.getInput().getType(), numClusters, strategy);
    auto distributedFilterType =
            (nceOp.getWeights() != nullptr)
                    ? getDistributedFilterTypeFromOp(nceOp, nceOp.getWeights().getType(), numClusters, strategy)
                    : nullptr;
    return fitIntoCMX(distributedInputType, distributedFilterType, newDistributedTensorType);
}

//
// fitIntoCMX
//

bool vpux::VPU::NCEInterpolateOp::fitIntoCMX(vpux::NDTypeInterface input, vpux::NDTypeInterface filter,
                                             vpux::NDTypeInterface output) {
    return fitIntoCMX(input, filter, output, Byte(0));
}

bool vpux::VPU::NCEInterpolateOp::fitIntoCMX(vpux::NDTypeInterface input, vpux::NDTypeInterface filter,
                                             vpux::NDTypeInterface output, Byte reservedMem) {
    const auto OC = output.getShape()[Dims4D::Act::C];
    SmallVector<Byte> buffers = {input.getTotalAllocSize(), filter.getTotalAllocSize(), output.getTotalAllocSize(),
                                 NCEInvariant::getWeightsTableSize(OC)};

    auto totalAvailableCMXSize = reservedMem.count() == 0 ? getTotalCMXSize(getOperation()).count()
                                                          : getTotalCMXFragmentationAwareSize(getOperation()).count();

    return vpux::VPU::calculateAlignedBuffersMemoryRequirement(getArch(getOperation()), buffers).count() +
                   reservedMem.count() <=
           totalAvailableCMXSize;
}

//
// SparseOpInterface
//

vpux::VPU::SparsitySupport vpux::VPU::NCEInterpolateOp::sparsitySupport() {
    // Super-dense mode does not support ODU sparsity
    const auto arch = getArch(getOperation());
    const auto outputType = getOutput().getType().cast<vpux::NDTypeInterface>();

    auto excludeMode = VPU::NCESparsity::bitwiseNot(VPU::SparsitySupport::NONE);

    if (VPU::NCESparsity::isSuperdenseRequired(arch, outputType.getDimsOrder(), outputType.getShape(),
                                               outputType.getElementType())) {
        excludeMode = VPU::NCESparsity::bitwiseNot(VPU::SparsitySupport::SPARSE_OUTPUTS);
    }

    switch (arch) {
    case VPU::ArchKind::VPUX30XX: {
        // Layout will always be NHWC for VPUX30XX.
        return (VPU::SparsitySupport::SPARSE_INPUTS | VPU::SparsitySupport::SPARSE_WEIGHTS) & excludeMode;
    }

    case VPU::ArchKind::VPUX37XX:
        return NCESparsity::FULLY_SUPPORTED_SPARSITY_MODE & excludeMode;

    default:
        VPUX_THROW("Unknown sparsity support mode for {0}", arch);
    }
}
