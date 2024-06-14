//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/core/layers.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/transforms/passes.hpp"

using namespace vpux;
using namespace VPU;

namespace {

// For arch 40XX, output workloads need to be relative to the start of the output in the current cluster and
// take overlap (halo) received from other clusters into consideration.
// When output is SOK or HKSwitch, there is no need to shift the workloads since the output sub-tensors are
// all concatenated in each cluster and the workloads already reflect that.
// When output is Distributed OVERLAPPED, having an overlap section (W or H) brought from another cluster
// at the beginning of the current one means we have to shift the workloads with the size of the overlap.
// NCEPermute with SOK(SOC) is actually SOH after being lowered to NCEEltwise, so also need correction here.
bool needsHaloWorkloadsCorrection(VPU::NCEOpInterface nceOp, VPU::DistributedTypeInterface outputTypes) {
    if (!outputTypes.containsDistributedTypes()) {
        return false;
    }

    auto distributedOutType = outputTypes.getDistributedTypes().begin()->cast<VPU::DistributedTensorType>();
    auto distributionAttr = distributedOutType.getDistribution();
    auto distributionMode = distributionAttr.getMode().getValue();

    // NCEPermute is the only exception because real SOC cases were already processed
    // when spliting nce workloads in SplitNCEOpsOntoWorkloadsPass.
    return distributionMode == VPU::DistributionMode::OVERLAPPED ||
           (mlir::isa<VPU::NCEPermuteOp>(nceOp) && isSegmentedOverC(distributionAttr));
}

// Get offset from start of the cluster along W,H,C axes.
// Returns a vector of offsets for each cluster.
SmallVector<SmallVector<int64_t>> getClusteringOffsets(VPU::DistributedTensorType distributedOut) {
    auto numClusters = distributedOut.getDistribution().getNumClusters().getInt();

    SmallVector<SmallVector<int64_t>> perClusterWorkloadOffsets(numClusters);

    const auto perClusterMemoryOffsets = distributedOut.getPerClusterMemoryShapeOffsets();
    const auto perClusterComputeOffsets = distributedOut.getPerClusterComputeShapeOffsets();

    for (auto clusterId : irange(numClusters)) {
        perClusterWorkloadOffsets[clusterId] = SmallVector<int64_t>{
                perClusterMemoryOffsets[clusterId][Dims4D::Act::N],
                std::min(perClusterMemoryOffsets[clusterId][Dims4D::Act::C],
                         perClusterComputeOffsets[clusterId][Dims4D::Act::C]),
                std::min(perClusterMemoryOffsets[clusterId][Dims4D::Act::H],
                         perClusterComputeOffsets[clusterId][Dims4D::Act::H]),
                std::min(perClusterMemoryOffsets[clusterId][Dims4D::Act::W],
                         perClusterComputeOffsets[clusterId][Dims4D::Act::W]),
        };
    }

    return perClusterWorkloadOffsets;
}

void applyClusteringOffset(VPU::DPUWorkloadOp dpuWorkloadOp, ArrayRef<int64_t> clusteringOffset, Logger log) {
    auto wlOffsets = parseIntArrayAttr<int64_t>(dpuWorkloadOp.getOutOffsetsAttr());
    if (mlir::isa<VPU::NCEPermuteOp>(dpuWorkloadOp->getParentOp())) {
        // NCEPermute CHW will be casted to HWC, so need to process offsets on C and H
        wlOffsets[Dims4D::Act::C.ind()] -= clusteringOffset[Dims4D::Act::C.ind()];
        wlOffsets[Dims4D::Act::H.ind()] -= clusteringOffset[Dims4D::Act::H.ind()];
    } else {
        wlOffsets[Dims4D::Act::H.ind()] -= clusteringOffset[Dims4D::Act::H.ind()];
        wlOffsets[Dims4D::Act::W.ind()] -= clusteringOffset[Dims4D::Act::W.ind()];
    }

    mlir::OpBuilder builder(dpuWorkloadOp);
    auto newWorkload = builder.create<VPU::DPUWorkloadOp>(
            dpuWorkloadOp.getLoc(), getIntArrayAttr(dpuWorkloadOp.getContext(), wlOffsets),
            dpuWorkloadOp.getOutSizesAttr(), dpuWorkloadOp.getInOffsetsAttr(), dpuWorkloadOp.getInSizesAttr(),
            dpuWorkloadOp.getPadAttr(), dpuWorkloadOp.getMpeModeAttr(), dpuWorkloadOp.getClusterIdAttr());

    log.nest().trace("Applied overlapped offset for workload: before '{0}', after '{1}'", dpuWorkloadOp, newWorkload);

    dpuWorkloadOp.erase();
}

//
// ShiftOutputWorkloadsForHalo
//

class ShiftOutputWorkloadsForHaloPass final : public ShiftOutputWorkloadsForHaloBase<ShiftOutputWorkloadsForHaloPass> {
public:
    explicit ShiftOutputWorkloadsForHaloPass(Logger log): _log(log) {
        _log.setName(Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;

private:
    Logger _log;
};

void ShiftOutputWorkloadsForHaloPass::safeRunOnFunc() {
    auto func = getOperation();

    func.walk([&](VPU::NCEOpInterface nceOp) {
        auto nceClusterTiling = nceOp->getParentOfType<VPU::NCEClusterTilingOp>();
        if (nceClusterTiling == nullptr) {
            return;
        }

        auto outputTypes = nceClusterTiling.getResult(0).getType().cast<VPU::DistributedTypeInterface>();
        if (!needsHaloWorkloadsCorrection(nceOp, outputTypes)) {
            return;
        }

        _log.trace("Adapting workloads for operation '{0}' at '{1}'.", nceOp->getName(), nceOp->getLoc());

        auto workloads = nceOp.getWorkloads().getOps<VPU::DPUWorkloadOp>();
        auto outDataDistributedType = outputTypes.getDistributedTypes().begin()->cast<VPU::DistributedTensorType>();
        const auto clusteringOffsets = getClusteringOffsets(outDataDistributedType);
        for (auto workloadOp : llvm::make_early_inc_range(workloads)) {
            VPUX_THROW_UNLESS(workloadOp.getClusterId().has_value(),
                              "DPU Workload should have cluster_id set. It does not.");
            auto clusterId = workloadOp.getClusterId().value();
            applyClusteringOffset(workloadOp, clusteringOffsets[clusterId], _log);
        }
    });
}

}  // namespace

//
// createShiftOutputWorkloadsForHaloPass
//

std::unique_ptr<mlir::Pass> vpux::VPU::createShiftOutputWorkloadsForHaloPass(Logger log) {
    return std::make_unique<ShiftOutputWorkloadsForHaloPass>(log);
}
