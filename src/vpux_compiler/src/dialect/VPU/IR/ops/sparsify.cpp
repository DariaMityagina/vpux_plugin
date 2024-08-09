//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
using namespace vpux;

mlir::LogicalResult vpux::VPU::SparsifyOp::inferReturnTypes(mlir::MLIRContext* ctx,
                                                            std::optional<mlir::Location> optLoc,
                                                            mlir::ValueRange operands, mlir::DictionaryAttr attrs,
                                                            mlir::OpaqueProperties prop, mlir::RegionRange /*regions*/,
                                                            mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::SparsifyOpAdaptor sparsify(operands, attrs, prop);
    if (mlir::failed(sparsify.verify(loc))) {
        return mlir::failure();
    }

    const auto inType = sparsify.getInput().getType().cast<mlir::RankedTensorType>();

    const auto outType = VPU::SparseTensorType::get(inType);
    inferredReturnTypes.push_back(outType);

    return mlir::success();
}
