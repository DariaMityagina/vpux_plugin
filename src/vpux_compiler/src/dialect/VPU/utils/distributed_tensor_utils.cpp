//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/utils/distributed_tensor_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/generate_tiling.hpp"
#include "vpux/compiler/dialect/VPU/utils/multi_cluster_strategy_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/sw_utils.hpp"
#include "vpux/compiler/dialect/VPUIP/sw_utils.hpp"

#include <llvm/ADT/TypeSwitch.h>

using namespace vpux;
using namespace VPU;

//
// Distributed tensor utilities
//

bool vpux::VPU::isSegmentedSWOp(mlir::Operation* op) {
    if (!mlir::isa<VPU::ClusteredOpInterface>(op)) {
        return false;
    }
    if (!mlir::isa<VPU::SWOpInterface>(op)) {
        return false;
    }
    auto clusterOp = mlir::cast<VPU::ClusteredOpInterface>(op);
    auto strategy = clusterOp.getMultiClusterStrategyAttr();
    if (!strategy.hasValue() || strategy.getValue() != VPU::MultiClusterStrategy::SplitOverKernel) {
        return false;
    }
    return true;
}

bool vpux::VPU::inputProducersCompatible(mlir::Operation* op) {
    // propagate tiled ops
    if (mlir::isa<VPU::ConcatOp>(op)) {
        return isSegmentedInputCompatible(op);
    }
    // propagate copy
    if (mlir::isa<VPU::CopyOp>(op)) {
        return isSegmentedInputCompatible(op);
    }
    if (auto clusterOp = mlir::dyn_cast<VPU::NCEClusterTilingOp>(op)) {
        // propagate copy
        auto innerCopy = clusterOp.getInnerTaskOpOfType<VPU::CopyOp>();
        if (innerCopy != nullptr) {
            return isSegmentedInputCompatible(op);
        }

        const auto outputs = clusterOp->getResults();
        VPUX_THROW_UNLESS(outputs.size() == 1, "Wrong outputs size: {0}", outputs.size());

        const auto output = *outputs.begin();

        auto getDistributedTensor = [](const mlir::Value value) -> VPU::DistributedTensorType {
            if (auto sparseTensor = value.getType().dyn_cast<VPU::SparseTensorType>()) {
                return sparseTensor.getData().dyn_cast<VPU::DistributedTensorType>();
            }
            return value.getType().dyn_cast<VPU::DistributedTensorType>();
        };

        auto distributedOutputType = getDistributedTensor(output);
        VPUX_THROW_WHEN(distributedOutputType == nullptr, "Wrong output type {0} for NCEClusterTilingOp {1}",
                        output.getType(), clusterOp);

        return VPUIP::isSegmentedOverC(distributedOutputType.getDistribution());
    }

    return isSegmentedSWOp(op);
}

bool vpux::VPU::isSegmentedInputCompatible(mlir::Operation* op) {
    // For SW kernel, SplitOverKernel means input is tiled on channel axis
    if (mlir::isa<VPU::SWOpInterface>(op)) {
        return true;
    }
    if (mlir::isa<VPU::NCEConvolutionOp, VPU::NCECompressConvolutionOp>(op)) {
        // full input required
        return false;
    }
    if (auto definingOp = op->getOperand(0).getDefiningOp()) {
        if (!inputProducersCompatible(definingOp)) {
            return false;
        }
    }
    // check siblings
    for (auto* user : op->getOperand(0).getUsers()) {
        if (user == op) {
            continue;
        }
        // If at lest one producer is not SEGMETNED SW as compute, broadcast the data
        if (!inputProducersCompatible(user)) {
            return false;
        }
    }
    return true;
}

bool vpux::VPU::isSegmentedOutputCompatible(mlir::Operation* op) {
    // For SW kernel, SplitOverKernel means input is tiled on channel axis
    if (mlir::isa<VPU::SWOpInterface>(op)) {
        return true;
    }
    // force SEG -> DPU -> SEG prevent SEG -> DPU -> SEG|DUP
    // re-enable with RT support E#66658
    if (isSegmentedInputCompatible(op)) {
        return true;
    }

    auto const isLegalSegSWOp = [&](mlir::Operation* user) {
        // TODO: This can be removed after E#76321 solved
        if (mlir::isa<VPU::SliceOp>(user)) {
            if (!user->hasOneUse()) {
                return false;
            }
            user = *user->getResult(0).getUsers().begin();
        }
        return isSegmentedSWOp(user);
    };

    // check consumres
    for (auto* user : op->getResult(0).getUsers()) {
        if (user == op) {
            continue;
        }
        // If at lest one consumer is not SEGMETNED SW as compute, broadcast the data
        if (!isLegalSegSWOp(user)) {
            return false;
        }
    }
    return true;
}

int64_t extractKernelTileAxis(ArrayRef<int64_t> numTiles) {
    VPUX_THROW_UNLESS(numTiles[Dims4D::Act::H.ind()] == 1 || numTiles[Dims4D::Act::W.ind()] == 1,
                      "Multidimension cluster tiling across H and W is not yet supported.");
    if (numTiles[Dims4D::Act::W.ind()] > 1) {
        return Dims4D::Kernel::X.ind();
    }
    return Dims4D::Kernel::Y.ind();
}

// This method computes the number of clusters to be used for an individual SOK
// layer such that additional alignment of the per cluster output channels is not required.
// Example: For 80 output channel / 4 clusters = [20, 20, 20, 20] output channels per cluster.
// 20 is not aligned to 16. Therefore, the compiler should only execute this layer on 3 clusters.
// This would result in [32, 32, 16] output channels per cluster.
int64_t vpux::VPU::getNumberOfClustersForSOKToAvoidAlignment(int64_t outputChannels, int64_t numClustersToUseForLayer,
                                                             bool uniformDistributedSegments) {
    for (int64_t clusters = numClustersToUseForLayer; clusters >= 1; clusters--) {
        if (uniformDistributedSegments) {
            // Align downwards to the next mutiple of KMB_DPU_CHANNELS_ALIGNMENT
            auto baselineChannels = alignValDown<int64_t>(outputChannels / clusters, KMB_DPU_CHANNELS_ALIGNMENT);
            int64_t remainder = outputChannels - baselineChannels * clusters;
            // Even if baseline itself is > 0 favor the cases where remainder is a multiple of alignment
            if (baselineChannels > 0 && !(remainder % KMB_DPU_CHANNELS_ALIGNMENT)) {
                return clusters;
            }
        } else {
            // For VPUX3XXX architectures, there's unwritten contract that the first N-1 cluster segments
            // all need to be equal, and the last segment can be equal or smaller.
            auto alignedOutputChannels =
                    alignValUp<int64_t>(divUp(outputChannels, clusters), KMB_DPU_CHANNELS_ALIGNMENT);
            int64_t remainder = outputChannels - (clusters - 1) * alignedOutputChannels;
            if (remainder > 0) {
                return clusters;
            }
        }
    }
    return 1;
}

int64_t vpux::VPU::getNumberOfClustersForSpatialDim(int64_t outputSpatialDim, int64_t numClustersForCompilation,
                                                    bool uniformDistributedSegments) {
    for (int64_t clusters = numClustersForCompilation; clusters >= 1; clusters--) {
        if (uniformDistributedSegments) {
            auto baselineHeight = outputSpatialDim / clusters;
            if (baselineHeight > 0) {
                return clusters;
            }
        } else {
            // For VPUX3XXX architectures, there's unwritten contract that the first N-1 cluster segments
            // all need to be equal, and the last segment can be equal or smaller.
            auto alignedOutputSpatialDim = divUp(outputSpatialDim, clusters);
            int64_t remainder = outputSpatialDim - (clusters - 1) * alignedOutputSpatialDim;
            if (remainder > 0) {
                return clusters;
            }
        }
    }
    return 1;
}

struct OverlapDistributionParams {
    OverlapDistributionParams(mlir::ArrayAttr kernel, VPU::PaddingAttr pads, mlir::ArrayAttr stride,
                              mlir::UnitAttr equalComputeAndMemoryView = nullptr)
            : kernel(kernel), pads(pads), stride(stride), equalComputeAndMemoryView(equalComputeAndMemoryView){};
    mlir::ArrayAttr kernel;
    VPU::PaddingAttr pads;
    mlir::ArrayAttr stride;
    mlir::UnitAttr equalComputeAndMemoryView;
};

OverlapDistributionParams getOverlappedDistributionParameters(mlir::MLIRContext* ctx,
                                                              ArrayRef<VPU::ClusteredOpInterface> opSubgraph,
                                                              int64_t kernelDistributionAxis,
                                                              mlir::UnitAttr equalComputeAndMemoryView = nullptr) {
    auto kernel = getIntArrayAttr(ctx, SmallVector<int64_t>{1, 1});
    auto pads = VPU::getPaddingAttr(ctx, 0, 0, 0, 0);
    auto strides = getIntArrayAttr(ctx, SmallVector<int64_t>{1, 1});

    SmallVector<VPU::NCEOpInterface> nceOpCandidates;
    for (auto clusteredOp : opSubgraph) {
        if (auto nceOp = mlir::dyn_cast<VPU::NCEOpInterface>(clusteredOp.getOperation())) {
            nceOpCandidates.push_back(nceOp);
        }
    }

    if (nceOpCandidates.empty()) {
        return OverlapDistributionParams(kernel, pads, strides);
    }

    // For now just take the highest kernel
    // As we have better representation in distributedBuffer, switch to computing the
    // actual shapes per clusters

    auto largestKernel = 0;
    auto largestIndex = 0;
    for (auto it : nceOpCandidates | indexed) {
        auto kernelSize = it.value().getKernelSize()[kernelDistributionAxis];
        if (kernelSize > largestKernel) {
            largestKernel = kernelSize;
            largestIndex = it.index();
        }
    }

    kernel = getIntArrayAttr(ctx, nceOpCandidates[largestIndex].getKernelSize());
    pads = nceOpCandidates[largestIndex].getPad();
    strides = getIntArrayAttr(ctx, nceOpCandidates[largestIndex].getStrides());

    return OverlapDistributionParams(kernel, pads, strides, equalComputeAndMemoryView);
}

