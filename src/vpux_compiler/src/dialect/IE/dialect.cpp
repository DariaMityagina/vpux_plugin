//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/dialect.hpp"
#include "vpux/compiler/dialect/IE/ops.hpp"

#include "vpux/compiler/dialect/const/ops.hpp"
#include "vpux/compiler/utils/error.hpp"

#include <mlir/IR/TensorEncoding.h>
#include <mlir/Interfaces/DecodeAttributesInterfaces.h>

using namespace vpux;

namespace {

//
// IEAsmHooks
//

class IEAsmHooks final : public mlir::OpAsmDialectInterface {
public:
    using mlir::OpAsmDialectInterface::OpAsmDialectInterface;

public:
    AliasResult getAlias(mlir::Attribute attr, llvm::raw_ostream& os) const final;
    AliasResult getAlias(mlir::Type type, llvm::raw_ostream& os) const final;
};

IEAsmHooks::AliasResult IEAsmHooks::getAlias(mlir::Attribute attr, llvm::raw_ostream& os) const {
    if (const auto mapAttr = attr.dyn_cast<mlir::AffineMapAttr>()) {
        const auto map = mapAttr.getValue();

        if (map.isPermutation()) {
            const auto dimsOrder = DimsOrder::fromAffineMap(map);

            if (const auto name = dimsOrder.getCanonicalName()) {
                os << name.getValue();
                return AliasResult::FinalAlias;
            }
        }
    }

    return AliasResult::NoAlias;
}

IEAsmHooks::AliasResult IEAsmHooks::getAlias(mlir::Type type, llvm::raw_ostream& os) const {
    if (type.isa<mlir::quant::QuantizedType>()) {
        os << "qElemType";
        return AliasResult::OverridableAlias;
    }

    return AliasResult::NoAlias;
}

//
// TensorEncodingVerifier
//

class TensorEncodingVerifier final :
        public mlir::VerifiableTensorEncoding::ExternalModel<TensorEncodingVerifier, IE::TensorAttr> {
public:
    using ConcreteEntity = mlir::DictionaryAttr;

    mlir::LogicalResult verifyEncoding(mlir::Attribute attr, ArrayRef<int64_t> shape, mlir::Type,
                                       FuncRef<mlir::InFlightDiagnostic()> emitError) const {
        const auto desc = attr.dyn_cast<IE::TensorAttr>();

        if (desc == nullptr) {
            return printTo(emitError(), "Unsupported TensorType encoding '{0}'", attr);
        }

        if (const auto orderAttr = desc.order()) {
            const auto map = orderAttr.getValue();

            if (!map.isPermutation()) {
                return printTo(emitError(), "TensorType order '{0}' is not a permutation", map);
            }

            if (checked_cast<size_t>(map.getNumResults()) != shape.size()) {
                return printTo(emitError(), "TensorType order '{0}' doesn't match to shape '{1}'", map, shape);
            }
        }

        return mlir::success();
    }
};

}  // namespace

//
// initialize
//

void vpux::IE::IEDialect::initialize() {
    addOperations<
#define GET_OP_LIST
#include <vpux/compiler/dialect/IE/generated/ops.cpp.inc>
            >();

    addInterfaces<IEAsmHooks>();

    IE::TensorAttr::attachInterface<TensorEncodingVerifier>(*getContext());

    registerAttributes();
}

//
// materializeConstant
//

mlir::Operation* vpux::IE::IEDialect::materializeConstant(mlir::OpBuilder& builder, mlir::Attribute value,
                                                          mlir::Type type, mlir::Location loc) {
    if (!value.isa<Const::ContentAttr>()) {
        (void)errorAt(loc, "Can't materialize IE Constant from Attribute '{0}'", value);
        return nullptr;
    }

    if (!type.isa<mlir::RankedTensorType>()) {
        (void)errorAt(loc, "Can't materialize IE Constant for Type '{0}'", type);
        return nullptr;
    }

    return builder.create<Const::DeclareOp>(loc, type, value.cast<Const::ContentAttr>());
}

//
// Generated
//

#include <vpux/compiler/dialect/IE/generated/dialect.cpp.inc>
