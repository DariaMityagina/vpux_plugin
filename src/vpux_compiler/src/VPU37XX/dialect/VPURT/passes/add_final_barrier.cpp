//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/VPU37XX/dialect/VPURT/passes.hpp"
#include "vpux/compiler/core/barrier_info.hpp"
#include "vpux/compiler/core/cost_model_utils.hpp"
#include "vpux/compiler/dialect/VPURT/task.hpp"
#include "vpux/compiler/dialect/VPURT/utils/barrier_legalization_utils.hpp"
#include "vpux/compiler/utils/logging.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

using namespace vpux;

namespace {

class AddFinalBarrierPass final : public VPURT::arch37xx::AddFinalBarrierBase<AddFinalBarrierPass> {
public:
    explicit AddFinalBarrierPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
};

void AddFinalBarrierPass::safeRunOnFunc() {
    auto func = getOperation();

    auto findInsertPoint = [&]() {
        auto barrierOpsIt = func.getOps<VPURT::DeclareVirtualBarrierOp>();
        if (barrierOpsIt.empty()) {
            return &func.getBody().front().front();
        }
        auto numOfBarrierOp = std::distance(barrierOpsIt.begin(), barrierOpsIt.end());
        auto lastBarrierOpIter = barrierOpsIt.begin();
        for (auto i : irange(numOfBarrierOp - 1)) {
            VPUX_UNUSED(i);
            lastBarrierOpIter++;
        }
        auto lastBarrierOp = *lastBarrierOpIter;
        return lastBarrierOp.getOperation();
    };
    auto insertPoint = findInsertPoint();
    mlir::OpBuilder builder(func);
    builder.setInsertionPointAfter(insertPoint);
    auto loc = mlir::NameLoc::get(mlir::StringAttr::get(&getContext(), "finishing_barrier"));
    auto barrierOp = builder.create<VPURT::DeclareVirtualBarrierOp>(loc, mlir::UnitAttr::get(&getContext()));
    auto finalBarrier = barrierOp.getBarrier();

    auto& barrierInfo = getAnalysis<BarrierInfo>();
    barrierInfo.buildTaskControlMap();
    auto finalTasks = barrierInfo.getFinalTasks();
    for (auto& taskOp : finalTasks) {
        _log.trace("Add finishing barrier for {0}", taskOp->getLoc());
        taskOp.getUpdateBarriersMutable().append(finalBarrier);
    }
    barrierInfo.clearAttributes();

    VPURT::verifyBarrierSlots(func, _log);
}
}  // namespace

//
// createAddFinalBarrierPass
//

std::unique_ptr<mlir::Pass> vpux::VPURT::arch37xx::createAddFinalBarrierPass(Logger log) {
    return std::make_unique<AddFinalBarrierPass>(log);
}