namespace {
SmallVector<Shape> getPerClusterEndOffset(ArrayRef<Shape> startOffset, ArrayRef<Shape> size) {
    const auto numDims = startOffset[0].size();
    const auto numClusters = startOffset.size();
    auto endOffset = SmallVector<Shape>(numClusters, Shape(numDims, 0));

    for (size_t cluster = 0; cluster < numClusters; cluster++) {
        for (size_t dim = 0; dim < numDims; dim++) {
            endOffset[cluster][Dim(dim)] = startOffset[cluster][Dim(dim)] + size[cluster][Dim(dim)] - 1;
        }
    }

    return endOffset;
}
}  // namespace

//
// In case of input being presented with explicit overlap lines with DPU,
// we need to take into account all the siblings requirements
// when it comes to kernel, pad and stride.
//
// For the best handling, to provide the output which can service all siblings
// without spilling be required, we will need the support of precomputed shapes/offsets
// per cluster.
// This is because of the cases when different ops may have the maximum requirements
// on different clusters. In which case, there's no singular way with current distributed
// infrastructure to represent a mixed tiling mode. Only explicit shapes will help here.
//
OverlapDistributionParams getActivationOverlappedParams(VPU::ClusteredOpInterface clusteredOp,
                                                        ArrayRef<int64_t> activationTensorNumTiles) {
    const auto ctx = clusteredOp.getContext();
    SmallVector<VPU::ClusteredOpInterface> siblingSubgraph;
    auto numberOperands = 1;
    // TODO: use common interference graph util
    if (mlir::dyn_cast<VPU::NCEEltwiseOp>(clusteredOp.getOperation())) {
        numberOperands = 2;
    }
    for (auto opIdx = 0; opIdx < numberOperands; ++opIdx) {
        for (auto sibling : clusteredOp->getOperand(opIdx).getUsers()) {
            if (auto clusteredSibling = mlir::dyn_cast<VPU::ClusteredOpInterface>(sibling)) {
                siblingSubgraph.push_back(clusteredSibling);
            }
        }
    }
    const auto kernelTileAxis = extractKernelTileAxis(activationTensorNumTiles);
    const auto candidateOverlappedParams = getOverlappedDistributionParameters(ctx, siblingSubgraph, kernelTileAxis);

    // Lacking a way specifying explicit per cluster shapes and offsets in the distributed
    // datatype, we are forced to pick a single sibling configuration.
    // Need to check if the picked configuration satisfies the current consumer
    // data requirements.
    //
    // For example two convolutions each with input height of 100 across 3 clusters
    // Conv 1 with [kernel_Y 1, stride_Y 1, pad_top_bottom 0, 0]
    // Conv 2 with [kernel_Y 5, stride_Y 4, pad_top_bottom 2, 2]
    //
    // Conv 1 needs [34, 33, 33] input size for each cluster
    // Conv 2 needs [35, 33, 31] input size for each cluster
    //
    // We can't pick a single sibling configuration to satisfy both operations.
    // Thus if the initial choice of config is not supporting, default to own config.
    //
    // This will change once we start using a more explicit representation for shapes per cluster
    // and no longer rely on the current distributed attribute config.

    const auto numberClusters = (kernelTileAxis == Dims4D::Kernel::Y.ind())
                                        ? activationTensorNumTiles[Dims4D::Act::H.ind()]
                                        : activationTensorNumTiles[Dims4D::Act::W.ind()];
    const auto distributionModeAttr = VPU::DistributionModeAttr::get(ctx, VPU::DistributionMode::OVERLAPPED);

    const auto candidateDistributedAttr = DistributedTensorAttr::get(
            distributionModeAttr, getIntArrayAttr(ctx, activationTensorNumTiles), candidateOverlappedParams.kernel,
            candidateOverlappedParams.pads, candidateOverlappedParams.stride, getIntAttr(ctx, numberClusters), nullptr,
            mlir::UnitAttr::get(ctx), nullptr, nullptr, nullptr, ctx);

    const auto localOverlappedParams = getOverlappedDistributionParameters(
            ctx, SmallVector<VPU::ClusteredOpInterface>({clusteredOp}), kernelTileAxis);

    const auto localDistributedAttr = DistributedTensorAttr::get(
            distributionModeAttr, getIntArrayAttr(ctx, activationTensorNumTiles), localOverlappedParams.kernel,
            localOverlappedParams.pads, localOverlappedParams.stride, getIntAttr(ctx, numberClusters), nullptr,
            mlir::UnitAttr::get(ctx), nullptr, nullptr, nullptr, ctx);

    const auto inputShape = getShape(clusteredOp->getOperand(0));

    const auto candidateOffsets = getPerClusterMemoryShapeOffsets(inputShape, candidateDistributedAttr);
    const auto candidateShapes = getPerClusterMemoryShapes(inputShape, candidateDistributedAttr);

    const auto localOffsets = getPerClusterMemoryShapeOffsets(inputShape, localDistributedAttr);
    const auto localShapes = getPerClusterMemoryShapes(inputShape, localDistributedAttr);

    for (auto offsetPerClusterZip : zip(candidateOffsets, localOffsets)) {
        for (auto dimZip : zip(std::get<0>(offsetPerClusterZip), std::get<1>(offsetPerClusterZip))) {
            if (std::get<0>(dimZip) > std::get<1>(dimZip)) {
                // candidate offset does not satisfy local op
                return localOverlappedParams;
            }
        }
    }

    const auto candidateEndOffset = getPerClusterEndOffset(candidateOffsets, candidateShapes);
    const auto localEndOffset = getPerClusterEndOffset(localOffsets, localShapes);

    for (auto endOffsetsPerClusterZip : zip(candidateEndOffset, localEndOffset)) {
        for (auto dimZip : zip(std::get<0>(endOffsetsPerClusterZip), std::get<1>(endOffsetsPerClusterZip))) {
            if (std::get<0>(dimZip) < std::get<1>(dimZip)) {
                // candidate shape does not satisfy local op
                return localOverlappedParams;
            }
        }
    }

    return candidateOverlappedParams;
}

//
// In case of output producing overlap lines with DPU
// we need to take into account all the consumer requirements
// when it comes to kernel, pad and stride.
//
// For the best handling, to provide the output which can service all consumers
// without spilling be required, we will need the support of precomputed shapes/offsets
// per cluster.
// This is because of the cases when different ops may have the maximum requirements
// on different clusters. In which case, there's no singular way with current distributed
// infrastructure to represent a mixed tiling mode. Only explicit shapes will help here.
//
OverlapDistributionParams getOutputOverlappedParams(VPU::ClusteredOpInterface clusteredOp,
                                                    ArrayRef<int64_t> outputTensorNumTiles) {
    const auto ctx = clusteredOp.getContext();
    SmallVector<VPU::ClusteredOpInterface> consumerSubgraph;
    const auto equalComputeAndMemoryView = (mlir::isa<NCEPermuteQuantizeOp>(clusteredOp.getOperation()))
                                                   ? mlir::UnitAttr::get(clusteredOp.getContext())
                                                   : nullptr;

    for (auto result : clusteredOp->getResults()) {
        for (auto consumer : result.getUsers()) {
            if (auto clusteredConsumer = mlir::dyn_cast<VPU::ClusteredOpInterface>(consumer)) {
                consumerSubgraph.push_back(clusteredConsumer);
            }
        }
    }
    const auto kernelTileAxis = extractKernelTileAxis(outputTensorNumTiles);
    const auto candidateOverlappedParams = getOverlappedDistributionParameters(
            clusteredOp.getContext(), consumerSubgraph, kernelTileAxis, equalComputeAndMemoryView);

    // Lacking a way specifying explicit per cluster shapes and offsets in the distributed
    // datatype, we are forced to pick a configuration where compute view is within the boundaries
    // of the memory view.
    // We represent input workload start & end through compute offset and size, while the total
    // amount of data in cluster is represented through memory shape. In cases where
    // compute start < memory start or compute end > memory_end, the size of data in cluster should be
    // max(compute end, memory_end) - min(compute start, memory start) + 1, but we currently have no way of
    // representing that. Therefore, we ensure that such a case will not happen by setting overlapped params k1x1,
    // s1x1, pad0x0x0x0 if the consumer distribution does not satisfy the requirements.

    const auto numberClusters = (kernelTileAxis == Dims4D::Kernel::Y.ind())
                                        ? outputTensorNumTiles[Dims4D::Act::H.ind()]
                                        : outputTensorNumTiles[Dims4D::Act::W.ind()];
    const auto distributionModeAttr = VPU::DistributionModeAttr::get(ctx, VPU::DistributionMode::OVERLAPPED);

    const auto candidateDistributedAttr = DistributedTensorAttr::get(
            distributionModeAttr, getIntArrayAttr(ctx, outputTensorNumTiles), candidateOverlappedParams.kernel,
            candidateOverlappedParams.pads, candidateOverlappedParams.stride, getIntAttr(ctx, numberClusters), nullptr,
            mlir::UnitAttr::get(ctx), nullptr, nullptr, nullptr, ctx);

    const auto outputShape = getShape(clusteredOp->getResult(0));

    const auto candidateMemoryOffsets = getPerClusterMemoryShapeOffsets(outputShape, candidateDistributedAttr);
    const auto candidateMemoryShapes = getPerClusterMemoryShapes(outputShape, candidateDistributedAttr);

    const auto candidateComputeOffsets = getPerClusterComputeShapeOffsets(outputShape, candidateDistributedAttr);
    const auto candidateComputeShapes = getPerClusterComputeShapes(outputShape, candidateDistributedAttr);

    const auto kernel = getIntArrayAttr(ctx, SmallVector<int64_t>{1, 1});
    const auto pads = VPU::getPaddingAttr(ctx, 0, 0, 0, 0);
    const auto strides = getIntArrayAttr(ctx, SmallVector<int64_t>{1, 1});
    const auto fallbackOverlappedParams = OverlapDistributionParams(kernel, pads, strides, equalComputeAndMemoryView);

    // Memory start offset must be before or equal to compute start offset
    for (auto startOffsetsPerClusterZip : zip(candidateMemoryOffsets, candidateComputeOffsets)) {
        for (auto dimZip : zip(std::get<0>(startOffsetsPerClusterZip), std::get<1>(startOffsetsPerClusterZip))) {
            if (std::get<0>(dimZip) > std::get<1>(dimZip)) {
                // candidate shape does not satisfy producer op
                return fallbackOverlappedParams;
            }
        }
    }

    const auto candidateMemoryEndOffset = getPerClusterEndOffset(candidateMemoryOffsets, candidateMemoryShapes);
    const auto candidateComputeEndOffset = getPerClusterEndOffset(candidateComputeOffsets, candidateComputeShapes);

    // Memory end offset must be after or equal to compute end offset
    for (auto endOffsetsPerClusterZip : zip(candidateMemoryEndOffset, candidateComputeEndOffset)) {
        for (auto dimZip : zip(std::get<0>(endOffsetsPerClusterZip), std::get<1>(endOffsetsPerClusterZip))) {
            if (std::get<0>(dimZip) < std::get<1>(dimZip)) {
                // candidate shape does not satisfy local op
                return fallbackOverlappedParams;
            }
        }
    }

    return candidateOverlappedParams;
}

