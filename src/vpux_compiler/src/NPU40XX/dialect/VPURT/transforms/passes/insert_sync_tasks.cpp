//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/NPU40XX/dialect/VPURT/transforms/passes.hpp"
#include "vpux/compiler/dialect/VPUIP/utils/utils.hpp"
#include "vpux/compiler/dialect/VPURT/IR/task.hpp"
#include "vpux/compiler/utils/dma.hpp"
#include "vpux/compiler/utils/logging.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

using namespace vpux;

namespace {

VPURT::TaskOp createSyncDMA(mlir::OpBuilder& builder, mlir::Value input, mlir::Value outputBuf,
                            mlir::ValueRange waitBarriers, mlir::ValueRange updateBarriers) {
    auto ctx = builder.getContext();
    auto syncDmaLoc = mlir::NameLoc::get(mlir::StringAttr::get(ctx, "sync_dma"));
    auto zeroAttr = vpux::getIntAttr(ctx, 0);

    auto syncDMATask = VPURT::wrapIntoTaskOp<VPUIP::SyncDMAOp>(
            builder, waitBarriers, updateBarriers, syncDmaLoc, input, outputBuf, /*port*/ zeroAttr,
            /*isOutOfOrder*/ nullptr, /*isCritical*/ nullptr, /*dmaHwpId*/ nullptr,
            /*dmaProfilingMetaData*/ nullptr);
    return syncDMATask->getParentOfType<VPURT::TaskOp>();
}

// Insert sync task that mark start and end of each FuncOp.
// Example:
//
//        | op -> .. -> op |
// funcOp{| op -> .. -> op |}
//        | op -> .. -> op |
//
//                 =>
//
//        |          /-> op -> .. -> op -\           |
// funcOp{| SyncTask --> op -> .. -> op --> SyncTask |}
//        |          \-> op -> .. -> op -/           |
//
class InsertSyncTasksPass final : public VPURT::arch40xx::InsertSyncTasksBase<InsertSyncTasksPass> {
public:
    explicit InsertSyncTasksPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
};

void InsertSyncTasksPass::safeRunOnFunc() {
    auto func = getOperation();
    auto* ctx = func->getContext();
    mlir::OpBuilder builder(func);

    // Identify existing first or last DeclareBufferOp, TaskOp
    // and DeclareVirtualBarrierOp as they will be used as insertion points
    // for new tasks that will be inserted in IR
    auto bufferOps = func.getOps<VPURT::DeclareBufferOp>();
    auto bufferInsertionPoint = !bufferOps.empty() ? *bufferOps.begin() : &func.getBody().front().front();

    auto taskOps = func.getOps<VPURT::TaskOp>();
    if (taskOps.empty()) {
        // No tasks - no need for additional sync tasks
        return;
    }
    // Sync task insertion points would be at first task
    // and last task
    auto startSyncTaskInsertionPoint = *taskOps.begin();
    auto lastSyncTaskInsertionPointIt = taskOps.begin();
    std::advance(lastSyncTaskInsertionPointIt, std::distance(taskOps.begin(), taskOps.end()) - 1);
    auto lastSyncTaskInsertionPoint = *lastSyncTaskInsertionPointIt;

    auto barriersOps = func.getOps<VPURT::DeclareVirtualBarrierOp>();

    mlir::Operation* firstBarrierInsertionPoint = &func.getBody().front().front();
    mlir::Operation* lastBarrierInsertionPoint = &func.getBody().front().front();

    // Sync tasks barriers insertion points would be at first barrier
    // and last barrier
    if (!barriersOps.empty()) {
        firstBarrierInsertionPoint = *barriersOps.begin();
        auto lastBarrierInsertionPointIt = barriersOps.begin();
        std::advance(lastBarrierInsertionPointIt, std::distance(barriersOps.begin(), barriersOps.end()) - 1);
        lastBarrierInsertionPoint = *lastBarrierInsertionPointIt;
    }

    // Create new barriers that will mark the start and end of schedule
    // in this function. Those barriers will be produced/consumed by sync tasks
    builder.setInsertionPoint(firstBarrierInsertionPoint);
    auto newStartBarrier = builder.create<VPURT::DeclareVirtualBarrierOp>(
            mlir::NameLoc::get(mlir::StringAttr::get(ctx, "start_barrier")));

    builder.setInsertionPointAfter(lastBarrierInsertionPoint);
    auto newEndBarrier = builder.create<VPURT::DeclareVirtualBarrierOp>(
            mlir::NameLoc::get(mlir::StringAttr::get(ctx, "end_barrier")));

    // Create dummy input and output buffer that will hold value of size 0
    auto inBuffer = VPUIP::createDummyBuffer(builder, bufferInsertionPoint);
    auto outBuffer = VPUIP::createDummyBuffer(builder, bufferInsertionPoint);

    // Identify first and last task on each execution queue.
    // For first tasks if they do no wait on any barrier connect them with start barrier
    // For end tasks if they do not update any barrier connect then to end barrier
    for (auto& taskQueuesFirstAndLastOp : VPURT::getTaskQueuesFirstAndLastOp(func)) {
        auto queueFirstOp = taskQueuesFirstAndLastOp.second.first;
        auto queueLastOp = taskQueuesFirstAndLastOp.second.second;
        if (queueFirstOp.getWaitBarriers().empty()) {
            queueFirstOp.getWaitBarriersMutable().assign(newStartBarrier);
        }

        if (queueLastOp.getUpdateBarriers().empty()) {
            queueLastOp.getUpdateBarriersMutable().assign(newEndBarrier);
        }
    }

    // Create start sync task which will produce start barrier
    builder.setInsertionPoint(startSyncTaskInsertionPoint);
    createSyncDMA(builder, inBuffer, outBuffer, {}, {newStartBarrier});

    // Create end sync task which will consume end barrier
    builder.setInsertionPointAfter(lastSyncTaskInsertionPoint);
    createSyncDMA(builder, inBuffer, outBuffer, {newEndBarrier}, {});
}
}  // namespace

//
// createInsertSyncTasksPass
//

std::unique_ptr<mlir::Pass> vpux::VPURT::arch40xx::createInsertSyncTasksPass(Logger log) {
    return std::make_unique<InsertSyncTasksPass>(log);
}
