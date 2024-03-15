//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include <mlir/IR/Operation.h>
#include "vpux/compiler/dialect/IE/ops.hpp"

#pragma once

namespace vpux {
namespace VPU {

bool checkForQuantization(mlir::Operation* op, mlir::Operation* postOp);
void setHWClampOp(mlir::Operation* mainOp, mlir::Operation* activationOp);
bool isSupportedHWClampOp(mlir::Operation* mainOp, mlir::Operation* clampOp, const LogCb& logCb);

}  // namespace VPU
}  // namespace vpux