SmallVector<int64_t> vpux::VPU::getActivationTensorNumTiles(VPU::ClusteredOpInterface clusteredOp,
                                                            int64_t numClustersAvailableForCompilation,
                                                            VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight || strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return {1, 1, numClustersAvailableForCompilation, 1};
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        if (isSegmentedInputCompatible(clusteredOp.getOperation())) {
            auto inputTensorType = clusteredOp->getOperand(0).getType().cast<vpux::NDTypeInterface>();
            auto IC = inputTensorType.getShape()[Dims4D::Act::C];
            int64_t numClustersToUseForLayer = std::min(numClustersAvailableForCompilation, IC);
            return {1, numClustersToUseForLayer, 1, 1};
        }
        return {1, 1, 1, 1};
    } else if (strategy == VPU::MultiClusterStrategy::Clustering) {
        return {1, 1, 1, 1};
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverWidth) {
        return {1, 1, 1, numClustersAvailableForCompilation};
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the number of tiles for the "
                   "activation tensor",
                   strategy);
    }
}

bool vpux::VPU::isDWOpAndNeedsAlign(ArchKind arch, VPUIP::NCETaskType nceTaskType) {
    bool isDWOp = nceTaskType == VPUIP::NCETaskType::DWCONV || nceTaskType == VPUIP::NCETaskType::MAXPOOL ||
                  nceTaskType == VPUIP::NCETaskType::AVEPOOL;
    return (arch == VPU::ArchKind::VPUX37XX) && isDWOp;
}

bool vpux::VPU::isEltwiseOpAndNeedsAlign(VPU::ClusteredOpInterface clusteredOp) {
    auto nceEltwiseOp = mlir::dyn_cast<VPU::NCEEltwiseOp>(clusteredOp.getOperation());
    if (nceEltwiseOp == nullptr) {
        return false;
    }

    // Find if there exists a non-eltwise nceOp with SOH in eltwise subgraph
    llvm::SmallPtrSet<mlir::Operation*, 16> processedInputOps;
    std::deque<mlir::Value> inputs = {nceEltwiseOp->getOperand(0), nceEltwiseOp->getOperand(1)};
    while (!inputs.empty()) {
        const auto currentInput = inputs.front();
        // skip processed input
        if (auto defOp = currentInput.getDefiningOp()) {
            if (processedInputOps.count(defOp) > 0) {
                inputs.pop_front();
                continue;
            }
        }
        for (auto userOp : currentInput.getUsers()) {
            // Skip non-clustered ops
            if (!mlir::isa<VPU::ClusteredOpInterface>(userOp)) {
                continue;
            }
            // There are 2 scenarios that we need to set alignment attr to eltwises
            // Scenario 1:
            //   Has one sibling op with SOH whose input needs alignment
            //                 AnyOp      AnyOp
            //                 /   \       /
            //            ConvOp   *EltwiseOp
            // Scenario 2:
            //   Has one descendant op with SOH whose input needs alignment
            //               *EltwiseOp    AnyOp
            //                        \    /
            //                       EltwiseOp
            //                           |
            //                         ConvOp
            if (auto userEltwiseOp = mlir::dyn_cast<VPU::NCEEltwiseOp>(userOp)) {
                // Should also find in child eltwiseOp's siblings and children
                auto userEltwiseInput1 = userEltwiseOp.input1();
                if (userEltwiseInput1 != currentInput &&
                    processedInputOps.count(userEltwiseInput1.getDefiningOp()) == 0) {
                    inputs.push_back(userEltwiseInput1);
                }
                auto userEltwiseInput2 = userEltwiseOp.input2();
                if (userEltwiseInput2 != currentInput &&
                    processedInputOps.count(userEltwiseInput2.getDefiningOp()) == 0) {
                    inputs.push_back(userEltwiseInput2);
                }
                auto userEltwiseOutput = userEltwiseOp.output();
                if (processedInputOps.count(userEltwiseOutput.getDefiningOp()) == 0) {
                    inputs.push_back(userEltwiseOutput);
                }
            } else {
                // Check if it's a non-eltwise with SOH
                auto userNceOp = mlir::cast<VPU::ClusteredOpInterface>(userOp);
                auto strategy = userNceOp.getMultiClusterStrategyAttr();
                if (strategy.hasValue() && (strategy.getValue() == VPU::MultiClusterStrategy::SplitOverHeight ||
                                            strategy.getValue() == VPU::MultiClusterStrategy::HKSwitch)) {
                    return true;
                }
            }
        }
        processedInputOps.insert(currentInput.getDefiningOp());
        inputs.pop_front();
    }
    return false;
}

bool vpux::VPU::isSWOpChannelAlignmentCompatible(VPU::ClusteredOpInterface swOp) {
    if (!mlir::isa<VPU::SWOpInterface>(swOp.getOperation())) {
        return false;
    }

    if (swOp->getOperands().size() != 1 && swOp->getResults().size() != 1) {
        return false;
    }

    const auto strategy = swOp.getMultiClusterStrategyAttr();
    if (!strategy.hasValue()) {
        return false;
    }

    // Only when SW Op with Clustering and SOK strategy
    auto actInputShape = swOp->getOperand(0).getType().cast<vpux::NDTypeInterface>().getShape();
    auto actOutputShape = swOp->getResult(0).getType().cast<vpux::NDTypeInterface>().getShape();
    auto actInputC = actInputShape[Dims4D::Act::C];
    auto actOutputC = actOutputShape[Dims4D::Act::C];
    auto alignment = DISTRIBUTED_C_ALIGNMENT[Dims4D::Act::C.ind()];

    if (strategy.getValue() == VPU::MultiClusterStrategy::Clustering) {
        return (actInputC % alignment == 0) && (actOutputC % alignment == 0);
    } else if (strategy.getValue() == VPU::MultiClusterStrategy::SplitOverKernel) {
        auto module = swOp->getParentOfType<mlir::ModuleOp>();
        auto nceClusterCount = IE::getAvailableExecutor(module, VPU::ExecutorKind::NCE).count();
        return (actInputC % (alignment * nceClusterCount) == 0) && (actOutputC % (alignment * nceClusterCount) == 0);
    }

    return false;
}

bool isHSegmentedType(vpux::VPU::DistributedTensorType distributedType) {
    auto mode = distributedType.getDistribution().mode().getValue();
    if (mode == VPU::DistributionMode::OVERLAPPED) {
        // SplitOverHOverlapped
        return true;
    }
    if (mode != VPU::DistributionMode::SEGMENTED) {
        // Clustering or SplitOverKernel
        return false;
    }
    auto numTilesAttr = distributedType.getDistribution().num_tiles();
    if (numTilesAttr == nullptr) {
        return false;
    }
    auto numTiles = parseIntArrayAttr<int64_t>(numTilesAttr);
    return numTiles[Dims4D::Act::H.ind()] > 1;
}

bool isSWParentAlignmentAtChannel(VPU::ClusteredOpInterface swOp) {
    auto parentOp = swOp->getOperand(0).getDefiningOp();

    auto isClusteredCopy = [](mlir::Operation* op) -> bool {
        if (auto clusteredOp = mlir::dyn_cast<VPU::NCEClusterTilingOp>(op)) {
            auto innerCopy = clusteredOp.getInnerTaskOpOfType<VPU::CopyOp>();
            if (innerCopy == nullptr) {
                return false;
            }
            return true;
        }
        return false;
    };
    while (parentOp != nullptr && (mlir::isa<VPU::ViewLikeOpInterface>(parentOp) || isClusteredCopy(parentOp))) {
        parentOp = parentOp->getOperand(0).getDefiningOp();
    }
    if (parentOp == nullptr || !mlir::isa<VPU::NCEClusterTilingOp>(parentOp)) {
        return false;
    }

    auto parentDistributedType = parentOp->getResult(0).getType().cast<vpux::VPU::DistributedTensorType>();
    if (isHSegmentedType(parentDistributedType)) {
        // SOH parent cannot be compatible with Clustering/SOK SW op
        return false;
    }
    auto parentAlignment = parentDistributedType.getDistribution().alignment();
    return parentAlignment != nullptr;
}

// Adjust inputType alignment for SW op to avoid spilling.
// For example:
//  - Conv (SOK) -> SW (SOK), the input of SW can set alignment of channel to 16
bool vpux::VPU::isSWOpWithAlignedInputChannelReq(VPU::ClusteredOpInterface swOp) {
    if (isSWOpChannelAlignmentCompatible(swOp)) {
        return isSWParentAlignmentAtChannel(swOp);
    }
    return false;
}

