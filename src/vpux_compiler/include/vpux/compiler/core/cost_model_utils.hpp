//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/dialect/IE/ops.hpp"
#include "vpux/compiler/dialect/VPUIP/dpu_tiler.hpp"

namespace vpux {

constexpr StringLiteral DPUCost = "minimumHardwareExecutionCost";
constexpr StringLiteral cycleCostAttrName = "cycleCost";
constexpr StringLiteral cycleBegin = "cycleBegin";
constexpr StringLiteral cycleEnd = "cycleEnd";

size_t getDMACost(mlir::Value input, mlir::Value output, VPU::ArchKind archKind,
                  std::shared_ptr<VPUNN::VPUCostModel> costModel);
size_t getDPUCost(mlir::Operation* op);
size_t getAsyncExecuteCycleBegin(mlir::async::ExecuteOp op);
size_t getAsyncExecuteCycleEnd(mlir::async::ExecuteOp op);
size_t calculateCopyCycles(mlir::Operation* innerOp, VPU::ArchKind archKind,
                           const std::shared_ptr<VPUNN::VPUCostModel> costModel);
size_t calculateShaveActCycles(VPUIP::SwKernelOp swKernelOp, const std::shared_ptr<VPUNN::VPUCostModel>& costModel,
                               VPU::ArchKind arch);
vpux::Byte getSwKernelRunTotalAllocSize(VPUIP::SwKernelRun swKernelRun, ArrayRef<mlir::Value> inputs,
                                        ArrayRef<mlir::Value> outputBuffs, SmallVector<mlir::Value>& inputsForKernelRun,
                                        SmallVector<mlir::Value>& outputsForKernelRun);
size_t getShaveActCycleForSwKernelOp(VPUIP::SwKernelOp swKernelOp, VPU::ArchKind arch, ArrayRef<mlir::Value> inputs,
                                     ArrayRef<mlir::Value> outputBuffs,
                                     const std::shared_ptr<VPUNN::VPUCostModel>& costModel);

}  // namespace vpux
