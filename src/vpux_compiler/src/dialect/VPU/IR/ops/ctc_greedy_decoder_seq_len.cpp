//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"

#include "vpux/compiler/utils/error.hpp"

using namespace vpux;

mlir::LogicalResult vpux::VPU::CTCGreedyDecoderSeqLenOp::inferReturnTypes(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties prop, mlir::RegionRange /*regions*/,
        mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::CTCGreedyDecoderSeqLenOpAdaptor ctc(operands, attrs, prop);
    if (mlir::failed(ctc.verify(loc))) {
        return mlir::failure();
    }

    const auto inType = ctc.getInput().getType().cast<vpux::NDTypeInterface>();
    const auto inShape = inType.getShape().raw();

    if (inShape.size() != 3) {
        return errorAt(loc, "First input tensor should have 3 dimensions");
    }

    const auto outElemType = ctc.getSequenceLength().getType().cast<vpux::NDTypeInterface>().getElementType();

    SmallVector<int64_t> outputShape{inShape[0], inShape[1]};
    SmallVector<int64_t> outputLengthShape{inShape[0]};

    auto outType = inType.changeElemType(outElemType);

    outType = outType.changeShape(Shape(outputShape));
    inferredReturnTypes.push_back(outType);

    outType = outType.changeShape(Shape(outputLengthShape));
    inferredReturnTypes.push_back(outType);

    return mlir::success();
}