bool isSWUsersAlignmentAtChannel(VPU::ClusteredOpInterface swOp) {
    for (auto childOp : swOp->getResult(0).getUsers()) {
        while (childOp != nullptr && mlir::isa<VPU::ViewLikeOpInterface>(childOp)) {
            childOp = *childOp->getResult(0).getUsers().begin();
            if (hasMultiBranches(childOp)) {
                return false;
            }
        }
        if (childOp == nullptr || !mlir::isa<VPU::NCEOpInterface>(childOp) ||
            !mlir::isa<VPU::ClusteredOpInterface>(childOp)) {
            return false;
        }

        auto clusteredNCEOp = mlir::cast<VPU::ClusteredOpInterface>(childOp);
        auto strategy = clusteredNCEOp.getMultiClusterStrategyAttr();
        // Only add alignment when the child strategy is not split on width or height, to keep subgraph consistent
        if (strategy.hasValue()) {
            auto mcStrategy = strategy.getValue();
            bool isSplitOnWidthOrHeight = mcStrategy == VPU::MultiClusterStrategy::SplitOverWidth ||
                                          mcStrategy == VPU::MultiClusterStrategy::SplitOverHeight ||
                                          mcStrategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped;
            if (!isSplitOnWidthOrHeight) {
                return true;
            }
        }
    }
    return false;
}

// Adjust inputType alignment for SW op to avoid spilling.
// For example:
//  - SW (Clustering) -> Conv (SOK), the output of SW can set alignment of channel to 16
bool vpux::VPU::isSWOpWithAlignedOutputChannelReq(VPU::ClusteredOpInterface swOp) {
    if (isSWOpChannelAlignmentCompatible(swOp)) {
        return isSWUsersAlignmentAtChannel(swOp);
    }
    return false;
}

Optional<SmallVector<int64_t>> vpux::VPU::getActivationTensorAlignment(VPU::ClusteredOpInterface clusteredOp,
                                                                       mlir::IntegerAttr numClusters,
                                                                       VPU::MultiClusterStrategy strategy,
                                                                       vpux::NDTypeInterface inputType) {
    if (mlir::isa<VPU::SWOpInterface>(clusteredOp.getOperation())) {
        if (isSWOpWithAlignedInputChannelReq(clusteredOp)) {
            return DISTRIBUTED_C_ALIGNMENT;
        }
        return None;
    }

    if (strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::Clustering) {
        return DISTRIBUTED_C_ALIGNMENT;
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverHeight ||
               strategy == VPU::MultiClusterStrategy::HKSwitch) {
        auto operation = clusteredOp.getOperation();
        auto arch = getArch(operation);

        if (mlir::isa<VPU::NCEConvolutionOp, VPU::NCEInterpolateOp>(operation) ||
            ((arch == VPU::ArchKind::VPUX37XX) &&
             mlir::isa<VPU::NCEDepthConvolutionOp, VPU::NCEMaxPoolOp, VPU::NCEAveragePoolOp,
                       VPU::NCECompressConvolutionOp>(operation)) ||
            isEltwiseOpAndNeedsAlign(clusteredOp)) {
            if (inputType == nullptr) {
                inputType = clusteredOp->getOperand(0).getType().cast<vpux::NDTypeInterface>();
            }
            const auto inputShape = inputType.getShape();
            const auto heightAlignment = getSOHMinimalHeightAlignment(inputShape, numClusters.getInt(), arch);
            if (heightAlignment <= 1) {
                return None;
            }

            return SmallVector<int64_t>{1, 1, heightAlignment, 1};
        }
    }
    return None;
}

SmallVector<int64_t> vpux::VPU::getOutputTensorNumTiles(VPU::ClusteredOpInterface clusteredOp,
                                                        int64_t numClustersAvailableForCompilation,
                                                        VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight || strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return {1, 1, numClustersAvailableForCompilation, 1};
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        auto outputTensorType = clusteredOp->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
        auto OC = outputTensorType.getShape()[Dims4D::Act::C];
        int64_t numClustersToUseForLayer = numClustersAvailableForCompilation;
        if (mlir::isa<VPU::SWOpInterface>(clusteredOp.getOperation())) {
            numClustersToUseForLayer = std::min(numClustersAvailableForCompilation, OC);
        } else {
            auto uniformDistributedSegments = !VPU::isArchVPUX3XXX(VPU::getArch(clusteredOp));
            numClustersToUseForLayer = getNumberOfClustersForSOKToAvoidAlignment(OC, numClustersAvailableForCompilation,
                                                                                 uniformDistributedSegments);
        }

        return {1, numClustersToUseForLayer, 1, 1};
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverWidth) {
        return {1, 1, 1, numClustersAvailableForCompilation};
    } else if (strategy == VPU::MultiClusterStrategy::Clustering) {
        return {1, 1, 1, 1};
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the number of tiles for the "
                   "output tensor",
                   strategy);
    }
}

Optional<SmallVector<int64_t>> vpux::VPU::getOutputTensorAlignment(VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return DISTRIBUTED_C_ALIGNMENT;
    }

    return None;
}

Optional<vpux::NDTypeInterface> vpux::VPU::adjustOutputAlignmentForSOH(VPU::ClusteredOpInterface clusteredOp,
                                                                       vpux::NDTypeInterface originalDistType) {
    if (clusteredOp->getResult(0).use_empty()) {
        return None;
    }

    if (mlir::isa<VPU::SWOpInterface>(clusteredOp.getOperation())) {
        return None;
    }

    auto originalDistTypeIf = originalDistType.dyn_cast<VPU::DistributedTypeInterface>();
    VPUX_THROW_UNLESS(originalDistTypeIf != nullptr, "Expected type to be distributed, got {0}", originalDistType);
    VPUX_THROW_UNLESS(originalDistTypeIf.containsDistributedTypes(), "Type does not contain distributed components");
    const auto distributedTypes = originalDistTypeIf.getDistributedTypes();

    const auto distributedDataType = distributedTypes.front().cast<VPU::DistributedTensorType>();

    auto updateAlignment = [&](VPU::ClusteredOpInterface consumerOp, bool skipCmxCheck) -> Optional<NDTypeInterface> {
        auto getAlignedDistributedTensorType =
                [&clusteredOp](ArrayRef<int64_t> alignment,
                               VPU::DistributedTensorType distType) -> VPU::DistributedTensorType {
            const auto newAlignmentAttr = getIntArrayAttr(clusteredOp->getContext(), alignment);
            auto distributedAttr = distType.getDistribution();
            auto newDistributedAttr = VPU::DistributedTensorAttr::get(
                    distributedAttr.mode(), distributedAttr.num_tiles(), distributedAttr.kernel(),
                    distributedAttr.pads(), distributedAttr.strides(), distributedAttr.num_clusters(), newAlignmentAttr,
                    distributedAttr.uniform_distributed_segments(), distributedAttr.compute_shapes(),
                    distributedAttr.compute_offsets(), distributedAttr.equal_memory_and_compute_view(),
                    clusteredOp->getContext());
            return VPU::DistributedTensorType::get(clusteredOp->getContext(), distType.getShape().raw(),
                                                   distType.getElementType(), distType.getOrder(),
                                                   distType.getMemSpace(), newDistributedAttr);
        };

        const auto newAlignment =
                getActivationTensorAlignment(consumerOp, distributedDataType.getDistribution().num_clusters(),
                                             VPU::MultiClusterStrategy::SplitOverHeight);
        if (!newAlignment.hasValue()) {
            return None;
        }

        SmallVector<VPU::DistributedTensorType> newDistributedTypes;
        for (auto type : distributedTypes) {
            auto distType = type.cast<VPU::DistributedTensorType>();
            newDistributedTypes.push_back(getAlignedDistributedTensorType(newAlignment.getValue(), distType));
        }

        auto layerStrategyChecker = LayerStrategyCheckerFactory::instance().get(clusteredOp->getName());

        if (originalDistType.isa<VPU::SparseTensorType>()) {
            VPUX_THROW_UNLESS(newDistributedTypes.size() >= 1, "Expected at least 1 distributed type, got {0}",
                              newDistributedTypes.size());
            const auto newDataType = newDistributedTypes[0];
            const auto newSMType = (newDistributedTypes.size() > 1) ? newDistributedTypes[1] : nullptr;
            const auto newSEType = (newDistributedTypes.size() > 2) ? newDistributedTypes[2] : nullptr;
            const auto newSparseOutputType = VPU::SparseTensorType::get(newDataType, newSMType, newSEType);
            if (skipCmxCheck || layerStrategyChecker->doesLayerChangeOutputAlignmentFitIntoCMX(
                                        clusteredOp, VPU::MultiClusterStrategy::SplitOverHeight, newSparseOutputType)) {
                return newSparseOutputType.cast<vpux::NDTypeInterface>();
            }
        }

        if (newDistributedTypes.size() == 1) {
            if (skipCmxCheck ||
                layerStrategyChecker->doesLayerChangeOutputAlignmentFitIntoCMX(
                        clusteredOp, VPU::MultiClusterStrategy::SplitOverHeight, newDistributedTypes[0])) {
                return newDistributedTypes[0].cast<vpux::NDTypeInterface>();
            }
        }

        return None;
    };

    // If the nceOp is eltwise, the output alignment should be the same as input.
    if (mlir::isa<VPU::NCEEltwiseOp>(clusteredOp)) {
        return updateAlignment(clusteredOp, /*skipCmxCheck=*/true);
    }

    // optimization SOH -> SOH alignment to remove spilling
    // For multi-users just random choose one NCEOp for optimize
    // TODO: choose the best NCEOp or find least common multiple of all user's alignment
    for (auto consumerOp : clusteredOp->getResult(0).getUsers()) {
        // If user is a concatOp whose output shape is the same as the
        // output shape of nceOp in both H & W, adjust output alignment
        // with input of concatOp's users to enable cmx concat.
        if (auto concatOp = mlir::dyn_cast<VPU::ConcatOp>(consumerOp)) {
            auto concatOutputShape = getShape(concatOp->getResult(0));
            auto isHWShapeSame = llvm::all_of(concatOp.inputs(), [&](mlir::Value input) {
                auto concatInputShape = input.getType().cast<vpux::NDTypeInterface>().getShape();
                return concatInputShape[Dims4D::Act::H] == concatOutputShape[Dims4D::Act::H] &&
                       concatInputShape[Dims4D::Act::W] == concatOutputShape[Dims4D::Act::W];
            });
            if (isHWShapeSame) {
                consumerOp = *consumerOp->getResult(0).getUsers().begin();
            }
        }

        if (!mlir::isa<VPU::NCEOpInterface>(consumerOp)) {
            continue;
        }

        auto consumerClusterOp = mlir::dyn_cast<VPU::ClusteredOpInterface>(consumerOp);
        auto consumerMultiClusterStrategyAttr = consumerClusterOp.getMultiClusterStrategyAttr();
        if (!consumerMultiClusterStrategyAttr.hasValue()) {
            continue;
        }

        const auto strategy = consumerMultiClusterStrategyAttr.getValue();
        if (strategy != VPU::MultiClusterStrategy::SplitOverHeight && strategy != VPU::MultiClusterStrategy::HKSwitch) {
            continue;
        }

        if (auto convOp = mlir::dyn_cast<NCEConvolutionOp>(consumerOp)) {
            const auto arch = VPU::getArch(consumerOp);
            if (VPU::NCEInvariant::isChannelMajorCompatible(arch,
                                                            convOp.input().getType().cast<vpux::NDTypeInterface>())) {
                return None;
            }
        }

        return updateAlignment(consumerClusterOp, /*skipCmxCheck=*/false);
    }
    return None;
}

