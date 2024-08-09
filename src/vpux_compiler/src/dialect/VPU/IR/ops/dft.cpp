//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"

#include "vpux/compiler/core/tiling.hpp"
#include "vpux/compiler/utils/attributes.hpp"

using namespace vpux;

mlir::LogicalResult vpux::VPU::DFTOp::inferReturnTypes(mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc,
                                                       mlir::ValueRange operands, mlir::DictionaryAttr attrs,
                                                       mlir::OpaqueProperties prop, mlir::RegionRange /*regions*/,

                                                       mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));
    VPU::DFTOpAdaptor op(operands, attrs, prop);
    if (mlir::failed(op.verify(loc))) {
        return mlir::failure();
    }

    auto axes = parseIntArrayAttr<int64_t>(op.getAxesAttr());
    auto signalSize = parseIntArrayAttr<int64_t>(op.getSignalSizeAttr());

    const auto inType = op.getInput().getType().cast<vpux::NDTypeInterface>();
    auto outShape = to_small_vector(inType.getShape());

    for (size_t i = 0; i < axes.size(); ++i) {
        if (signalSize[i] != -1) {
            outShape[axes[i]] = signalSize[i];
        }
    }

    auto outType = inType.changeShape(Shape(outShape));
    inferredReturnTypes.push_back(outType);
    return mlir::success();
}

//
// TilingBuilderOpInterface
//

vpux::InputTiling vpux::VPU::DFTOp::backInferTileInfo(const vpux::TileInfo& outputTile, vpux::Logger /*log*/) {
    auto curTile = outputTile;
    auto axes = parseIntArrayAttr<int64_t>(getAxesAttr());
    const auto inShape = getShape(getInput());
    for (auto axis : axes) {
        curTile.shape[Dim(axis)] = inShape[Dim(axis)];
    }
    TileInfo twiddleTile(getShape(getTwiddleFactors()));
    return TilingInfo{{std::move(curTile), std::move(twiddleTile)}};
}

void vpux::VPU::DFTOp::adjustAttrs(const TilingInfo& /*inputTiling*/, const TileInfo& /*outputTile*/) {
}

mlir::FailureOr<OutputTiling> vpux::VPU::DFTOp::getTilingStrategy(TilingMode tilingMode, Logger log) {
    auto op = getOperation();
    // eliminate axes from possible tiling dims
    auto axes = parseIntArrayAttr<int64_t>(getAxesAttr());
    // add last axis to not allowed split as represent the complex number
    const auto outputType = op->getResult(0).getType().cast<vpux::NDTypeInterface>();
    const auto outputShape = outputType.getShape();
    axes.push_back(outputShape.size() - 1);

    return getSWLayerTilingStrategy(op, tilingMode, log, getMaxNumTilesWithAxesExclusion(op, axes));
}
