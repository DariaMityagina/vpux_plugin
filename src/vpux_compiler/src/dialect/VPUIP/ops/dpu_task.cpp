//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/core/cost_model_utils.hpp"
#include "vpux/compiler/dialect/VPUIP/ops.hpp"

using namespace vpux;

//
// DPUTaskOp
//

void vpux::VPUIP::DPUTaskOp::build(mlir::OpBuilder& builder, mlir::OperationState& state, mlir::ArrayAttr outStart,
                                   mlir::ArrayAttr outEnd, VPU::PaddingAttr pad, VPU::MPEMode mpeMode) {
    build(builder, state, outStart, outEnd, /*inStart=*/nullptr, /*inEnd=*/nullptr, pad, mpeMode,
          /*cluster_id=*/nullptr, /* workload_id =  */ nullptr);
}

void vpux::VPUIP::DPUTaskOp::build(mlir::OpBuilder& builder, mlir::OperationState& state, mlir::ArrayAttr outStart,
                                   mlir::ArrayAttr outEnd, VPU::PaddingAttr pad, VPU::MPEMode mpeMode,
                                   mlir::IntegerAttr clusterId) {
    build(builder, state, outStart, outEnd, /*inStart=*/nullptr, /*inEnd=*/nullptr, pad, mpeMode, clusterId,
          /* workload_id =  */ nullptr);
}

void vpux::VPUIP::DPUTaskOp::build(mlir::OpBuilder& builder, mlir::OperationState& state, mlir::ArrayAttr outStart,
                                   mlir::ArrayAttr outEnd, mlir::ArrayAttr inStart, mlir::ArrayAttr inEnd,
                                   VPU::PaddingAttr pad, VPU::MPEMode mpeMode) {
    build(builder, state, outStart, outEnd, inStart, inEnd, pad, mpeMode,
          /*cluster_id=*/nullptr, /* workload_id =  */ nullptr);
}

void vpux::VPUIP::DPUTaskOp::build(mlir::OpBuilder& builder, mlir::OperationState& state, mlir::ArrayAttr outStart,
                                   mlir::ArrayAttr outEnd, mlir::ArrayAttr inStart, mlir::ArrayAttr inEnd,
                                   VPU::PaddingAttr pad, VPU::MPEMode mpeMode, mlir::IntegerAttr clusterId) {
    build(builder, state, outStart, outEnd, inStart, inEnd, pad, mpeMode, clusterId,
          /* workload_id =  */ nullptr);
}

size_t vpux::VPUIP::DPUTaskOp::getOperationCycleCost(std::shared_ptr<VPUNN::VPUCostModel>& costModel) {
    auto dpuTaskOp = mlir::cast<VPUIP::DPUTaskOp>(this->getOperation());
    auto module = getOperation()->getParentOfType<mlir::ModuleOp>();

    // TODO: Expose API to get arch from cost model
    const auto arch = VPU::getArch(module);
    vpux::Logger log = Logger::global();

    return checked_cast<size_t>(getDPUTaskOpCost(dpuTaskOp, costModel, arch, log));
}