SmallVector<int64_t> vpux::VPU::getWeightsTensorNumTiles(VPU::ClusteredOpInterface clusteredOp,
                                                         vpux::NDTypeInterface tensorType,
                                                         int64_t numClustersAvailableForCompilation,
                                                         VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return {1, 1, 1, 1};
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        auto OC = tensorType.getShape()[Dims4D::Filter::OC];
        auto uniformDistributedSegments = !VPU::isArchVPUX3XXX(VPU::getArch(clusteredOp));
        int64_t numClustersToUseForLayer = getNumberOfClustersForSOKToAvoidAlignment(
                OC, numClustersAvailableForCompilation, uniformDistributedSegments);
        return {numClustersToUseForLayer, 1, 1, 1};
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the number of tiles for the "
                   "weights tensor",
                   strategy);
    }
}

Optional<SmallVector<int64_t>> vpux::VPU::getWeightsTensorAlignment(VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::Clustering) {
        return SmallVector<int64_t>{16, 1, 1, 1};
    }
    return None;
}

SmallVector<int64_t> vpux::VPU::getWeightsTableTensorNumTiles(VPU::ClusteredOpInterface clusteredOp,
                                                              vpux::NDTypeInterface tensorType,
                                                              int64_t numClustersAvailableForCompilation,
                                                              VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return {1, 1, 1, 1};
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        auto OC = tensorType.getShape()[Dims4D::Act::C];
        auto uniformDistributedSegments = !VPU::isArchVPUX3XXX(VPU::getArch(clusteredOp));
        int64_t numClustersToUseForLayer = getNumberOfClustersForSOKToAvoidAlignment(
                OC, numClustersAvailableForCompilation, uniformDistributedSegments);
        return {numClustersToUseForLayer, 1, 1, 1};
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the number of tiles for the "
                   "weights tensor",
                   strategy);
    }
}

SmallVector<int64_t> vpux::VPU::getActivationWindowTensorNumTiles(VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight ||
        strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return {1, 1, 1, 1};
    }
    VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the number of tiles for the "
               "activation window tensor",
               strategy);
}

SmallVector<int64_t> vpux::VPU::getInstructionListTableTensorNumTiles(VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight ||
        strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return {1, 1, 1, 1};
    }
    VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the number of tiles for the "
               "instruction list table tensor",
               strategy);
}

DistributionMode vpux::VPU::getActivationTensorDistributionMode(VPU::ClusteredOpInterface clusteredOp,
                                                                VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped) {
        return DistributionMode::OVERLAPPED;
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverWidth) {
        return DistributionMode::OVERLAPPED;
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverHeight ||
               strategy == VPU::MultiClusterStrategy::HKSwitch) {
        if (VPU::isArchVPUX3XXX(VPU::getArch(clusteredOp))) {
            return DistributionMode::SEGMENTED;
        }
        return DistributionMode::OVERLAPPED;
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        if (isSegmentedInputCompatible(clusteredOp.getOperation())) {
            return DistributionMode::SEGMENTED;
        }
        return DistributionMode::DUPLICATED;
    } else if (strategy == VPU::MultiClusterStrategy::Clustering) {
        return DistributionMode::DUPLICATED;
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the distribution mode for the "
                   "activation tensor",
                   strategy);
    }
}

DistributionMode vpux::VPU::getWeightsTensorDistributionMode(VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return DistributionMode::DUPLICATED;
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        return DistributionMode::SEGMENTED;
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the distribution mode for the "
                   "weights tensor",
                   strategy);
    }
}

DistributionMode vpux::VPU::getOutputTensorDistributionMode(VPU::ClusteredOpInterface clusteredOp,
                                                            VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight) {
        if (VPU::isArchVPUX3XXX(VPU::getArch(clusteredOp))) {
            return DistributionMode::SEGMENTED;
        }
        return DistributionMode::OVERLAPPED;
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverWidth) {
        return DistributionMode::OVERLAPPED;
    } else if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        if (isSegmentedOutputCompatible(clusteredOp.getOperation())) {
            return DistributionMode::SEGMENTED;
        }
        return DistributionMode::DUPLICATED | DistributionMode::SEGMENTED;
    } else if (strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return DistributionMode::MULTICASTED | DistributionMode::SEGMENTED;
    } else if (strategy == VPU::MultiClusterStrategy::Clustering) {
        return DistributionMode::DUPLICATED;
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the distribution mode for the "
                   "output tensor",
                   strategy);
    }
}

DistributionMode vpux::VPU::getActivationWindowTensorDistributionMode(VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight ||
        strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return DistributionMode::DUPLICATED;
    } else {
        VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the distribution mode for the "
                   " activation window tensor",
                   strategy);
    }
}

DistributionMode vpux::VPU::getInstructionListTableTensorDistributionMode(VPU::MultiClusterStrategy strategy) {
    if (strategy == VPU::MultiClusterStrategy::SplitOverHeightOverlapped ||
        strategy == VPU::MultiClusterStrategy::SplitOverHeight ||
        strategy == VPU::MultiClusterStrategy::SplitOverKernel || strategy == VPU::MultiClusterStrategy::Clustering ||
        strategy == VPU::MultiClusterStrategy::HKSwitch) {
        return DistributionMode::DUPLICATED;
    }

    VPUX_THROW("{0} is an invalid multi-cluster strategy, unable to determine the distribution mode for the "
               "instruction list table tensor",
               strategy);
}

NCEClusterTilingOp vpux::VPU::createDistributedCopyOut(VPU::ClusteredOpInterface clusteredOp,
                                                       NCEClusterTilingOp clusterTilingOp) {
    mlir::OpBuilder builder(clusteredOp);
    auto origOutput = clusteredOp->getResult(0);
    const auto origOutType = origOutput.getType().cast<NDTypeInterface>();
    const auto origOutMemSpace = origOutType.getMemSpace();

    const auto outputTensorBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc,
                                             mlir::ValueRange newOperands) {
        auto outputTensorDistributedCopyOp = builder.create<VPU::CopyOp>(loc, newOperands[0], origOutMemSpace);
        builder.create<YieldOp>(loc, outputTensorDistributedCopyOp->getResults());
    };

    return builder.create<NCEClusterTilingOp>(clusterTilingOp->getLoc(), origOutType, clusterTilingOp->getResult(0),
                                              outputTensorBodyBuilder);
}

NCEClusterTilingOp vpux::VPU::createDistributedCopyOut(mlir::Operation* sourceOp, vpux::NDTypeInterface outputType) {
    mlir::OpBuilder builder(sourceOp);
    builder.setInsertionPointAfter(sourceOp);
    const auto origOutMemSpace = IndexedSymbolAttr::get(sourceOp->getContext(), stringifyEnum(MemoryKind::DDR), 0);

    const auto outputTensorBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc,
                                             mlir::ValueRange newOperands) {
        auto outputTensorDistributedCopyOp = builder.create<VPU::CopyOp>(loc, newOperands[0], origOutMemSpace);
        builder.create<YieldOp>(loc, outputTensorDistributedCopyOp->getResults());
    };

    return builder.create<NCEClusterTilingOp>(sourceOp->getLoc(), outputType, sourceOp->getResult(0),
                                              outputTensorBodyBuilder);
}

int64_t vpux::VPU::getSOHPerClusterHeightAlignment(int64_t inputWidth) {
    // W * h_per_cluster must be divisible by 4, thus
    // if W % 4 == 0, then h alignment needs to be 1
    // if W % 2 == 0, then h alignment needs to be 2
    // else h alignment needs to be 4
    if (inputWidth % 4 == 0) {
        return 1;
    } else if (inputWidth % 2 == 0) {
        return 2;
    }

    return 4;
}

int64_t vpux::VPU::getSOHMinimalHeightAlignment(vpux::ShapeRef shape, int64_t numClusters, VPU::ArchKind arch) {
    if (!VPU::isArchVPUX3XXX(arch)) {
        return 1;
    }
    auto heightAlignment = getSOHPerClusterHeightAlignment(shape[Dims4D::Act::W]);
    for (int64_t alignment = 1; alignment < heightAlignment; alignment *= 2) {
        const auto hPerCluster = alignValUp(divUp(shape[Dims4D::Act::H], numClusters), alignment);
        if (hPerCluster * shape[Dims4D::Act::W] % 4 == 0) {
            heightAlignment = alignment;
            break;
        }
    }
    return heightAlignment;
};

