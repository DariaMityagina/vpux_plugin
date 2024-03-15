//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"

#include "vpux/compiler/utils/error.hpp"

using namespace vpux;

mlir::LogicalResult vpux::VPU::PerAxisTileOp::inferReturnTypes(mlir::MLIRContext* ctx,
                                                               std::optional<mlir::Location> optLoc,
                                                               mlir::ValueRange operands, mlir::DictionaryAttr attrs,
                                                               mlir::OpaqueProperties, mlir::RegionRange /*regions*/,
                                                               mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::PerAxisTileOpAdaptor perAxisTile(operands, attrs);
    if (mlir::failed(perAxisTile.verify(loc))) {
        return mlir::failure();
    }

    const auto inType = perAxisTile.getInput().getType().cast<vpux::NDTypeInterface>();

    const auto axis = checked_cast<unsigned int>(perAxisTile.getAxis());
    const auto tiles = checked_cast<unsigned int>(perAxisTile.getTiles());

    auto outShape = to_small_vector(inType.getShape().raw());

    if (axis > outShape.size()) {
        return errorAt(loc, "Axis is out of range. Available range [0, {0}), but got axis = {1}", outShape.size(),
                       axis);
    }

    outShape[axis] *= tiles;

    const auto outType = inType.changeShape(Shape(outShape));

    inferredReturnTypes.push_back(outType);

    return mlir::success();
}