// When doing SOH not all combinations are supported by HW in terms of how input is segmented
// Following rules need to be satisfied:
// - height of clusters from 0 to N - 1 must be equal
// - height of last cluster (which stores the remainder) must be <= of height of previous clusters
// - Width * height_per_cluster (for cluster 0 - N-1) must be multiple of 4
// Last requirement not needed for arch VPUX30XX and VPUX311X if operation is of depth-wise type
// (i.e. DWCONV or MAXPOOL)
bool vpux::VPU::isSOHSupportedByDPU(ShapeRef inputShape, int64_t numClusters, bool DWTypeOp, ArchKind arch) {
    const auto IH = inputShape[Dims4D::Act::H];
    const auto IW = inputShape[Dims4D::Act::W];

    auto hPerCluster = divUp(IH, numClusters);
    auto noDWAlignment = DWTypeOp && arch != VPU::ArchKind::VPUX37XX;
    auto alignment = (noDWAlignment) ? 1 : getSOHPerClusterHeightAlignment(IW);

    hPerCluster = alignValUp(hPerCluster, alignment);

    auto hLastCluster = IH - hPerCluster * (numClusters - 1);

    return (hLastCluster > 0);
}

mlir::IntegerAttr vpux::VPU::getOptimalNumClusters(VPU::ClusteredOpInterface clusteredOp, int64_t OC,
                                                   VPU::MultiClusterStrategy strategy) {
    auto* ctx = clusteredOp->getContext();
    auto module = clusteredOp->getParentOfType<mlir::ModuleOp>();

    // Both ACT Shaves and DPUs are grouped together in NCE clusters, in a symmetric manner.
    // For VPUX37XX and subsequent, each NCE cluster 1 DPU and 2 ACT shaves.
    // Thus shaves have the availability for distributing across clusters similar to DPUs.
    auto numClustersAvailableForCompilation =
            getIntAttr(ctx, IE::getAvailableExecutor(module, ExecutorKind::NCE).count());
    auto optimalNumberOfClusters = numClustersAvailableForCompilation;

    // Here the number of clusters to be used for an individual SOK layer is determined
    // such that additional alignment of the per cluster output channels is not required.
    // For example 80 output channels, the weights should only be split on 3 clusters [32, 32, 16].
    // Also when creating the copy-in for the activation we need to ensure that the number
    // of clusters that the input is duplicated to is also 3 clusters in this case.
    // Therefore we use the variable optimalNumberOfClusters for both purposes here, to detemine
    // num_tiles and numClusters for the activations and the weights.
    if (strategy == VPU::MultiClusterStrategy::SplitOverKernel) {
        int64_t numClustersToUseForLayer = numClustersAvailableForCompilation.getValue().getSExtValue();
        if (mlir::isa<VPU::SWOpInterface>(clusteredOp.getOperation())) {
            numClustersToUseForLayer = std::min(numClustersToUseForLayer, OC);
        } else {
            auto uniformDistributedSegments = !VPU::isArchVPUX3XXX(VPU::getArch(clusteredOp));
            numClustersToUseForLayer =
                    getNumberOfClustersForSOKToAvoidAlignment(OC, numClustersToUseForLayer, uniformDistributedSegments);
        }
        optimalNumberOfClusters = mlir::IntegerAttr::get(getInt64Type(ctx), numClustersToUseForLayer);
    }
    return optimalNumberOfClusters;
}
VPU::DistributedTensorType vpux::VPU::createDistributedTensorType(
        VPU::ClusteredOpInterface clusteredOp, vpux::NDTypeInterface inputType, DistributionMode distributionMode,
        mlir::ArrayAttr numTiles, mlir::IntegerAttr numClusters, mlir::ArrayAttr alignment, mlir::ArrayAttr kernel,
        VPU::PaddingAttr pad, mlir::ArrayAttr stride, mlir::UnitAttr equalComputeAndMemoryView) {
    return llvm::TypeSwitch<mlir::Operation*, DistributedTensorType>(clusteredOp.getOperation())
            .Case<VPU::SWOpInterface>([&](VPU::SWOpInterface swOp) {
                return createDistributedTensorType(swOp, inputType, distributionMode, numTiles, numClusters, alignment);
            })
            .Case<VPU::NCEOpInterface>([&](VPU::NCEOpInterface nceOp) {
                return createDistributedTensorType(nceOp, inputType, distributionMode, numTiles, numClusters, alignment,
                                                   kernel, pad, stride, equalComputeAndMemoryView);
            })
            .Case<VPU::ConcatOp>([&](VPU::ConcatOp concatOp) {
                return createDistributedTensorType(concatOp, inputType, distributionMode, numTiles, numClusters,
                                                   alignment, kernel, pad, stride);
            })
            .Default([clusteredOp](mlir::Operation*) -> DistributedTensorType {
                VPUX_THROW("unsupported operation for createDistributedTensorType: {0}", clusteredOp);
            });
}

DistributedTensorType vpux::VPU::createDistributedTensorType(VPU::SWOpInterface swOp, vpux::NDTypeInterface inputType,
                                                             DistributionMode distributionMode,
                                                             mlir::ArrayAttr numTiles,
                                                             mlir::IntegerAttr optimalNumberOfClusters,
                                                             mlir::ArrayAttr alignment) {
    auto* ctx = swOp->getContext();
    DistributedTensorAttr distributedActivationTensorAttr;
    const auto activationTensorDistributionModeAttr = DistributionModeAttr::get(ctx, distributionMode);

    const auto shape = inputType.getShape();
    const auto uniformDistributedSegments =
            !VPU::isArchVPUX3XXX(VPU::getArch(swOp.getOperation())) ? mlir::UnitAttr::get(ctx) : nullptr;

    if (distributionMode == DistributionMode::DUPLICATED) {
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, nullptr, nullptr, nullptr, nullptr, optimalNumberOfClusters,
                alignment, uniformDistributedSegments, nullptr, nullptr, nullptr, ctx);
    } else if (VPU ::bitEnumContains(distributionMode, VPU::DistributionMode::SEGMENTED)) {
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, numTiles, nullptr, nullptr, nullptr, optimalNumberOfClusters,
                alignment, uniformDistributedSegments, nullptr, nullptr, nullptr, ctx);
    } else if (distributionMode == VPU::DistributionMode::OVERLAPPED) {
        VPUX_THROW_UNLESS(swOp->getNumResults() == 1, "More than one result for Sw op: {0}", swOp);
        auto outShape = getShape(swOp->getResult(0));
        Optional<ArrayRef<int64_t>> alignmentValue =
                alignment == nullptr ? None : Optional<ArrayRef<int64_t>>(parseIntArrayAttr<int64_t>(alignment));
        auto outTiles = fillDividedTiles(Shape(parseIntArrayAttr<int64_t>(numTiles)), outShape, alignmentValue);
        auto tilingBuilder = mlir::dyn_cast<VPU::TilingBuilderOpInterface>(swOp.getOperation());
        VPUX_THROW_WHEN(tilingBuilder == nullptr, "Cannot cast op to TilingBuilderOpInterface at {0}", swOp->getLoc());
        SmallVector<InputTiling> inputTiles;
        for (auto outTile : outTiles) {
            inputTiles.push_back(tilingBuilder.backInferTileInfo(outTile, Logger::global()));
            VPUX_THROW_UNLESS(inputTiles.back().tiles.size() == 1, "Unexpected input operands size {0}",
                              inputTiles.back().tiles.size());
        }

        SmallVector<SmallVector<int64_t>> inputPerClusterShape;
        SmallVector<SmallVector<int64_t>> inputPerClusterOffset;
        for (auto i : irange(outTiles.size())) {
            inputPerClusterShape.push_back(to_small_vector(inputTiles[i].tiles[0].shape));
            inputPerClusterOffset.push_back(to_small_vector(inputTiles[i].tiles[0].offsets));
        }
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, numTiles, nullptr, nullptr, nullptr, optimalNumberOfClusters,
                alignment, uniformDistributedSegments, vpux::getIntArrayOfArray(ctx, inputPerClusterShape),
                vpux::getIntArrayOfArray(ctx, inputPerClusterOffset), nullptr, ctx);
    } else {
        VPUX_THROW("Unsupported distribution mode: {0}", VPU::stringifyDistributionMode(distributionMode));
    }

    const auto memSpace = vpux::IndexedSymbolAttr::get(MemoryKindAttr::get(ctx, MemoryKind::CMX_NN));

    const auto order = mlir::AffineMapAttr::get(inputType.getDimsOrder().toAffineMap(ctx));
    auto elemType = inputType.getElementType();

    return DistributedTensorType::get(ctx, shape.raw(), elemType, order, memSpace, distributedActivationTensorAttr);
}

DistributedTensorType vpux::VPU::createDistributedTensorType(VPU::NCEOpInterface nceOp, vpux::NDTypeInterface inputType,
                                                             DistributionMode distributionMode,
                                                             mlir::ArrayAttr numTiles,
                                                             mlir::IntegerAttr optimalNumberOfClusters,
                                                             mlir::ArrayAttr alignment, mlir::ArrayAttr kernel,
                                                             VPU::PaddingAttr pad, mlir::ArrayAttr stride,
                                                             mlir::UnitAttr equalComputeAndMemoryView) {
    auto* ctx = nceOp->getContext();
    DistributedTensorAttr distributedActivationTensorAttr;
    auto module = nceOp->getParentOfType<mlir::ModuleOp>();
    auto nceResOp = IE::getAvailableExecutor(module, ExecutorKind::NCE);
    const auto activationTensorDistributionModeAttr = DistributionModeAttr::get(ctx, distributionMode);

    const auto shape = inputType.getShape();
    const auto uniformDistributedSegments =
            !VPU::isArchVPUX3XXX(VPU::getArch(nceOp.getOperation())) ? mlir::UnitAttr::get(ctx) : nullptr;
    if (distributionMode == DistributionMode::OVERLAPPED) {
        optimalNumberOfClusters = getIntAttr(ctx, nceResOp.count());
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, numTiles, kernel, pad, stride, optimalNumberOfClusters, alignment,
                uniformDistributedSegments, nullptr, nullptr, equalComputeAndMemoryView, ctx);
    } else if (distributionMode == DistributionMode::DUPLICATED) {
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, nullptr, nullptr, nullptr, nullptr, optimalNumberOfClusters,
                alignment, uniformDistributedSegments, nullptr, nullptr, nullptr, ctx);
    } else if (VPU ::bitEnumContains(distributionMode, VPU::DistributionMode::SEGMENTED)) {
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, numTiles, nullptr, nullptr, nullptr, optimalNumberOfClusters,
                alignment, uniformDistributedSegments, nullptr, nullptr, nullptr, ctx);
    } else {
        VPUX_THROW("Unsupported distribution mode: {0}", VPU::stringifyDistributionMode(distributionMode));
    }

    const auto memSpace = vpux::IndexedSymbolAttr::get(MemoryKindAttr::get(ctx, MemoryKind::CMX_NN));

    const auto order = mlir::AffineMapAttr::get(inputType.getDimsOrder().toAffineMap(ctx));
    auto elemType = inputType.getElementType();

    return DistributedTensorType::get(ctx, shape.raw(), elemType, order, memSpace, distributedActivationTensorAttr);
}

DistributedTensorType vpux::VPU::createDistributedTensorType(VPU::ConcatOp concatOp, vpux::NDTypeInterface inputType,
                                                             DistributionMode distributionMode,
                                                             mlir::ArrayAttr numTiles,
                                                             mlir::IntegerAttr optimalNumberOfClusters,
                                                             mlir::ArrayAttr alignment, mlir::ArrayAttr kernel,
                                                             VPU::PaddingAttr pad, mlir::ArrayAttr stride) {
    auto* ctx = concatOp->getContext();
    DistributedTensorAttr distributedActivationTensorAttr;
    const auto activationTensorDistributionModeAttr = DistributionModeAttr::get(ctx, distributionMode);

    const auto shape = inputType.getShape();
    const auto uniformDistributedSegments =
            !VPU::isArchVPUX3XXX(VPU::getArch(concatOp.getOperation())) ? mlir::UnitAttr::get(ctx) : nullptr;
    if (distributionMode == DistributionMode::DUPLICATED) {
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, nullptr, nullptr, nullptr, nullptr, optimalNumberOfClusters,
                alignment, uniformDistributedSegments, nullptr, nullptr, nullptr, ctx);
    } else if (VPU ::bitEnumContains(distributionMode, VPU::DistributionMode::SEGMENTED)) {
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, numTiles, nullptr, nullptr, nullptr, optimalNumberOfClusters,
                alignment, uniformDistributedSegments, nullptr, nullptr, nullptr, ctx);
    } else if (distributionMode == DistributionMode::OVERLAPPED) {
        distributedActivationTensorAttr = DistributedTensorAttr::get(
                activationTensorDistributionModeAttr, numTiles, kernel, pad, stride, optimalNumberOfClusters, alignment,
                uniformDistributedSegments, nullptr, nullptr, nullptr, ctx);
    } else {
        VPUX_THROW("Unsupported distribution mode {0} for op {1}", VPU::stringifyDistributionMode(distributionMode),
                   concatOp);
    }

    const auto memSpace = vpux::IndexedSymbolAttr::get(MemoryKindAttr::get(ctx, MemoryKind::CMX_NN));

    const auto order = mlir::AffineMapAttr::get(inputType.getDimsOrder().toAffineMap(ctx));
    auto elemType = inputType.getElementType();

    return DistributedTensorType::get(ctx, shape.raw(), elemType, order, memSpace, distributedActivationTensorAttr);
}

NCEClusterTilingOp vpux::VPU::createDistributedCopyIn(VPU::ClusteredOpInterface clusteredOp, mlir::Value input,
                                                      DistributionMode distributionMode, mlir::ArrayAttr numTiles,
                                                      mlir::ArrayAttr alignment, VPU::MultiClusterStrategy strategy) {
    auto OC = clusteredOp->getResult(0).getType().cast<vpux::NDTypeInterface>().getShape()[Dims4D::Act::C];
    auto numClusters = getOptimalNumClusters(clusteredOp, OC, strategy);

    mlir::ArrayAttr kernelAttr = nullptr;
    VPU::PaddingAttr padAttr = nullptr;
    mlir::ArrayAttr strideAttr = nullptr;
    if (distributionMode == DistributionMode::OVERLAPPED) {
        auto overlappedParams = getActivationOverlappedParams(clusteredOp, parseIntArrayAttr<int64_t>(numTiles));
        kernelAttr = overlappedParams.kernel;
        padAttr = overlappedParams.pads;
        strideAttr = overlappedParams.stride;
    }

    vpux::NDTypeInterface inputTensorDistributedTensorType;
    if (auto sparseInputType = input.getType().dyn_cast<VPU::SparseTensorType>()) {
        auto distributedDataType = createDistributedTensorType(
                clusteredOp, sparseInputType.getData().cast<vpux::NDTypeInterface>(), distributionMode, numTiles,
                numClusters, alignment, kernelAttr, padAttr, strideAttr);

        VPU::DistributedTensorType distributedSMType = nullptr;
        if (sparseInputType.getSparsityMap() != nullptr) {
            distributedSMType = createDistributedTensorType(
                    clusteredOp, sparseInputType.getSparsityMap().cast<vpux::NDTypeInterface>(), distributionMode,
                    numTiles, numClusters, alignment, kernelAttr, padAttr, strideAttr);
        }

        VPU::DistributedTensorType distributedSEType = nullptr;
        if (sparseInputType.getStorageElementTable() != nullptr) {
            auto seTableAlignment = parseIntArrayAttr<int64_t>(alignment);
            seTableAlignment[Dims4D::Act::C.ind()] = 1;
            auto seTableAlignmentAttr = getIntArrayAttr(clusteredOp.getContext(), seTableAlignment);
            distributedSEType = createDistributedTensorType(
                    clusteredOp, sparseInputType.getStorageElementTable().cast<vpux::NDTypeInterface>(),
                    distributionMode, numTiles, numClusters, seTableAlignmentAttr, kernelAttr, padAttr, strideAttr);
        }

        inputTensorDistributedTensorType = VPU::SparseTensorType::get(
                distributedDataType, distributedSMType, distributedSEType, sparseInputType.getIsWeights(),
                sparseInputType.getCompressionScheme(), sparseInputType.getSeAttr());

    } else {
        inputTensorDistributedTensorType = createDistributedTensorType(
                clusteredOp, input.getType().cast<vpux::NDTypeInterface>(), distributionMode, numTiles, numClusters,
                alignment, kernelAttr, padAttr, strideAttr);
    }
    mlir::OpBuilder builder(clusteredOp);
    builder.setInsertionPoint(clusteredOp);
    const auto inputTensorBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc,
                                            mlir::ValueRange newOperands) {
        const auto memSpace = IndexedSymbolAttr::get(builder.getContext(), stringifyEnum(MemoryKind::CMX_NN));
        auto inputTensorDistributedCopyOp =
                builder.create<VPU::CopyOp>(clusteredOp->getLoc(), newOperands[0], memSpace);
        builder.create<YieldOp>(loc, inputTensorDistributedCopyOp->getResults());
    };

    auto distributedInputCopyOp = builder.create<NCEClusterTilingOp>(
            clusteredOp->getLoc(), inputTensorDistributedTensorType, input, inputTensorBodyBuilder);

    return distributedInputCopyOp;
}

inline bool needToAlign(VPU::ClusteredOpInterface clusteredOp, vpux::NDTypeInterface inputType) {
    // No need to align CMajor NCE Conv ops
    // Eltwise and SW operations do not need to align but the "alignment" attribute is required
    // to keep the continuity of the distribution type
    return !(mlir::isa<VPU::NCEConvolutionOp>(clusteredOp) &&
             VPU::NCEInvariant::isChannelMajorCompatible(VPU::getArch(clusteredOp.getOperation()), inputType));
}

VPU::DistributedTypeInterface vpux::VPU::getDistributedActivationTypeFromOp(VPU::ClusteredOpInterface clusteredOp,
                                                                            vpux::NDTypeInterface inputType,
                                                                            mlir::IntegerAttr numClusters) {
    VPUX_THROW_UNLESS(clusteredOp.getMultiClusterStrategyAttr().hasValue(),
                      "Op {0} does not have multiClusterStrategy attribute", clusteredOp->getLoc());
    return getDistributedActivationTypeFromOp(clusteredOp, inputType, numClusters,
                                              clusteredOp.getMultiClusterStrategyAttr().getValue());
}

VPU::DistributedTypeInterface vpux::VPU::getDistributedActivationTypeFromOp(VPU::ClusteredOpInterface clusteredOp,
                                                                            vpux::NDTypeInterface inputType,
                                                                            mlir::IntegerAttr numClusters,
                                                                            VPU::MultiClusterStrategy customStrategy,
                                                                            mlir::ArrayAttr customAlignment) {
    auto activationTensorDistributionMode = getActivationTensorDistributionMode(clusteredOp, customStrategy);
    auto activationTensorNumTiles = getActivationTensorNumTiles(clusteredOp, numClusters.getInt(), customStrategy);
    if (mlir::isa<VPU::SWOpInterface>(clusteredOp.getOperation())) {
        activationTensorDistributionMode = getSWInputTensorDistributionMode(clusteredOp, customStrategy, inputType);
        activationTensorNumTiles =
                getSWInputTensorNumTiles(clusteredOp, numClusters.getInt(), customStrategy, inputType);
    }

    if (customAlignment == nullptr && needToAlign(clusteredOp, inputType)) {
        const auto activationAlignment =
                getActivationTensorAlignment(clusteredOp, numClusters, customStrategy, inputType);
        if (activationAlignment.hasValue()) {
            customAlignment = getIntArrayAttr(clusteredOp.getContext(), activationAlignment.getValue());
        }
    }

    mlir::ArrayAttr kernelAttr = nullptr;
    VPU::PaddingAttr padAttr = nullptr;
    mlir::ArrayAttr strideAttr = nullptr;
    if (activationTensorDistributionMode == DistributionMode::OVERLAPPED) {
        auto overlappedParams = getActivationOverlappedParams(clusteredOp, activationTensorNumTiles);
        kernelAttr = overlappedParams.kernel;
        padAttr = overlappedParams.pads;
        strideAttr = overlappedParams.stride;
    }

    auto activationTensorNumTilesAttr = getIntArrayAttr(clusteredOp.getContext(), activationTensorNumTiles);

    if (auto sparseType = inputType.dyn_cast<VPU::SparseTensorType>()) {
        VPUX_THROW_UNLESS(sparseType.getSparsityMap() != nullptr, "Missing input sparsity map");
        auto distributedDataType = createDistributedTensorType(
                clusteredOp, sparseType.getData().cast<vpux::NDTypeInterface>(), activationTensorDistributionMode,
                activationTensorNumTilesAttr, numClusters, customAlignment, kernelAttr, padAttr, strideAttr);
        auto distributedSMType =
                createDistributedTensorType(clusteredOp, sparseType.getSparsityMap().cast<vpux::NDTypeInterface>(),
                                            activationTensorDistributionMode, activationTensorNumTilesAttr, numClusters,
                                            customAlignment, kernelAttr, padAttr, strideAttr);
        if (sparseType.getStorageElementTable() != nullptr) {
            auto distributedSEType = createDistributedTensorType(
                    clusteredOp, sparseType.getStorageElementTable().cast<vpux::NDTypeInterface>(),
                    activationTensorDistributionMode, activationTensorNumTilesAttr, numClusters, customAlignment,
                    kernelAttr, padAttr, strideAttr);
            return VPU::SparseTensorType::get(distributedDataType, distributedSMType, distributedSEType);
        }
        return VPU::SparseTensorType::get(distributedDataType, distributedSMType);
    }

    return createDistributedTensorType(clusteredOp, inputType, activationTensorDistributionMode,
                                       activationTensorNumTilesAttr, numClusters, customAlignment, kernelAttr, padAttr,
                                       strideAttr);
}

VPU::DistributedTypeInterface vpux::VPU::getDistributedFilterTypeFromOp(VPU::NCEOpInterface nceOp,
                                                                        vpux::NDTypeInterface inputType,
                                                                        mlir::IntegerAttr numClusters) {
    auto clusteredOp = mlir::dyn_cast<VPU::ClusteredOpInterface>(nceOp.getOperation());
    VPUX_THROW_UNLESS(clusteredOp.getMultiClusterStrategyAttr().hasValue(),
                      "Op {0} does not have multiClusterStrategy attribute", nceOp->getLoc());
    return getDistributedFilterTypeFromOp(nceOp, inputType, numClusters,
                                          clusteredOp.getMultiClusterStrategyAttr().getValue());
}

VPU::DistributedTypeInterface vpux::VPU::getDistributedFilterTypeFromOp(VPU::NCEOpInterface nceOp,
                                                                        vpux::NDTypeInterface inputType,
                                                                        mlir::IntegerAttr numClusters,
                                                                        VPU::MultiClusterStrategy customStrategy) {
    mlir::ArrayAttr weightAlignmentAttr = nullptr;
    const auto clusteredOp = mlir::dyn_cast<VPU::ClusteredOpInterface>(nceOp.getOperation());
    const auto weightsTensorDistributionMode = getWeightsTensorDistributionMode(customStrategy);
    const auto weightsTensorNumTiles = getIntArrayAttr(
            nceOp.getContext(), getWeightsTensorNumTiles(clusteredOp, inputType, numClusters.getInt(), customStrategy));

    const auto weightAlignment = getWeightsTensorAlignment(customStrategy);

    if (weightAlignment.hasValue()) {
        weightAlignmentAttr = getIntArrayAttr(nceOp.getContext(), weightAlignment.getValue());
    }

    if (auto sparseType = inputType.dyn_cast<VPU::SparseTensorType>()) {
        VPUX_THROW_UNLESS(sparseType.getSparsityMap() != nullptr, "Missing filter sparsity map");
        auto distributedDataType = createDistributedTensorType(
                nceOp, sparseType.getData().cast<vpux::NDTypeInterface>(), weightsTensorDistributionMode,
                weightsTensorNumTiles, numClusters, weightAlignmentAttr);
        auto distributedSMType = createDistributedTensorType(
                nceOp, sparseType.getSparsityMap().cast<vpux::NDTypeInterface>(), weightsTensorDistributionMode,
                weightsTensorNumTiles, numClusters, weightAlignmentAttr);
        auto isWeights = mlir::UnitAttr::get(nceOp.getContext());
        return VPU::SparseTensorType::get(distributedDataType, distributedSMType, nullptr, isWeights,
                                          sparseType.getCompressionScheme());
    }

    return createDistributedTensorType(nceOp, inputType, weightsTensorDistributionMode, weightsTensorNumTiles,
                                       numClusters, weightAlignmentAttr);
}

VPU::DistributedTypeInterface vpux::VPU::getDistributedOutputTypeFromOp(VPU::ClusteredOpInterface clusteredOp,
                                                                        vpux::NDTypeInterface inputType,
                                                                        mlir::IntegerAttr numClusters) {
    VPUX_THROW_UNLESS(clusteredOp.getMultiClusterStrategyAttr().hasValue(),
                      "Op {0} does not have multiClusterStrategy attribute", clusteredOp->getLoc());
    return getDistributedOutputTypeFromOp(clusteredOp, inputType, numClusters,
                                          clusteredOp.getMultiClusterStrategyAttr().getValue());
}

VPU::DistributedTypeInterface vpux::VPU::getDistributedOutputTypeFromOp(VPU::ClusteredOpInterface clusteredOp,
                                                                        vpux::NDTypeInterface inputType,
                                                                        mlir::IntegerAttr numClusters,
                                                                        VPU::MultiClusterStrategy customStrategy) {
    const auto outputTensorDistributionMode = getOutputTensorDistributionMode(clusteredOp, customStrategy);
    const auto outputTensorNumTiles = getOutputTensorNumTiles(clusteredOp, numClusters.getInt(), customStrategy);

    mlir::ArrayAttr outputAlignmentAttr = nullptr;
    // Set output alignment for HW layer
    auto clusteredHWNeedsChannelAlignment = [](const VPU::ClusteredOpInterface& hwOp) -> bool {
        return mlir::isa<VPU::NCEOpInterface>(*hwOp) &&
               needToAlign(hwOp, hwOp->getOperand(0).getType().cast<vpux::NDTypeInterface>());
    };
    auto inputAlignment = getActivationTensorAlignment(clusteredOp, numClusters, customStrategy);
    if (mlir::isa<VPU::NCEEltwiseOp, VPU::NCEPermuteQuantizeOp>(clusteredOp.getOperation()) &&
        inputAlignment.hasValue()) {
        // Eltwise input and output must have the same alignment/shape due to the hardware limitation
        outputAlignmentAttr = getIntArrayAttr(clusteredOp->getContext(), inputAlignment.getValue());
    } else if (clusteredHWNeedsChannelAlignment(clusteredOp)) {
        const auto outputAlignment = getOutputTensorAlignment(customStrategy);
        if (outputAlignment.hasValue()) {
            outputAlignmentAttr = getIntArrayAttr(clusteredOp.getContext(), outputAlignment.getValue());
        }
    }

    // Set output alignment for SW layer
    if (mlir::isa<VPU::SWOpInterface>(clusteredOp.getOperation())) {
        if (isSWOpWithAlignedOutputChannelReq(clusteredOp)) {
            outputAlignmentAttr = getIntArrayAttr(clusteredOp.getContext(), DISTRIBUTED_C_ALIGNMENT);
        }
    }

    mlir::ArrayAttr kernelAttr = nullptr;
    VPU::PaddingAttr padAttr = nullptr;
    mlir::ArrayAttr strideAttr = nullptr;
    mlir::UnitAttr equalComputeAndMemoryView = nullptr;
    if (outputTensorDistributionMode == DistributionMode::OVERLAPPED) {
        auto overlappedParams = getOutputOverlappedParams(clusteredOp, outputTensorNumTiles);
        kernelAttr = overlappedParams.kernel;
        padAttr = overlappedParams.pads;
        strideAttr = overlappedParams.stride;
        equalComputeAndMemoryView = overlappedParams.equalComputeAndMemoryView;
    }

    auto outputTensorNumTilesAttr = getIntArrayAttr(clusteredOp.getContext(), outputTensorNumTiles);

    if (auto sparseType = inputType.dyn_cast<VPU::SparseTensorType>()) {
        VPUX_THROW_UNLESS(sparseType.getSparsityMap() != nullptr, "Missing output sparsity map");
        VPUX_THROW_UNLESS(sparseType.getStorageElementTable() == nullptr,
                          "ODU-generated storage element table is not supported");
        auto distributedDataType = createDistributedTensorType(
                clusteredOp, sparseType.getData().cast<vpux::NDTypeInterface>(), outputTensorDistributionMode,
                outputTensorNumTilesAttr, numClusters, outputAlignmentAttr, kernelAttr, padAttr, strideAttr);
        auto distributedSMType = createDistributedTensorType(
                clusteredOp, sparseType.getSparsityMap().cast<vpux::NDTypeInterface>(), outputTensorDistributionMode,
                outputTensorNumTilesAttr, numClusters, outputAlignmentAttr, kernelAttr, padAttr, strideAttr);
        return VPU::SparseTensorType::get(distributedDataType, distributedSMType);
    }

    return createDistributedTensorType(clusteredOp, inputType, outputTensorDistributionMode, outputTensorNumTilesAttr,
                                       numClusters, outputAlignmentAttr, kernelAttr, padAttr, strideAttr,
                                       equalComputeAndMemoryView);
}

Shape vpux::VPU::getLargestClusterOutputShape(VPU::ClusteredOpInterface clusteredOp,
                                              VPU::MultiClusterStrategy strategy) {
    auto outputType = clusteredOp->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
    const int64_t OC = outputType.getShape()[Dims4D::Act::C];
    auto numClustersAttr = getOptimalNumClusters(clusteredOp, OC, strategy);
    auto distributedOutputTensorType =
            getDistributedOutputTypeFromOp(clusteredOp, outputType, numClustersAttr, strategy);
    auto distributedDataType =
            distributedOutputTensorType.getDistributedTypes().front().cast<VPU::DistributedTensorType>();
    return distributedDataType.getLargestCompactShape();
}
