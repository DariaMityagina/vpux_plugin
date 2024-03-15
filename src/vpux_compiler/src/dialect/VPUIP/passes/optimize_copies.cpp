//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPUIP/passes.hpp"

#include "vpux/compiler/dialect/VPU/IR/attributes.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/nce_sparsity.hpp"
#include "vpux/compiler/dialect/VPUIP/ops.hpp"
#include "vpux/compiler/dialect/VPUIP/utils.hpp"
#include "vpux/compiler/dialect/VPURT/ops.hpp"
#include "vpux/compiler/utils/permute_utils.hpp"

#include "vpux/compiler/core/aliases_info.hpp"

#include "vpux/compiler/utils/analysis.hpp"
#include "vpux/compiler/utils/rewriter.hpp"
#include "vpux/compiler/utils/types.hpp"

#include "vpux/utils/core/range.hpp"

#include <mlir/IR/PatternMatch.h>
#include <mlir/Transforms/GreedyPatternRewriteDriver.h>

using namespace vpux;

namespace {

bool isCMX2CMXCopy(vpux::VPU::MemoryKind srcMemory, vpux::VPU::MemoryKind dstMemory) {
    return srcMemory == dstMemory && srcMemory == VPU::MemoryKind::CMX_NN;
}

// To explicitly control the patterns exec order to assure dependency
// benefitLevels[0] is highest benefit level and represent the relative pattern is the first one to run
const uint32_t levelCount = 4;
SmallVector<mlir::PatternBenefit> benefitLevels = getBenefitLevels(levelCount);

// Check the user of the copyOp is an EltwiseOp with is_inplace
bool isEltwiseInplaceUser(VPUIP::CopyOp copyOp) {
    mlir::Operation* op = copyOp.getOperation();
    auto clusterTiling = copyOp->getParentOfType<VPUIP::NCEClusterTilingOp>();
    if (clusterTiling) {
        op = clusterTiling.getOperation();
    }

    auto opUsers = op->getResult(0).getUsers();
    if (opUsers.empty()) {
        return false;
    }

    if (!op->hasOneUse()) {
        auto firstUserOp = *opUsers.begin();
        for (auto userOp : llvm::make_early_inc_range(opUsers)) {
            if (firstUserOp != userOp) {
                return false;
            }
        }
    }

    auto copyUser = *opUsers.begin();
    auto userClusterTilingOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(copyUser);
    if (userClusterTilingOp != nullptr) {
        copyUser = userClusterTilingOp.getInnerTaskOp();
    }

    const auto isEltwiseInplaceCandidate = [](VPUIP::NCEClusterTaskOp op) {
        if (op.getTaskType() != VPUIP::NCETaskType::ELTWISE) {
            return false;
        }
        return op.getIsInplace().value_or(false);
    };

    auto userClusterTaskOp = mlir::dyn_cast<VPUIP::NCEClusterTaskOp>(copyUser);
    if (userClusterTaskOp != nullptr) {
        return isEltwiseInplaceCandidate(userClusterTaskOp);
    }

    return false;
}

//
// CopyOpSequence
//

class CopyOpSequence final : public mlir::OpRewritePattern<VPUIP::CopyOp> {
public:
    CopyOpSequence(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : mlir::OpRewritePattern<VPUIP::CopyOp>(ctx, benefit), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult CopyOpSequence::matchAndRewrite(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter) const {
    /*
     Remove redundant Copy-to-Copy sequence:
         ParentCopyOp
              |
           CopyOp
     */
    _log.trace("CopyOpSequence: Copy at {0}", copyOp->getLoc());
    auto nestedLogger = _log.nest();
    auto parentCopyOp = copyOp.getInput().getDefiningOp<VPUIP::CopyOp>();
    if (parentCopyOp == nullptr) {
        StringRef parentOpName = "None";
        if (auto parentOp = copyOp.getInput().getDefiningOp()) {
            parentOpName = parentOp->getName().getStringRef();
        } else if (copyOp.getInput().isa<mlir::BlockArgument>()) {
            parentOpName = "BlockArgument";
        }
        nestedLogger.trace("Cannot match because parent isn't CopyOp, but '{0}'", parentOpName);
        return mlir::failure();
    }

    if (parentCopyOp.getOutputBuff().isa<mlir::BlockArgument>() ||
        !(isBufAllocOp(parentCopyOp.getOutputBuff().getDefiningOp()) ||
          VPUIP::getRootAlloc<mlir::memref::AllocOp>(parentCopyOp.getOutputBuff()))) {
        nestedLogger.trace("Cannot match because parent's output buffer is not produced by allocation");
        return mlir::failure();
    }

    for (auto user : parentCopyOp.getOutput().getUsers()) {
        if (mlir::isa<VPUIP::SubViewOp>(user)) {
            // if intermediate SubViewOp users, skip due to accuracy loss
            // TODO E#35612: implement support for intermediate SubViewOp users
            nestedLogger.trace("Cannot match because intermediate SubViewOp users, skip due to accuracy loss");
            return mlir::failure();
        }
    }

    // In case the new copyOp will be eliminated after copyOp sequence optimization, and the user of copyOp is
    // an EltwiseOp with is_inplace, then the inplace buffer for EltwiseOp should be updated.
    auto parentCopyOpInputType = parentCopyOp.getInput().getType().cast<vpux::NDTypeInterface>();
    auto copyOpoutType = copyOp.getOutputBuff().getType().cast<vpux::NDTypeInterface>();
    if (isCMX2CMXCopy(parentCopyOpInputType.getMemoryKind(), copyOpoutType.getMemoryKind()) &&
        parentCopyOpInputType == copyOpoutType && isEltwiseInplaceUser(copyOp)) {
        auto copyOpUser = copyOp->getResult(0).getUsers().begin();
        auto userClusterTaskOp = mlir::dyn_cast<VPUIP::NCEClusterTaskOp>(*copyOpUser);
        VPUX_THROW_UNLESS(userClusterTaskOp != nullptr, "Cannot get the user NCEClusterTaskOp");

        // Found the inplace buffer of nceOp and replace use
        auto nceOutputBuff = VPUIP::getLayerOutputs(userClusterTaskOp)[0];
        auto copyOpOutBuff = VPUIP::getLayerOutputs(copyOp)[0];
        if (nceOutputBuff == copyOpOutBuff) {
            auto parentCopyInputOp = parentCopyOp.getInput().getDefiningOp();
            if (parentCopyInputOp == nullptr) {
                return mlir::failure();
            }
            auto parentCopyOpInputBuff = VPUIP::getLayerOutputs(parentCopyInputOp)[0];
            nceOutputBuff.replaceAllUsesWith(parentCopyOpInputBuff);
        }
    }

    rewriter.replaceOpWithNewOp<VPUIP::CopyOp>(copyOp, parentCopyOp.getInput(), copyOp.getOutputBuff());

    // CopyOp can have MemoryEffect so "hanging" unused parentCopyOp might not be erased by MLIR automatically
    if (parentCopyOp->use_empty()) {
        rewriter.eraseOp(parentCopyOp);
    }

    nestedLogger.trace("Successfully fused sequence of copies into one op");
    return mlir::success();
}

//
// NCEClusterCopyOpSequence
//

class NCEClusterCopyOpSequence final : public mlir::OpRewritePattern<VPUIP::CopyOp> {
public:
    NCEClusterCopyOpSequence(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : mlir::OpRewritePattern<VPUIP::CopyOp>(ctx, benefit), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult NCEClusterCopyOpSequence::matchAndRewrite(VPUIP::CopyOp copyOp,
                                                              mlir::PatternRewriter& rewriter) const {
    // Eliminate copy pairs - spills to DDR
    _log.trace("NCEClusterCopyOpSequence: Copy at {0}", copyOp->getLoc());
    auto nestedLogger = _log.nest();

    auto clusterTiling = copyOp->getParentOfType<VPUIP::NCEClusterTilingOp>();
    if (clusterTiling == nullptr) {
        nestedLogger.trace("Cannot match because copy operation isn't wrapped by NCEClusterTilingOp");
        return mlir::failure();
    }

    auto parentClusterTiling = clusterTiling->getOperand(0).getDefiningOp<VPUIP::NCEClusterTilingOp>();
    if (parentClusterTiling == nullptr) {
        nestedLogger.trace("Cannot match because source producer isn't wrapped by NCEClusterTilingOp");
        return mlir::failure();
    }

    auto parentCopy = parentClusterTiling.getInnerTaskOpOfType<VPUIP::CopyOp>();
    if (parentCopy == nullptr) {
        nestedLogger.trace("Cannot match because predecessor isn't CopyOp");
        return mlir::failure();
    }

    auto isCompatibleDistributedType = [&](mlir::Value input, mlir::Value output) -> bool {
        auto inDistributedType = VPUIP::extractDataType(input).dyn_cast<VPUIP::DistributedBufferType>();
        auto outDistributedType = VPUIP::extractDataType(output).dyn_cast<VPUIP::DistributedBufferType>();
        if (inDistributedType == nullptr || outDistributedType == nullptr) {
            nestedLogger.trace("Cannot match because types aren't distributed");
            return false;
        }

        if (VPU::isDistributedCastCompatible(inDistributedType, outDistributedType).failed()) {
            nestedLogger.trace("Cannot match because of types incompatibility: '{0}' != '{1}'", inDistributedType,
                               outDistributedType);
            return false;
        }

        return true;
    };

    // The I/O types of this CopyOp-chain should be similar
    auto producerInput = parentClusterTiling.getOperand(0);
    auto output = clusterTiling.getResult(0);

    // In case the NCEClusterCopyOp sequence will be eliminated after optimization, and the user of
    // NCEClusterCopyOp is an EltwiseOp with is_inplace, then need to check the distributed type
    // compatible between input Op of NCEClusterCopyOp and EltwiseOp
    //              Input Op 1                     Input Op 2
    //                 |                              |
    //   ClusterTiling_Copy(CMX2DDR)       ClusterTiling_Copy(CMX2DDR)
    //                 |                              |
    //   ClusterTiling_Copy(DDR2CMX)       ClusterTiling_Copy(DDR2CMX)
    //       With inplace buffer
    //                         \             /
    //               ClusterTiling_NCE(EltwiseOp with is_inplace)
    //                                |
    // If distributed type compatible, then convert to:
    //              Input Op 1
    //          With inplace buffer        Input Op 2
    //                         \             /
    //               ClusterTiling_NCE(EltwiseOp with is_inplace)
    //                                |
    // If distributed type incompatible, then convert to:
    //              Input Op 1
    //                 |
    //   ClusterTiling_Copy(CMX2DDR)
    //                 |
    //   ClusterTiling_Copy(DDR2CMX)
    //       With inplace buffer            Input Op 2
    //                         \             /
    //               ClusterTiling_NCE(EltwiseOp with is_inplace)
    //                                |
    if (isEltwiseInplaceUser(copyOp)) {
        auto userClusterTilingOp =
                mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(*clusterTiling.getResult(0).getUsers().begin());
        auto userClusterTaskOp = mlir::dyn_cast<VPUIP::NCEClusterTaskOp>(userClusterTilingOp.getInnerTaskOp());
        VPUX_THROW_UNLESS(userClusterTaskOp != nullptr, "Cannot get the user NCEClusterTaskOp");

        // Found the inplace buffer of nceOp and replace use with compatible input Op buffer of NCEClusterCopyOp
        auto nceOutputBuff = VPUIP::getLayerOutputs(userClusterTilingOp)[0];
        auto tilingCopyOpOutBuff = VPUIP::getLayerOutputs(clusterTiling)[0];
        if (nceOutputBuff == tilingCopyOpOutBuff) {
            auto parentTilingCopyInputOp = mlir::dyn_cast_or_null<VPUIP::NCEClusterTilingOp>(
                    parentClusterTiling.getOperand(0).getDefiningOp());
            if (parentTilingCopyInputOp == nullptr) {
                return mlir::failure();
            }

            if (parentTilingCopyInputOp->getResult(0).getType() != output.getType() &&
                !isCompatibleDistributedType(parentTilingCopyInputOp->getResult(0), output)) {
                nestedLogger.trace(
                        "Do not fuse sequence copy as the user is EltwiseOp with inplace and incompatible type");
                return mlir::failure();
            }

            auto parentCopyOpInputBuff = VPUIP::getLayerOutputs(parentTilingCopyInputOp)[0];
            nceOutputBuff.replaceAllUsesWith(parentCopyOpInputBuff);
        }
    }

    if (producerInput.getType() != output.getType()) {
        if (!isCompatibleDistributedType(producerInput, output)) {
            return mlir::failure();
        }

        rewriter.setInsertionPointAfter(parentClusterTiling);
        rewriter.replaceOpWithNewOp<VPUIP::DistributedCastOp>(clusterTiling, output.getType(), producerInput);

        if (parentClusterTiling->use_empty()) {
            rewriter.eraseOp(parentClusterTiling);
        }
        nestedLogger.trace("Successfully fused sequence of NCEClusterTiled copies into one op");
        return mlir::success();
    }

    rewriter.replaceOp(clusterTiling, producerInput);
    if (parentClusterTiling->use_empty()) {
        rewriter.eraseOp(parentClusterTiling);
    }
    nestedLogger.trace("Successfully fused sequence of NCEClusterTiled copies into one op");
    return mlir::success();
}

//
// CMXToCMXCopy
//

/*  Sparse case is more complex since GroupSparseBufferOp takes place:

        (alloc data)-> GroupOp -> (subview 1)   -> (single grouped buffer)
                    /           \ (subview ...) -> (single grouped buffer)
         (alloc SM)             \ (subview N)   -> (single grouped buffer)

    ClusterTask can write into 2 buffers therefore group ungroup pair of ops is added.
    Then ClusterTask or Tiling op can write into intermediate individual buffers without copy:

        (alloc data)-> GroupOp -> (subview 1)   -> UnGroupOp -> (individual buffers) -> GroupOp
                    /           \ (subview ...) -> UnGroupOp -> (individual buffers) -> GroupOp
         (alloc SM)             \ (subview N)   -> UnGroupOp -> (individual buffers) -> GroupOp
*/
VPUIP::GroupSparseBufferOp createGroupUnGroupPair(vpux::VPUIP::SubViewOp copySubView, mlir::PatternRewriter& rewriter,
                                                  Logger log, VPUIP::DistributedCastOp distributedCast = nullptr) {
    auto ctx = copySubView->getContext();
    auto sparseType = copySubView.getResult().getType().cast<VPUIP::SparseBufferType>();

    VPUX_THROW_WHEN(sparseType.getStorageElementTable() != nullptr,
                    "SparseType for NCE op output has SETable, type {0}", sparseType);

    auto getGroupUngroupPair = [&](mlir::Value ungroupInput) -> VPUIP::GroupSparseBufferOp {
        log.trace("Creating UngroupSparseBufferOp.");
        auto unGroupOp = rewriter.create<VPUIP::UngroupSparseBufferOp>(copySubView.getLoc(), ungroupInput);

        auto dataBuffer = unGroupOp.getData();
        auto sparsityMap = unGroupOp.getSparsityMap();
        auto seTable = unGroupOp.getStorageElementTable();

        log.trace("Creating GroupSparseBufferOp.");
        return rewriter.create<VPUIP::GroupSparseBufferOp>(copySubView.getLoc(), dataBuffer, sparsityMap, seTable,
                                                           sparseType.getIsWeights(), sparseType.getCompressionScheme(),
                                                           sparseType.getSeAttr());
    };

    if (distributedCast == nullptr) {
        return getGroupUngroupPair(copySubView.getResult());
    }

    auto createDistributedCast = [&](mlir::Value distributedCastIn,
                                     VPU::DistributedTensorAttr targetDistribution) -> VPUIP::DistributedCastOp {
        auto sparseBuffType = distributedCastIn.getType().cast<VPUIP::SparseBufferType>();
        auto dataBuffer = sparseBuffType.getData().cast<VPUIP::DistributedBufferType>();
        auto sparsityMap = sparseBuffType.getSparsityMap().cast<VPUIP::DistributedBufferType>();

        auto distribCastData =
                VPUIP::DistributedBufferType::get(ctx, dataBuffer.getShape().raw(), dataBuffer.getElementType(),
                                                  dataBuffer.getLayout(), dataBuffer.getMemSpace(), targetDistribution);
        auto distribCastSparseMap = VPUIP::DistributedBufferType::get(
                ctx, sparsityMap.getShape().raw(), sparsityMap.getElementType(), sparsityMap.getLayout(),
                sparsityMap.getMemSpace(), targetDistribution);

        auto distributedCastType = VPUIP::SparseBufferType::get(
                distribCastData, distribCastSparseMap, sparseBuffType.getStorageElementTable(),
                sparseBuffType.getIsWeights(), sparseBuffType.getCompressionScheme());

        log.trace("Creating DistributedCastOp with input = {0} and output distribution = {1}.", distributedCastIn,
                  targetDistribution);
        return rewriter.create<VPUIP::DistributedCastOp>(copySubView.getLoc(), distributedCastType, distributedCastIn);
    };

    auto nceOpDistribution = distributedCast->getOperand(0)
                                     .getType()
                                     .cast<VPU::DistributedTypeInterface>()
                                     .getDistributedTypes()
                                     .front()
                                     .cast<VPUIP::DistributedBufferType>()
                                     .getDistribution();

    auto distrCastBefore = createDistributedCast(copySubView.getResult(), nceOpDistribution);

    auto groupOp = getGroupUngroupPair(distrCastBefore.getResult());

    auto subviewDistribution = copySubView.getResult()
                                       .getType()
                                       .cast<VPU::DistributedTypeInterface>()
                                       .getDistributedTypes()
                                       .front()
                                       .cast<VPUIP::DistributedBufferType>()
                                       .getDistribution();

    auto newDistrCastAfter = createDistributedCast(groupOp.getResult(), subviewDistribution);

    copySubView.getResult().replaceAllUsesExcept(newDistrCastAfter.getResult(),
                                                 llvm::SmallPtrSet<mlir::Operation*, 1>{distrCastBefore});
    return groupOp;
}

template <class ConcreteType>
ConcreteType getParentOp(mlir::Operation* copyOp) {
    auto parentOp = copyOp->getOperand(0).getDefiningOp<ConcreteType>();
    if (parentOp == nullptr) {
        if (auto parentGroupOp = copyOp->getOperand(0).getDefiningOp<VPUIP::GroupSparseBufferOp>()) {
            return parentGroupOp->getOperand(0).getDefiningOp<ConcreteType>();
        }
    }
    return parentOp;
}

bool isHighDimInputStrideCopy(VPUIP::NCEClusterTilingOp clusterCopyOp) {
    if (!mlir::isa_and_nonnull<VPUIP::SubViewOp>(clusterCopyOp.getOperand(0).getDefiningOp())) {
        return false;
    }
    // Copy cannot be eliminated for nested SubViewOps
    auto isNestedSubviewUser = llvm::any_of(clusterCopyOp->getUsers(), [](mlir::Operation* user) {
        return mlir::isa<VPUIP::SubViewOp>(user);
    });
    if (isNestedSubviewUser) {
        return false;
    }
    auto innerCopyOp = mlir::dyn_cast<VPUIP::CopyOp>(clusterCopyOp.getInnerTaskOp());
    if (innerCopyOp == nullptr) {
        return false;
    }
    auto inputType = clusterCopyOp->getOperand(0).getType().dyn_cast<vpux::NDTypeInterface>();
    auto outputType = clusterCopyOp->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
    const auto inputElemSize = inputType.getElemTypeSize();
    const auto inputShape = inputType.getShape();
    const auto inputLayout = inputType.getDimsOrder();
    const auto outputElemSize = outputType.getElemTypeSize();
    const auto outputShape = outputType.getShape();
    const auto outputLayout = outputType.getDimsOrder();
    if (inputElemSize != outputElemSize || inputShape != outputShape || inputLayout != outputLayout) {
        return false;
    }
    auto inputMemShape = inputType.getMemShape().raw();
    auto inputMemStrides = inputType.getMemStrides().raw();
    auto getStrideDim = [&]() -> Dim {
        for (auto ind : irange(inputMemShape.size()) | reversed) {
            auto dim = Dim(ind);
            if (ind == inputMemShape.size() - 1 && inputMemStrides[ind] != inputElemSize) {
                return dim;
            } else if (ind != inputMemShape.size() - 1) {
                const auto prevMemDim = ind + 1;
                if (inputMemStrides[ind] != inputMemStrides[prevMemDim] * inputMemShape[prevMemDim]) {
                    return dim;
                }
            }
        }
        return Dim(0);
    };
    auto strideDim = getStrideDim();
    return strideDim == Dims4D::Act::N;
}

bool isDistributedInOutCompatible(VPUIP::NCEClusterTilingOp clusterCopyOp) {
    const auto tilingCopyInput = clusterCopyOp->getOperand(0);
    const auto tilingCopyOutput = clusterCopyOp->getResult(0);
    const auto inDistributedType = VPUIP::extractDataType(tilingCopyInput).dyn_cast<VPUIP::DistributedBufferType>();
    const auto outDistributedType = VPUIP::extractDataType(tilingCopyOutput).dyn_cast<VPUIP::DistributedBufferType>();
    if (inDistributedType != outDistributedType) {
        if (inDistributedType == nullptr || outDistributedType == nullptr) {
            return false;
        }

        if (VPU::areDistributionAttrsCompatible(inDistributedType, outDistributedType).failed()) {
            return false;
        }
    }

    return true;
}

bool isExcludedUser(mlir::Operation* op) {
    // For normal case, NCE or groupOp conncet to ConcatView directly
    if (mlir::isa<VPUIP::ConcatViewOp>(op)) {
        return true;
    }

    // For sparse with distributedCast case, NCE or groupOp conncet to distributedCastOp
    if (mlir::isa<VPUIP::DistributedCastOp>(op)) {
        if (op->hasOneUse() && mlir::isa<VPUIP::ConcatViewOp>(*op->getResult(0).getUsers().begin())) {
            return true;
        }
    }
    return false;
}

bool needInsertCopies(mlir::Operation* op) {
    if (op->use_empty()) {
        return false;
    }

    const auto isCopy = [](mlir::Operation* user) {
        auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(user);
        auto tilingCopyOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(user);
        return copyOp != nullptr || (tilingCopyOp != nullptr && tilingCopyOp.getInnerTaskOpOfType<VPUIP::CopyOp>());
    };
    for (auto user : op->getResult(0).getUsers()) {
        if (VPUIP::isPureViewOp(user)) {
            if (isExcludedUser(user)) {
                continue;
            }

            // currently we can only propagate stride through quantizeCast, but could not for other view like. For
            // example: 1x16x32x64 genericReshape to 1x16x16x128(NCHW), if input stride is in H [33280,2080,65,1], don't
            // know how to set output stride. Some special case may work, like input stride in C [34816,2048,64, 1],
            // but haven't been handled.
            if (mlir::isa<VPUIP::QuantizeCastOp>(user)) {
                if (needInsertCopies(user)) {
                    return true;
                }
                continue;
            }

            // Insert copies for other view like operation
            return true;
        }

        if (!isCopy(user)) {
            return true;
        }
    }
    return false;
}

void propagateStrideInfo(mlir::Operation* parent, mlir::PatternRewriter& rewriter) {
    if (parent->use_empty()) {
        return;
    }

    auto origOutType = parent->getResult(0).getType().cast<vpux::NDTypeInterface>();
    const auto inReqs = StrideReqs::compact(origOutType.getRank());
    if (inReqs.checkStrides(origOutType)) {
        return;
    }
    auto parentStrides = getStrides(parent->getResult(0));

    const auto isTilingCopy = [](mlir::Operation* user) {
        auto tilingCopyOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(user);
        return tilingCopyOp != nullptr && tilingCopyOp.getInnerTaskOpOfType<VPUIP::CopyOp>();
    };
    const auto copyOutBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc, mlir::ValueRange newOperands) {
        builder.create<VPUIP::CopyOp>(loc, newOperands[0], newOperands[1]);
    };
    for (auto user : llvm::make_early_inc_range(parent->getResult(0).getUsers())) {
        if (isExcludedUser(user)) {
            continue;
        }

        if (mlir::isa<VPUIP::CopyOp>(user)) {
            continue;
        }

        if (mlir::isa<VPUIP::QuantizeCastOp>(user)) {
            auto origType = user->getResult(0).getType().cast<vpux::NDTypeInterface>();
            auto newType = origType.changeStrides(parentStrides);
            user->getResult(0).setType(newType);
            propagateStrideInfo(user, rewriter);
            continue;
        }

        if (isTilingCopy(user)) {
            // TilingCopy need to re-create to make sure stride info propagated.
            auto tilingCopyOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(user);
            rewriter.setInsertionPointAfter(parent);
            SmallVector<mlir::Value> inputsOutputOperands = {tilingCopyOp->getOperand(0),
                                                             tilingCopyOp.getOutputBuffs()[0]};
            auto newTillingCopy = rewriter.create<VPUIP::NCEClusterTilingOp>(tilingCopyOp->getLoc(),
                                                                             tilingCopyOp->getResult(0).getType(),
                                                                             inputsOutputOperands, copyOutBodyBuilder);
            auto allocOp = tilingCopyOp.getOutputBuffs()[0].getDefiningOp();
            if (newTillingCopy->isBeforeInBlock(allocOp)) {
                newTillingCopy->moveAfter(allocOp);
            }
            rewriter.replaceOp(tilingCopyOp, newTillingCopy->getResult(0));
            continue;
        }

        VPUX_THROW("Unsupported operation type {0} to propagate stride info", user->getName());
    }
}

void insertCopiesAfterNCETask(VPUIP::NCEClusterTaskOp parentNCE, mlir::Type origType, mlir::PatternRewriter& rewriter) {
    auto nceOutType = origType.dyn_cast<vpux::NDTypeInterface>();
    rewriter.setInsertionPointAfter(parentNCE);
    // To DDR
    auto newDDRType = nceOutType.changeMemSpace(VPU::MemoryKind::DDR);
    auto newAllocDDROp = rewriter.create<mlir::memref::AllocOp>(appendLoc(parentNCE->getLoc(), "_new_DDR_buffer"),
                                                                newDDRType.cast<mlir::MemRefType>());
    auto newCopyToDDR = rewriter.create<VPUIP::CopyOp>(appendLoc(parentNCE->getLoc(), "_stride_to_compact"),
                                                       parentNCE->getResult(0), newAllocDDROp);

    // To CMX
    auto newAllocCMXOp = rewriter.create<mlir::memref::AllocOp>(appendLoc(parentNCE->getLoc(), "_new_CMX_buffer"),
                                                                nceOutType.cast<mlir::MemRefType>());
    auto newCopyToCMX = rewriter.create<VPUIP::CopyOp>(parentNCE->getLoc(), newCopyToDDR->getResult(0), newAllocCMXOp);

    parentNCE->getResult(0).replaceUsesWithIf(newCopyToCMX->getResult(0), [&](mlir::OpOperand& opOperand) {
        return opOperand.getOwner() != newCopyToDDR && !isExcludedUser(opOperand.getOwner());
    });
}

void insertCopiesAfterNCETaskDistributedBuffer(VPUIP::NCEClusterTilingOp parentNCEClusterOp, mlir::Type origType,
                                               mlir::PatternRewriter& rewriter) {
    VPUX_THROW_WHEN(!parentNCEClusterOp.getInnerTaskOpOfType<VPUIP::NCEClusterTaskOp>(),
                    "Should be a Tiling NCE task but actually not");

    auto nceOutDistributedType = origType.dyn_cast<VPUIP::DistributedBufferType>();
    auto nceOutType = nceOutDistributedType.getCompactType().dyn_cast<vpux::NDTypeInterface>();
    const auto copyOutBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc, mlir::ValueRange newOperands) {
        builder.create<VPUIP::CopyOp>(loc, newOperands[0], newOperands[1]);
    };
    rewriter.setInsertionPointAfter(parentNCEClusterOp);
    // To DDR
    auto newDDRType = nceOutType.changeMemSpace(VPU::MemoryKind::DDR);
    auto newAllocDDROp = rewriter.create<mlir::memref::AllocOp>(
            appendLoc(parentNCEClusterOp->getLoc(), "_new_DDR_buffer"), newDDRType.cast<mlir::MemRefType>());

    SmallVector<mlir::Value> ddrCopyOperands = {parentNCEClusterOp->getResult(0),
                                                static_cast<mlir::Value>(newAllocDDROp)};
    auto newTillingCopyToDDR =
            rewriter.create<VPUIP::NCEClusterTilingOp>(appendLoc(parentNCEClusterOp->getLoc(), "_stride_to_compact"),
                                                       newDDRType, ddrCopyOperands, copyOutBodyBuilder);
    // To CMX
    auto newDistributeBuff = rewriter.create<VPURT::AllocDistributed>(
            appendLoc(parentNCEClusterOp->getLoc(), "_new_CMX_buffer"), nceOutDistributedType, nullptr, nullptr);
    SmallVector<mlir::Value> cmxCopyOperands = {newTillingCopyToDDR->getResult(0),
                                                static_cast<mlir::Value>(newDistributeBuff)};
    auto newTillingCopyToCMX = rewriter.create<VPUIP::NCEClusterTilingOp>(
            parentNCEClusterOp->getLoc(), nceOutDistributedType, cmxCopyOperands, copyOutBodyBuilder);

    parentNCEClusterOp->getResult(0).replaceUsesWithIf(
            newTillingCopyToCMX->getResult(0), [&](mlir::OpOperand& opOperand) {
                return opOperand.getOwner() != newTillingCopyToDDR && !isExcludedUser(opOperand.getOwner());
            });
}

void insertCopiesAfterGroupSparsityDistributedBuffer(VPUIP::GroupSparseBufferOp sparseBufferOp, mlir::Type origType,
                                                     mlir::PatternRewriter& rewriter) {
    auto sparseType = origType.cast<VPUIP::SparseBufferType>();

    auto dataBufferType = sparseType.getData().cast<VPUIP::DistributedBufferType>();
    auto sparsityMapType = sparseType.getSparsityMap().cast<VPUIP::DistributedBufferType>();
    auto dataBufferCompactType = dataBufferType.getCompactType().dyn_cast<vpux::NDTypeInterface>();
    auto sparsityMapCompactType = sparsityMapType.getCompactType().dyn_cast<vpux::NDTypeInterface>();

    rewriter.setInsertionPointAfter(sparseBufferOp);

    // To DDR
    auto newDDRDataBufferCompactType = dataBufferCompactType.changeMemSpace(VPU::MemoryKind::DDR);
    auto newDDRSparsityMapCompactType = sparsityMapCompactType.changeMemSpace(VPU::MemoryKind::DDR);

    auto newDDRDataBufferOp =
            rewriter.create<mlir::memref::AllocOp>(appendLoc(sparseBufferOp->getLoc(), "_new_data_DDR_buffer"),
                                                   newDDRDataBufferCompactType.cast<mlir::MemRefType>());
    auto newDDRSparsityMapOp =
            rewriter.create<mlir::memref::AllocOp>(appendLoc(sparseBufferOp->getLoc(), "_new_sparsity_DDR_buffer"),
                                                   newDDRSparsityMapCompactType.cast<mlir::MemRefType>());
    auto groupSparseBufferDDROp = rewriter.create<VPUIP::GroupSparseBufferOp>(
            sparseBufferOp.getLoc(), newDDRDataBufferOp, newDDRSparsityMapOp, nullptr, sparseType.getIsWeights(),
            sparseType.getCompressionScheme(), sparseType.getSeAttr());
    const auto copyOutBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc, mlir::ValueRange newOperands) {
        builder.create<VPUIP::CopyOp>(loc, newOperands[0], newOperands[1]);
    };

    SmallVector<mlir::Value> ddrCopyOperands = {sparseBufferOp->getResult(0),
                                                static_cast<mlir::Value>(groupSparseBufferDDROp->getResult(0))};
    auto newTillingCopyToDDR = rewriter.create<VPUIP::NCEClusterTilingOp>(
            appendLoc(sparseBufferOp->getLoc(), "_stride_to_compact"), groupSparseBufferDDROp->getResult(0).getType(),
            ddrCopyOperands, copyOutBodyBuilder);

    // To CMX
    auto newCMXDataBufferOp = rewriter.create<VPURT::AllocDistributed>(
            appendLoc(sparseBufferOp->getLoc(), "_new_data_CMX_buffer"), dataBufferType, nullptr, nullptr);
    auto newCMXSparsityMapOp = rewriter.create<VPURT::AllocDistributed>(
            appendLoc(sparseBufferOp->getLoc(), "_new_sparsity_CMX_buffer"), sparsityMapType, nullptr, nullptr);

    auto groupSparseBufferCMXOp = rewriter.create<VPUIP::GroupSparseBufferOp>(
            sparseBufferOp.getLoc(), newCMXDataBufferOp, newCMXSparsityMapOp, nullptr, sparseType.getIsWeights(),
            sparseType.getCompressionScheme(), sparseType.getSeAttr());
    SmallVector<mlir::Value> cmxCopyOperands = {newTillingCopyToDDR->getResult(0),
                                                static_cast<mlir::Value>(groupSparseBufferCMXOp->getResult(0))};
    auto newTillingCopyToCMX = rewriter.create<VPUIP::NCEClusterTilingOp>(
            appendLoc(sparseBufferOp->getLoc(), "_stride_to_compact"), groupSparseBufferCMXOp->getResult(0).getType(),
            cmxCopyOperands, copyOutBodyBuilder);

    sparseBufferOp->getResult(0).replaceUsesWithIf(newTillingCopyToCMX->getResult(0), [&](mlir::OpOperand& opOperand) {
        return opOperand.getOwner() != newTillingCopyToDDR && !isExcludedUser(opOperand.getOwner());
    });
}

void insertCopiesAfterGroupSparsity(VPUIP::GroupSparseBufferOp sparseBufferOp, mlir::Type origType,
                                    mlir::PatternRewriter& rewriter) {
    auto sparseType = origType.cast<VPUIP::SparseBufferType>();
    auto dataBufferCompactType = sparseType.getData().dyn_cast<vpux::NDTypeInterface>();
    auto sparsityMapCompactType = sparseType.getSparsityMap().dyn_cast<vpux::NDTypeInterface>();

    rewriter.setInsertionPointAfter(sparseBufferOp);

    // To DDR
    auto newDDRDataBufferCompactType = dataBufferCompactType.changeMemSpace(VPU::MemoryKind::DDR);
    auto newDDRSparsityMapCompactType = sparsityMapCompactType.changeMemSpace(VPU::MemoryKind::DDR);

    auto newDDRDataBufferOp =
            rewriter.create<mlir::memref::AllocOp>(appendLoc(sparseBufferOp->getLoc(), "_new_data_DDR_buffer"),
                                                   newDDRDataBufferCompactType.cast<mlir::MemRefType>());
    auto newDDRSparsityMapOp =
            rewriter.create<mlir::memref::AllocOp>(appendLoc(sparseBufferOp->getLoc(), "_new_sparsity_DDR_buffer"),
                                                   newDDRSparsityMapCompactType.cast<mlir::MemRefType>());

    auto groupSparseBufferDDROp = rewriter.create<VPUIP::GroupSparseBufferOp>(
            sparseBufferOp.getLoc(), newDDRDataBufferOp, newDDRSparsityMapOp, nullptr, sparseType.getIsWeights(),
            sparseType.getCompressionScheme(), sparseType.getSeAttr());

    auto newCopyToDDR = rewriter.create<VPUIP::CopyOp>(appendLoc(sparseBufferOp->getLoc(), "_stride_to_compact"),
                                                       sparseBufferOp->getResult(0), groupSparseBufferDDROp);

    // To CMX
    auto newCMXDataBufferOp = rewriter.create<mlir::memref::AllocOp>(
            appendLoc(sparseBufferOp->getLoc(), "_new_CMX_buffer"), dataBufferCompactType.cast<mlir::MemRefType>());
    auto newCMXSparsityMapOp = rewriter.create<mlir::memref::AllocOp>(
            appendLoc(sparseBufferOp->getLoc(), "_new_CMX_buffer"), sparsityMapCompactType.cast<mlir::MemRefType>());

    auto groupSparseBufferCMXOp = rewriter.create<VPUIP::GroupSparseBufferOp>(
            sparseBufferOp.getLoc(), newCMXDataBufferOp, newCMXSparsityMapOp, nullptr, sparseType.getIsWeights(),
            sparseType.getCompressionScheme(), sparseType.getSeAttr());

    auto newCopyToCMX = rewriter.create<VPUIP::CopyOp>(appendLoc(sparseBufferOp->getLoc(), "_stride_to_compact"),
                                                       newCopyToDDR, groupSparseBufferCMXOp);

    sparseBufferOp->getResult(0).replaceUsesWithIf(newCopyToCMX->getResult(0), [&](mlir::OpOperand& opOperand) {
        return opOperand.getOwner() != newCopyToDDR && !isExcludedUser(opOperand.getOwner());
    });
}

void handleStrideForOtherUsers(mlir::Operation* parent, mlir::Type origType, mlir::PatternRewriter& rewriter,
                               Logger log) {
    if (needInsertCopies(parent)) {
        if (auto nceTask = mlir::dyn_cast<VPUIP::NCEClusterTaskOp>(parent)) {
            insertCopiesAfterNCETask(nceTask, origType, rewriter);
        } else if (auto clustringNceTask = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(parent)) {
            insertCopiesAfterNCETaskDistributedBuffer(clustringNceTask, origType, rewriter);
        } else if (auto groupSparsity = mlir::dyn_cast<VPUIP::GroupSparseBufferOp>(parent)) {
            auto sparseType = groupSparsity->getResult(0).getType().dyn_cast<VPUIP::SparseBufferType>();
            if (sparseType.containsDistributedTypes()) {
                insertCopiesAfterGroupSparsityDistributedBuffer(groupSparsity, origType, rewriter);
            } else {
                insertCopiesAfterGroupSparsity(groupSparsity, origType, rewriter);
            }
        } else {
            VPUX_THROW("Incorrect parent type {0}", parent->getName());
        }
        log.trace("Insert a pair of copy to handle stride");
    } else {
        propagateStrideInfo(parent, rewriter);
        log.trace("Propagate stride info to child");
    }
}

mlir::LogicalResult removeClusterTilingCMXToCMXCopy(VPUIP::NCEClusterTilingOp copyClusterOp,
                                                    mlir::PatternRewriter& rewriter, Logger log) {
    log.trace("removeClusterTilingCMXToCMXCopy: Copy at {0}", copyClusterOp->getLoc());
    auto nestedLogger = log.nest();

    auto innerCopyOp = mlir::dyn_cast<VPUIP::CopyOp>(copyClusterOp.getInnerTaskOp());
    if (innerCopyOp == nullptr) {
        nestedLogger.trace("Cannot match because tiling op does not contain Copy");
        return mlir::failure();
    }

    auto inputType = copyClusterOp->getOperand(0).getType().dyn_cast<vpux::NDTypeInterface>();
    auto outputType = copyClusterOp->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
    // Only remove redundant CMX2CMX CopyOps
    if (!isCMX2CMXCopy(inputType.getMemoryKind(), outputType.getMemoryKind())) {
        nestedLogger.trace("Cannot match because the transfer is not CMX->CMX");
        return mlir::failure();
    }

    auto distributedCast = getParentOp<VPUIP::DistributedCastOp>(copyClusterOp);

    // CMX Concat case with subView, update the buffers used
    if (auto copySubView = copyClusterOp.getOutputBuffs()[0].getDefiningOp<VPUIP::SubViewOp>()) {
        // case with subView - retrieve operations to be re-linked
        auto masterBuffer = VPUIP::getRootAlloc<VPURT::AllocDistributed>(copySubView.getSource());
        if (masterBuffer == nullptr) {
            nestedLogger.trace("Cannot match because source isn't master buffer");
            return mlir::failure();
        }

        auto parentNCEClusterOp = distributedCast == nullptr ? getParentOp<VPUIP::NCEClusterTilingOp>(copyClusterOp)
                                                             : getParentOp<VPUIP::NCEClusterTilingOp>(distributedCast);
        if (parentNCEClusterOp == nullptr) {
            nestedLogger.trace("Cannot match because copy is not a successor of NCEClusterTiling or of a "
                               "NCEClusterTiling -> VPUIP.DistributedCast sequence");
            return mlir::failure();
        }

        if (parentNCEClusterOp.getOutputBuffs()[0].getDefiningOp<VPUIP::SubViewOp>()) {
            nestedLogger.trace("NCE output is already the subview of Concat");
            return mlir::failure();
        }

        mlir::Operation* parentOp = parentNCEClusterOp;
        auto origType = parentNCEClusterOp->getResult(0).getType();
        const auto updateParentNCEOp = [&](size_t argIdx, mlir::Value value,
                                           VPUIP::GroupSparseBufferOp newGroupOp = nullptr) {
            // Update result types of NCEClusterTiling
            parentNCEClusterOp->getResult(checked_cast<unsigned int>(argIdx)).setType(value.getType());
            // Update output buffers of NCEClusterTiling
            parentNCEClusterOp.getOutputBuffs()[argIdx].replaceAllUsesWith(value);
            // Update inner NCEClusterTask
            const auto newInnerType = value.getType().dyn_cast<VPUIP::DistributedBufferType>().getCompactType();
            // Update block arguments
            size_t totalArgNum = 1;
            if (newGroupOp != nullptr) {
                totalArgNum = newGroupOp->getNumOperands();
            }
            // Output operands are placed in the end
            parentNCEClusterOp.getBody()
                    .getArgument(
                            checked_cast<unsigned int>(parentNCEClusterOp.getNumOperands() - (totalArgNum) + argIdx))
                    .setType(newInnerType);
            // Update result types
            parentNCEClusterOp.getInnerTaskOp()->getResult(checked_cast<unsigned int>(argIdx)).setType(newInnerType);
            // Update new group op to use results of parentNCEClusterOp
            if (newGroupOp != nullptr) {
                newGroupOp->setOperand(checked_cast<unsigned int>(argIdx), parentNCEClusterOp.getResults()[argIdx]);
            }
        };

        copySubView->moveBefore(parentNCEClusterOp);

        if (auto subviewParentGroupOp = mlir::dyn_cast<VPUIP::GroupSparseBufferOp>(masterBuffer)) {
            rewriter.setInsertionPoint(parentNCEClusterOp);
            auto newGroupOp = createGroupUnGroupPair(copySubView, rewriter, nestedLogger, distributedCast);
            if (newGroupOp == nullptr) {
                return mlir::failure();
            }

            auto newBuffers = SmallVector<mlir::Value>({newGroupOp.getData(), newGroupOp.getSparsityMap()});

            // Go through individual buffers and update corresponding operands.
            // First run is data and second run is sparsity map.
            for (auto newBuffer : newBuffers | indexed) {
                updateParentNCEOp(newBuffer.index(), newBuffer.value(), newGroupOp);
            }

            auto copyOpReplacement = newGroupOp.getOperation();
            if (distributedCast != nullptr) {
                auto newDistributedCast = *(newGroupOp.getResult().getUsers().begin());

                // Parent Group Op will be moved after NCEClusterOp, therefore DistributedCast should be moved as well
                newDistributedCast->moveAfter(parentNCEClusterOp);
                copyOpReplacement = newDistributedCast;
                auto oldGroup = distributedCast->getOperand(0).getDefiningOp<VPUIP::GroupSparseBufferOp>();
                VPUX_THROW_WHEN(oldGroup == nullptr, "Should be groupSparseBufferOp, but not");
                oldGroup->replaceAllUsesWith(newGroupOp);
                origType = oldGroup->getResult(0).getType();
            } else {
                auto oldGroup = copyClusterOp->getOperand(0).getDefiningOp<VPUIP::GroupSparseBufferOp>();
                VPUX_THROW_WHEN(oldGroup == nullptr, "Should be groupSparseBufferOp, but not");
                oldGroup->replaceAllUsesWith(newGroupOp);
                origType = oldGroup->getResult(0).getType();
            }
            parentOp = newGroupOp;

            // Replace all uses of copy op with GroupOp
            newGroupOp->moveAfter(parentNCEClusterOp);
            copyClusterOp->replaceAllUsesWith(copyOpReplacement);
        } else {
            // replace the copy with the subView
            auto nceClusterOutput = copySubView.getResult();
            if (distributedCast != nullptr) {
                rewriter.setInsertionPointAfter(copySubView);
                auto ndTypeIfValue = copySubView.getType().cast<NDTypeInterface>();
                auto distributedCastType =
                        distributedCast->getOperand(0).getType().cast<NDTypeInterface>().changeStrides(
                                ndTypeIfValue.getStrides());

                nestedLogger.trace("Creating DistributedCastOp with input = {0} and output type = {1}.", copySubView,
                                   distributedCastType);

                auto newDistrCast = rewriter.create<VPUIP::DistributedCastOp>(parentNCEClusterOp->getLoc(),
                                                                              distributedCastType, copySubView);
                nceClusterOutput = newDistrCast.getResult();
            }

            updateParentNCEOp(0 /*result index*/, nceClusterOutput);
            copyClusterOp->replaceAllUsesWith(parentNCEClusterOp);
        }

        // update IR location of the master buffer
        if (copySubView->isBeforeInBlock(masterBuffer)) {
            VPUIP::moveRootAllocBefore(masterBuffer, copySubView);
        }

        rewriter.eraseOp(copyClusterOp);
        if (distributedCast != nullptr) {
            rewriter.eraseOp(distributedCast);
        }

        // now we need to propagate stride info to other users
        handleStrideForOtherUsers(parentOp, origType, rewriter, log);
    } else if (inputType == outputType ||
               (isHighDimInputStrideCopy(copyClusterOp) && isDistributedInOutCompatible(copyClusterOp))) {
        // case with no subView   Or
        // case with input subView
        // if the subView splits on the highest dimension
        // eliminate the CMX2CMX copy
        copyClusterOp->replaceAllUsesWith(copyClusterOp.getOperand(0).getDefiningOp());
        rewriter.eraseOp(copyClusterOp);
        if (distributedCast != nullptr) {
            rewriter.eraseOp(distributedCast);
        }
    } else {
        log.trace("Copy not optimized {0}", copyClusterOp->getLoc());
        return mlir::failure();
    }

    nestedLogger.trace("Successfully removed sequence");
    return mlir::success();
}

mlir::LogicalResult removeCMXToCMXCopy(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter, Logger log) {
    // Check current CopyOp source and destination
    log.trace("removeCMXToCMXCopy: Copy at {0}", copyOp->getLoc());
    auto nestedLogger = log.nest();

    auto inputType = copyOp.getInput().getType().cast<vpux::NDTypeInterface>();
    auto outputType = copyOp.getOutput().getType().cast<vpux::NDTypeInterface>();

    // Only remove redundant CMX2CMX CopyOps
    if (!isCMX2CMXCopy(inputType.getMemoryKind(), outputType.getMemoryKind())) {
        nestedLogger.trace("Cannot match because the transfer is not CMX->CMX");
        return mlir::failure();
    }
    // CMX Concat case with SubView, update the buffers used
    if (auto copySubView = mlir::dyn_cast<VPUIP::SubViewOp>(copyOp.getOutputBuff().getDefiningOp())) {
        // case with SubView - retrieve operations to be re-linked
        auto parentNCE = getParentOp<VPUIP::NCEClusterTaskOp>(copyOp);

        if (parentNCE == nullptr) {
            nestedLogger.trace("Cannot match because copy operation is not a successor of NCEClusterTask");
            return mlir::failure();
        }

        auto masterBuffer = VPUIP::getRootAlloc<mlir::memref::AllocOp>(copySubView->getOperand(0));
        if (masterBuffer == nullptr) {
            nestedLogger.trace("Cannot match because source isn't master buffer");
            return mlir::failure();
        }

        mlir::Operation* parentOp = parentNCE;
        auto origType = parentNCE->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
        VPUIP::moveRootAllocBefore(copySubView, parentNCE);
        if (auto subviewParentGroupOp = mlir::dyn_cast<VPUIP::GroupSparseBufferOp>(masterBuffer)) {
            rewriter.setInsertionPoint(parentNCE);
            auto newGroupOp = createGroupUnGroupPair(copySubView, rewriter, nestedLogger);
            if (newGroupOp == nullptr) {
                return mlir::failure();
            }
            // Go through individual buffers and update corresponding operands
            parentNCE->getResult(0).setType(newGroupOp.getData().getType());
            parentNCE->getResult(1).setType(newGroupOp.getSparsityMap().getType());
            // Update NCEClusterTask output buffers
            parentNCE.getOutputBuff().replaceAllUsesWith(newGroupOp.getData());
            parentNCE.getOutputSparsityMapBuff().replaceAllUsesWith(newGroupOp.getSparsityMap());
            // Update GroupOp to use results of NCEClusterTask, but not new UngroupOp
            newGroupOp->setOperand(0, parentNCE.getOutput());
            newGroupOp->setOperand(1, parentNCE.getOutputSparsityMap());
            // Replace all uses of copy op with new GroupOp
            newGroupOp->moveAfter(parentNCE);

            auto oldGroup = copyOp->getOperand(0).getDefiningOp<VPUIP::GroupSparseBufferOp>();
            VPUX_THROW_WHEN(oldGroup == nullptr, "Should be groupSparseBufferOp, but not");
            oldGroup->replaceAllUsesWith(newGroupOp);
            origType = oldGroup->getResult(0).getType();
            parentOp = newGroupOp;
            copyOp->replaceAllUsesWith(newGroupOp);
        } else {
            // replace the copy with the subView
            parentNCE->getResult(0).setType(copySubView->getResult(0).getType());
            parentNCE.getOutputBuff().replaceAllUsesWith(copySubView->getResult(0));
            copyOp.getOutput().replaceAllUsesWith(copyOp.getInput());
        }
        // update IR location of the master buffer
        if (copySubView->isBeforeInBlock(masterBuffer)) {
            VPUIP::moveRootAllocBefore(masterBuffer, copySubView);
        }

        rewriter.eraseOp(copyOp);

        // now we need to propagate stride info to other users
        handleStrideForOtherUsers(parentOp, origType, rewriter, log);
    } else if (inputType == outputType) {
        // case with no subView
        copyOp.getOutput().replaceAllUsesWith(copyOp.getInput());
        rewriter.eraseOp(copyOp);
    } else {
        log.trace("Copy not optimized {0}", copyOp->getLoc());
        return mlir::failure();
    }

    nestedLogger.trace("Successfully removed sequence");
    return mlir::success();
}

class CMXToCMXCopy final : public mlir::OpRewritePattern<VPUIP::CopyOp> {
public:
    CMXToCMXCopy(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : mlir::OpRewritePattern<VPUIP::CopyOp>(ctx, benefit), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult CMXToCMXCopy::matchAndRewrite(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter) const {
    /*
     Remove CMX2CMX Copy without SubView:
         Copy(DDR2CMX)                    Copy(DDR2CMX)
              |                                |
            NCEOp           =>               NCEOp
              |
         Copy(CMX2CMX)

     Remove CMX2CMX Copy with SubView:
        Copy(DDR2CMX)                Copy(DDR2CMX)  SubView
              |                                \     /
            NCEOp       SubView   =>            NCEOp
               \         /
              Copy(CMX2CMX)

     For Cluster-ed scenario, it is possible to have:
        Copy(DDR2CMX)                Copy(DDR2CMX)  SubView
              |                            |           |
            NCEOp        =>                |    (DistributedCast)
              |                            \        / (output_buff)
    (DistributedCast)  SubView                NCEOp
               \         / (output_buff)
              Copy(CMX2CMX)

    For Cluster-ed scenario with Sparse type, final subgraph should be:
               Alloc Data    Alloc SparsityMap
                      \                /
                        GroupSparseOp
                             |
                          SubView -------> (if original SubView output had multiple
                             |              consumers, this is their new producer)
                      (DistributedCast)
                             |
                          Ungroup
        (output_data_buff) |  | (output_sparsity_map_buff)
                           NCEOp


     */
    if (auto clusterTilingCopy = copyOp->getParentOfType<VPUIP::NCEClusterTilingOp>()) {
        return removeClusterTilingCMXToCMXCopy(clusterTilingCopy, rewriter, _log);
    } else {
        return removeCMXToCMXCopy(copyOp, rewriter, _log);
    }
}

//
// DDRToDDRCopyOfNCECluster
//

class DDRToDDRCopyOfNCECluster final : public mlir::OpRewritePattern<VPUIP::CopyOp> {
public:
    DDRToDDRCopyOfNCECluster(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : mlir::OpRewritePattern<VPUIP::CopyOp>(ctx, benefit), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

bool isDDR2DDROfNCEClusterInput(VPUIP::CopyOp copyOp) {
    // ChildOp should be a copy op wrapped in ClusterTilingOp
    if (copyOp.getOutput().getUsers().empty()) {
        return false;
    }

    auto isClusterTilingCopyOp = [](mlir::Operation* user) {
        if (auto tilingOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(user)) {
            return tilingOp.getInnerTaskOpOfType<VPUIP::CopyOp>() != nullptr;
        }
        return false;
    };

    auto isLegalUpdateViewLikeInType = [](mlir::Operation* op, mlir::Value newInput) {
        const auto origInput = op->getOperands()[0];
        op->getOpOperand(0).set(newInput);
        auto iface = mlir::dyn_cast<mlir::InferTypeOpInterface>(*op);
        SmallVector<mlir::Type> newTypes;
        const auto isLegal =
                iface.inferReturnTypes(op->getContext(), op->getLoc(), op->getOperands(), op->getAttrDictionary(),
                                       op->getPropertiesStorage(), op->getRegions(), newTypes)
                        .succeeded();
        op->getOpOperand(0).set(origInput);
        return isLegal;
    };

    for (auto copyOpUser : copyOp.getOutput().getUsers()) {
        // TODO: Extend for other ViewLike ops E#74293
        if (mlir::isa<VPUIP::ShapeCastOp>(copyOpUser) && mlir::isa<mlir::InferTypeOpInterface>(copyOpUser)) {
            if (!isLegalUpdateViewLikeInType(copyOpUser, copyOp.getInput())) {
                return false;
            }
            for (auto pureViewOpUser : copyOpUser->getResult(0).getUsers()) {
                if (!isClusterTilingCopyOp(pureViewOpUser)) {
                    return false;
                }
            }
        } else if (!isClusterTilingCopyOp(copyOpUser)) {
            return false;
        }
    }

    return true;
}

bool hasValidParallelCopyBranchWithSubView(VPUIP::CopyOp copyOp, VPUIP::NCEClusterTilingOp parentOp) {
    if (parentOp->hasOneUse()) {
        return false;
    }

    auto subview = copyOp.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>();
    if (subview == nullptr) {
        return false;
    }

    // If a CMX to DDR copy's input is a subview of SOH's output, the CMX2DDR copy's input tensor will have a SEGMENTED
    // or OVERLAPPED distribution. But the output data of the tensor's subview may be distributed on one cluster or
    // multiple clusters.In the current compiler logic, when calculating DMA cost and unroll DMA, it is assumed that the
    // data of the Tensor with SEGMENTED or OVERLAPPED distribution is distributed on multiple clusters. Therefore, SOH
    // optimization is temporarily turned off and turned on after subsequent compiler support.E60342
    if (auto distType = VPUIP::extractDataType(parentOp.getInputs()[0]).dyn_cast<VPUIP::DistributedBufferType>()) {
        if (distType.getDistribution().getMode().getValue() == VPU::DistributionMode::SEGMENTED ||
            distType.getDistribution().getMode().getValue() == VPU::DistributionMode::OVERLAPPED) {
            auto subviewshape = subview.getResult().getType().cast<vpux::NDTypeInterface>().getShape().raw();
            auto numTiles = parseIntArrayAttr<int64_t>(distType.getDistribution().getNumTiles());
            if (subviewshape.size() == 4 && subviewshape[Dims4D::Act::H.ind()] % numTiles[Dims4D::Act::H.ind()] != 0) {
                return false;
            }

            // In case of the CMX2DDR copy's input tensor has a SEGMENTED or OVERLAPPED distribution and the tile Axis
            // is H, and if the output data of the tensor's subview has tile offsets including H, then the tile result
            // may be incorrect after SOH optimization (When the offset is a non first cluster / the offset is only
            // used in a single cluster or a few clusters / the offset exists across two consecutive clusters), as
            // current compiler logic not support this case in calculating DMA cost and unroll DMA
            // TODO: Add optimization for this case, #E80157
            for (auto user : llvm::make_early_inc_range(parentOp.getResult(0).getUsers())) {
                if (auto subview = mlir::dyn_cast<VPUIP::SubViewOp>(*user)) {
                    auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(*subview.getResult().getUsers().begin());
                    auto offsetAttr = subview.getStaticOffsetsAttr();
                    const auto offsetsArray = parseIntArrayAttr<int64_t>(offsetAttr);
                    const auto tilingScheme = parseIntArrayAttr<int64_t>(distType.getDistribution().getNumTiles());
                    const auto tileAxis = vpux::VPU::getDistributedTilingAxis(tilingScheme);
                    if (copyOp && offsetsArray[tileAxis]) {
                        return false;
                    }
                }
            }
        }
    }

    // check other parallel branch if it's a valid copy branch or not
    for (auto siblingOp : parentOp.getResults().getUsers()) {
        // Considering padding/slice case: Tiling_copy -> subview -> copy
        if (auto siblingSubview = mlir::dyn_cast<VPUIP::SubViewOp>(*siblingOp)) {
            if (siblingSubview.getResult().hasOneUse()) {
                auto childOp = siblingSubview.getResult().getUsers().begin();
                if (auto childCopy = mlir::dyn_cast<VPUIP::CopyOp>(*childOp)) {
                    // Case is okay : pass
                    if (!childCopy.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>()) {
                        return false;
                    }
                }
            } else {
                return false;
            }
        } else if (auto siblingCopy = mlir::dyn_cast<VPUIP::CopyOp>(*siblingOp)) {
            if (siblingCopy != copyOp) {
                if (!siblingCopy.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>()) {
                    return false;
                }
            }
        } else {
            return false;
        }
    }
    // check all branches and okay
    return true;
}

// For the case: parent of copyOp only have one output branch
// Parallel case should be processed by isParallelDDR2DDROfNCEClusterOutput()
// for clear logic
bool isDDR2DDROfNCEClusterOutput(VPUIP::CopyOp copyOp) {
    // ParentOp should be a copy op wrapped in ClusterTilingOp
    // ChildOp should be a concat
    auto parentOp = copyOp->getOperand(0).getDefiningOp<VPUIP::NCEClusterTilingOp>();
    if (parentOp == nullptr || parentOp.getInnerTaskOpOfType<VPUIP::CopyOp>() == nullptr) {
        return false;
    }
    if (copyOp.getOutput().getUsers().empty()) {
        return false;
    }
    for (auto user : copyOp.getOutput().getUsers()) {
        if (!mlir::isa<VPUIP::ConcatViewOp>(*user)) {
            return false;
        }
    }

    return parentOp->hasOneUse();
}

bool isParallelDDR2DDROfNCEClusterOutput(VPUIP::CopyOp copyOp) {
    // ParentOp should be a copy op wrapped in ClusterTilingOp
    // ChildOp should be a concat
    auto parentOp = copyOp->getOperand(0).getDefiningOp<VPUIP::NCEClusterTilingOp>();
    if (parentOp == nullptr || parentOp.getInnerTaskOpOfType<VPUIP::CopyOp>() == nullptr) {
        return false;
    }

    if (copyOp.getOutput().getUsers().empty()) {
        return false;
    }
    for (auto user : copyOp.getOutput().getUsers()) {
        if (!mlir::isa<VPUIP::ConcatViewOp>(*user)) {
            return false;
        }
    }

    /*
     Optimize the parallel DDR2DDR copies as CMX2DDR copies:
                 ClusterTiling_Copy(CMX2DDR)
                      /        \
            Copy(DDR2DDR)   (SubViews ->) Copy(DDR2DDR)
            /        \                 /       \
        SubView              |               SubView
                             |
                          Concat
    */
    return hasValidParallelCopyBranchWithSubView(copyOp, parentOp);
}

bool isStridedCopy(VPUIP::CopyOp copyOp) {
    // Here we check two options at the same time:
    // 1. Copy op is not strided, in the sense that step for copying dimension is 1
    // 2. Copy can handle full plane without offsets

    const auto outType = copyOp.getOutputBuff().getType().cast<vpux::NDTypeInterface>();
    const auto order = outType.getDimsOrder();
    const auto memStrides = StrideReqs::compact(order.numDims()).calcStrides(order, outType);
    auto compactStrides = order.toLogicalOrder(memStrides);

    auto actStrides = outType.getStrides();
    VPUX_THROW_UNLESS(compactStrides.size() == actStrides.size(),
                      "Compact ({0}) and actual ({1}) strides size mismatch", compactStrides.size(), actStrides.size());

    for (size_t i = 1; i < compactStrides.size(); i++) {
        if (compactStrides[Dim(i)] != actStrides[Dim(i)]) {
            return true;
        }
    }

    return false;
}

bool isDDR2DDROfConcatInput(VPUIP::CopyOp copyOp) {
    // ParentOp should be a concatView op
    // ChildOp should be a concatView too
    auto parentConcatOp = copyOp.getInput().getDefiningOp<VPUIP::ConcatViewOp>();
    if (parentConcatOp == nullptr) {
        return false;
    }
    if (!copyOp.getOutput().hasOneUse()) {
        return false;
    }

    auto childConcatOp = mlir::dyn_cast<VPUIP::ConcatViewOp>(*copyOp.getOutput().getUsers().begin());
    if (childConcatOp == nullptr) {
        return false;
    }

    // Exclude strided dma case
    size_t constCopyCnt = 0;
    auto predicteChildConcatInput = [&](mlir::Value op) {
        auto copy = op.getDefiningOp<VPUIP::CopyOp>();
        if (copy == nullptr || isStridedCopy(copy)) {
            return false;
        }

        auto concat = copy.getInput().getDefiningOp<VPUIP::ConcatViewOp>();
        if (concat == nullptr) {
            auto subView = copy.getInput().getDefiningOp<VPUIP::SubViewOp>();
            if (subView == nullptr) {
                auto parentCopyInputConst = VPUIP::getRootConst(copy.getInput());
                if (parentCopyInputConst) {
                    constCopyCnt++;
                    return true;
                }
                return false;
            } else if (!subView.getResult().hasOneUse()) {
                return false;
            }
            concat = subView.getSource().getDefiningOp<VPUIP::ConcatViewOp>();
        }

        return concat == parentConcatOp;
    };

    /*
     E.g., Optimize the left DDR2DDR copy in below case:
     case 1:
                      ConcatView
                      /         \
             Copy(DDR2DDR)      SubView
                     \            \
                      \        Copy(DDR2DDR)
                       \        /
                           |
                           |
                       ConcatView
    case 2:
                ConcatView
                    |
             Copy(DDR2DDR)      const.Declare
                     \            |
                      \        Copy(DDR2DDR)
                       \        /
                           |
                           |
                       ConcatView
    */
    if (!llvm::all_of(childConcatOp.getInputs(), predicteChildConcatInput)) {
        return false;
    }

    const auto childConcatInputsNum = childConcatOp.getInputs().size();

    const auto parentConcatUsers = parentConcatOp.getOutput().getUsers();
    const auto parentConcatUsersNum = std::distance(parentConcatUsers.begin(), parentConcatUsers.end());

    return (childConcatInputsNum - constCopyCnt) == static_cast<size_t>(parentConcatUsersNum);
}

mlir::LogicalResult removeDDR2DDRForNCEClusterInput(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter, Logger log) {
    copyOp.getOutput().replaceAllUsesWith(copyOp.getInput());

    // Update ViewLike Op Output Type
    SmallVector<mlir::Operation*> viewLikeOps;
    for (auto copyOpUser : copyOp.getInput().getUsers()) {
        if (mlir::isa<VPUIP::ShapeCastOp>(copyOpUser)) {
            viewLikeOps.push_back(copyOpUser);
        }
    }

    for (auto viewLikeOp : viewLikeOps) {
        vpux::inferReturnTypes(viewLikeOp, vpux::InferShapedTypeMode::ALL);
    }

    log.trace("Successfully removed DDRToDDR input copy {0} at {1}", copyOp->getName(), copyOp->getLoc());
    rewriter.eraseOp(copyOp);
    return mlir::success();
}

mlir::LogicalResult removeDDR2DDRForNCEClusterOutput(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter,
                                                     Logger log) {
    // CMX Concat case with subView, update the buffers used
    if (auto subViewOp = copyOp.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>()) {
        // case with subView - retrieve operations to be re-linked
        auto masterBuffer = VPUIP::getRootAlloc<mlir::memref::AllocOp>(subViewOp->getOperand(0));
        if (masterBuffer == nullptr) {
            log.trace("Cannot match because source isn't master buffer");
            return mlir::failure();
        }
        auto parentOp = copyOp->getOperand(0).getDefiningOp<VPUIP::NCEClusterTilingOp>();
        // replace the copy with VPUIP subView
        rewriter.setInsertionPoint(parentOp);
        auto newSubViewOp = rewriter.create<VPUIP::SubViewOp>(
                subViewOp->getLoc(), subViewOp.getSource(), subViewOp.getStaticOffsetsAttr(),
                subViewOp.getStaticSizesAttr(), subViewOp.getStaticStridesAttr());
        parentOp.getOutputBuffs()[0].replaceAllUsesWith(newSubViewOp->getResult(0));
        parentOp->getResult(0).setType(newSubViewOp->getResult(0).getType());

        // update IR location of the master buffer
        if (newSubViewOp->isBeforeInBlock(masterBuffer)) {
            VPUIP::moveRootAllocBefore(masterBuffer, newSubViewOp);
        }
    } else {
        auto parentOp = copyOp.getInput().getDefiningOp<VPUIP::NCEClusterTilingOp>();
        auto allocOp = VPUIP::getRootAlloc<mlir::memref::AllocOp>(parentOp.getOutputBuffs()[0]);
        if (allocOp == nullptr) {
            log.trace("Cannot match because source isn't master buffer");
            return mlir::failure();
        }

        for (auto user : copyOp.getOutput().getUsers()) {
            auto concatOp = mlir::dyn_cast<VPUIP::ConcatViewOp>(user);
            concatOp.getOutputBuff().replaceAllUsesWith(allocOp->getResult(0));
        }
    }

    copyOp.getOutput().replaceAllUsesWith(copyOp.getInput());
    log.trace("Successfully removed Clustered DDRToDDR output copy {0} at {1}", copyOp->getName(), copyOp->getLoc());
    rewriter.eraseOp(copyOp);
    return mlir::success();
}

mlir::LogicalResult removeParallelDDR2DDRForNCEClusterOutput(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter,
                                                             Logger log) {
    auto parentOp = copyOp->getOperand(0).getDefiningOp<VPUIP::NCEClusterTilingOp>();

    for (auto user : llvm::make_early_inc_range(parentOp.getResult(0).getUsers())) {
        if (auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(*user)) {
            auto subview = copyOp.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>();

            rewriter.setInsertionPointAfter(subview);
            const auto copyOutBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc,
                                                mlir::ValueRange newOperands) {
                builder.create<VPUIP::CopyOp>(loc, newOperands[0], newOperands[1]);
            };
            SmallVector<mlir::Value> inputsOutputOperands = {parentOp->getOperand(0), subview.getResult()};
            auto newCopyInCluster = rewriter.create<VPUIP::NCEClusterTilingOp>(
                    parentOp->getLoc(), subview->getResult(0).getType(), inputsOutputOperands, copyOutBodyBuilder);

            copyOp.getOutput().replaceAllUsesWith(newCopyInCluster->getResult(0));

            log.trace("Successfully removed Parallel DDRToDDR output copy {0} at {1}", copyOp->getName(),
                      copyOp->getLoc());
            rewriter.eraseOp(copyOp);
        }
    }

    for (auto user : llvm::make_early_inc_range(parentOp.getResult(0).getUsers())) {
        if (auto subview = mlir::dyn_cast<VPUIP::SubViewOp>(*user)) {
            auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(*subview.getResult().getUsers().begin());
            if (copyOp == nullptr) {
                log.trace("CopyOp is null");
                return mlir::failure();
            }
            auto outputSubview = copyOp.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>();
            if (outputSubview == nullptr) {
                log.trace("Output subview is null");
                return mlir::failure();
            }

            rewriter.setInsertionPointAfter(copyOp);
            // New a new subview for copy output
            auto newSubView = rewriter.create<VPUIP::SubViewOp>(
                    subview->getLoc(), parentOp->getOperand(0), subview.getStaticOffsetsAttr(),
                    subview.getStaticSizesAttr(), subview.getStaticStridesAttr());

            const auto copyOutBodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc,
                                                mlir::ValueRange newOperands) {
                builder.create<VPUIP::CopyOp>(loc, newOperands[0], newOperands[1]);
            };
            SmallVector<mlir::Value> inputsOutputOperands = {newSubView.getResult(), outputSubview.getResult()};
            auto newCopyInCluster = rewriter.create<VPUIP::NCEClusterTilingOp>(
                    parentOp->getLoc(), outputSubview.getResult().getType(), inputsOutputOperands, copyOutBodyBuilder);

            copyOp.getOutput().replaceAllUsesWith(newCopyInCluster->getResult(0));
            log.trace("Successfully removed Parallel DDRToDDR output copy (with input subview) {0} at {1}",
                      copyOp->getName(), copyOp->getLoc());
            rewriter.eraseOp(copyOp);
            rewriter.eraseOp(subview);
        }
    }

    rewriter.eraseOp(parentOp);
    return mlir::success();
}

static inline bool checkOpsSupportInferType(mlir::Operation* startOp, mlir::Operation* endOp, Logger log) {
    auto currentOp = startOp;

    while (currentOp != endOp) {
        if (!mlir::isa<mlir::InferTypeOpInterface, mlir::memref::AllocOp, VPUIP::NCEClusterTilingOp>(currentOp)) {
            log.trace("Unexpected op {0} at {1}", currentOp->getName(), currentOp->getLoc());
            return false;
        }
        currentOp = currentOp->getNextNode();
    }
    return true;
}

static inline void inferOpsTypeBetween(mlir::Operation* startOp, mlir::Operation* endOp) {
    auto currentOp = startOp;

    while (currentOp != endOp) {
        // In case the currentOp is a VPUIP::NCEClusterTilingOp and it doesn't support mlir::InferTypeOpInterface,
        // then will setType based on the SubViewOp of this NCEClusterTilingOp,
        // no adapt to set the inner type as only the strides changed.

        // Only AllocOp and NCEClusterTilingOp will call this if func after checkOpsSupportInferType func
        // no need to infer AllocOp's type
        if (!mlir::isa<mlir::InferTypeOpInterface>(currentOp)) {
            if (auto tilingCopyOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(currentOp)) {
                for (auto result : currentOp->getResults() | indexed) {
                    result.value().setType(tilingCopyOp.getOutputBuffs()[result.index()].getType());
                }
                currentOp = currentOp->getNextNode();
            } else if (mlir::isa<mlir::memref::AllocOp>(currentOp)) {
                currentOp = currentOp->getNextNode();
                continue;
            } else {
                VPUX_THROW("Unexpected op type '{0}' at '{1}'", currentOp->getName(), currentOp->getLoc());
            }
        } else {
            vpux::inferReturnTypes(currentOp, vpux::InferShapedTypeMode::ALL);
            currentOp = currentOp->getNextNode();
        }
    }
}

mlir::LogicalResult removeDDR2DDRForConcatInput(VPUIP::CopyOp copyOp, mlir::PatternRewriter& rewriter, Logger log) {
    auto parentConcatOp = copyOp.getInput().getDefiningOp<VPUIP::ConcatViewOp>();
    auto parentMemAlloc = VPUIP::getRootAlloc<mlir::memref::AllocOp>(parentConcatOp.getOutputBuff());
    if (parentMemAlloc == nullptr) {
        log.trace("Cannot match because parentConcatOp output isn't master buffer");
        return mlir::failure();
    }

    auto childConcatOp = mlir::dyn_cast<VPUIP::ConcatViewOp>(*copyOp.getOutput().getUsers().begin());
    auto childMemAlloc = VPUIP::getRootAlloc<mlir::memref::AllocOp>(childConcatOp.getOutputBuff());
    if (childMemAlloc == nullptr) {
        log.trace("Cannot match because childConcatOp output isn't master buffer");
        return mlir::failure();
    }

    auto childMemSize = vpux::getTotalSize(childMemAlloc->getResult(0));
    auto parentMemSize = vpux::getTotalSize(parentMemAlloc->getResult(0));
    if (childMemSize <= parentMemSize) {
        log.error("There is no redundant Copy operation since the child size ({0}) <= parent size ({1})", childMemSize,
                  parentMemSize);
        return mlir::failure();
    }

    if (!checkOpsSupportInferType(parentMemAlloc, childConcatOp, log)) {
        log.trace("Cannot match because some Ops doesn't support InferTypeOpInterface");
        return mlir::failure();
    }

    log.trace("Successfully removed DDRToDDR output copy {0} at {1} for Concat", copyOp->getName(), copyOp->getLoc());
    auto childCopySubview = copyOp.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>();

    auto newSubViewOp = rewriter.create<VPUIP::SubViewOp>(parentMemAlloc->getLoc(), childCopySubview.getSource(),
                                                          childCopySubview.getStaticOffsetsAttr(),
                                                          childCopySubview.getStaticSizesAttr());

    // update IR location of the master buffer
    if (parentMemAlloc->isBeforeInBlock(newSubViewOp)) {
        VPUIP::moveRootAllocBefore(newSubViewOp, parentMemAlloc);
    }
    // update IR location of the master buffer
    if (newSubViewOp->isBeforeInBlock(childMemAlloc)) {
        VPUIP::moveRootAllocBefore(childMemAlloc, newSubViewOp);
    }

    parentMemAlloc->getResult(0).replaceAllUsesWith(newSubViewOp.getResult());
    rewriter.eraseOp(parentMemAlloc);
    // Re-Infer the Type of the Ops
    inferOpsTypeBetween(newSubViewOp, childConcatOp);

    copyOp.getOutput().replaceAllUsesWith(copyOp.getInput());
    rewriter.eraseOp(copyOp);
    return mlir::success();
}

mlir::LogicalResult DDRToDDRCopyOfNCECluster::matchAndRewrite(VPUIP::CopyOp copyOp,
                                                              mlir::PatternRewriter& rewriter) const {
    /*
     Remove redundant DDR2DDR Copy of the NCECluster's input:
ClusterTiling_Copy                    ...        SubView
   (CMX2DDR)        SubView             \         /
          \         /              ClusterTiling_Copy(CMX2DDR)
          Copy(DDR2DDR)        =>            |
               |                           Concat
            Concat

     Remove redundant DDR2DDR Copy of the NCECluster's output:
          Copy(DDR2DDR)            PureViewOp(Optional)
                |                          |
        PureViewOp(Optional)       ClusterTiling_Copy
                |                      (DDR2CMX)
        ClusterTiling_Copy    =>           |
            (DDR2CMX)              ClusterTiling_NCE
                |                          |
        ClusterTiling_NCE
                |

     Optimize the parallel DDR2DDR copies as CMX2DDR copies:
                ClusterTiling_Copy(CMX2DDR)
                      /        \
            Copy(DDR2DDR)       Copy(DDR2DDR)       =>
            /        \          /       \
        SubView           |            SubView
                          |
                        Concat

                         ...
                     /          \
ClusterTiling_Copy(CMX2DDR)   ClusterTiling_Copy(CMX2DDR)
            /        \          /       \
        SubView           |            SubView
                          |
                        Concat
     */
    _log.trace("DDRToDDRCopyOfNCECluster: Copy at {0}", copyOp->getLoc());
    auto nestedLogger = _log.nest();
    if (!VPUIP::isCopyFromDDR(copyOp) || !VPUIP::isCopyToDDR(copyOp)) {
        nestedLogger.trace("Cannot match because isn't DDR->DDR copy");
        return mlir::failure();
    }

    if (isDDR2DDROfNCEClusterInput(copyOp)) {
        return removeDDR2DDRForNCEClusterInput(copyOp, rewriter, nestedLogger);
    } else if (isDDR2DDROfNCEClusterOutput(copyOp)) {
        return removeDDR2DDRForNCEClusterOutput(copyOp, rewriter, nestedLogger);
    } else if (isParallelDDR2DDROfNCEClusterOutput(copyOp)) {
        // TODO: Add this optimization in single cluster case
        return removeParallelDDR2DDRForNCEClusterOutput(copyOp, rewriter, nestedLogger);
    } else if (isDDR2DDROfConcatInput(copyOp)) {
        return removeDDR2DDRForConcatInput(copyOp, rewriter, nestedLogger);
    }
    std::string possibleReason;
    if (copyOp.getInput().getDefiningOp<Const::DeclareOp>()) {
        possibleReason = " Copy from Constant isn't optimizable";
    }
    nestedLogger.trace("Unsupported pattern.{0}", possibleReason);
    return mlir::failure();
}

//
// ConcatViewWithCopyBase
//

class ConcatViewWithCopyBase : public mlir::OpRewritePattern<VPUIP::ConcatViewOp> {
public:
    ConcatViewWithCopyBase(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : mlir::OpRewritePattern<VPUIP::ConcatViewOp>(ctx, benefit), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPUIP::ConcatViewOp origOp, mlir::PatternRewriter& rewriter) const final;
    bool isLegalConcatViewPattern(VPUIP::ConcatViewOp origOp, vpux::Logger log) const;

    virtual bool hasLegalCopyUser(VPUIP::ConcatViewOp sourceOp) const = 0;
    virtual mlir::Value getOutputBuffer(mlir::Operation* sourceOp) const = 0;
    virtual mlir::LogicalResult adaptBufferTypeToPemuteCastInput(mlir::Value buffer, VPUIP::PermuteCastOp permuteCast,
                                                                 Logger log) const = 0;
    virtual VPUIP::LayerOpInterface createNewCopyOp(VPUIP::CopyOp copyInput, VPUIP::SubViewOp subViewOp,
                                                    mlir::PatternRewriter& rewriter) const = 0;

private:
    bool hasDuplicatedCopyOutput(VPUIP::ConcatViewOp origOp) const;

    Logger _log;
};

VPU::DistributedTensorAttr deducePermuteCastInputDistributedTensorAttr(VPUIP::PermuteCastOp permuteCast,
                                                                       VPU::DistributedTensorAttr outputDistribution) {
    auto perm = permuteCast.getMemPerm();
    auto inversePerm = mlir::inversePermutation(perm);

    auto inPermuteType = permuteCast->getOperand(0).getType().cast<vpux::NDTypeInterface>();
    auto outPermuteType = permuteCast->getResult(0).getType().cast<vpux::NDTypeInterface>();

    return applyPermutationOnDistributedTensorAttr(outputDistribution, inversePerm, outPermuteType.getDimsOrder(),
                                                   inPermuteType.getDimsOrder(), outPermuteType.getShape(),
                                                   inPermuteType.getShape());
}

mlir::LogicalResult ConcatViewWithCopyBase::matchAndRewrite(VPUIP::ConcatViewOp origOp,
                                                            mlir::PatternRewriter& rewriter) const {
    if (!isLegalConcatViewPattern(origOp, _log)) {
        _log.nest().trace("Cannot fuse this ConcatView Op {0}", origOp.getLoc());
        return mlir::failure();
    }

    mlir::Operation* firstCopyOp;
    auto* childOp = getFirstUser(origOp.getResult());
    auto permuteCastOp = mlir::dyn_cast<VPUIP::PermuteCastOp>(childOp);
    if (permuteCastOp != nullptr) {
        firstCopyOp = getFirstUser(permuteCastOp.getResult());
    } else {
        firstCopyOp = childOp;
    }
    VPUX_THROW_UNLESS(firstCopyOp != nullptr, "Cannot get the first user Op");

    _log.trace("Got ConcatView Op at '{0}'", origOp.getLoc());

    SmallVector<mlir::Value> concatInputs;
    auto outBuffer = getOutputBuffer(firstCopyOp);

    // record original buffer type before adaptBufferTypeToPemuteCastInput is called as it may be adjusted in it
    auto origBufferType = outBuffer.getType();
    // update buffer type if there is PermuteCastOp after ConcatViewOp
    if (permuteCastOp != nullptr) {
        if (mlir::failed(adaptBufferTypeToPemuteCastInput(outBuffer, permuteCastOp, _log))) {
            _log.nest().trace("Failed to adapt buffer type to PermuteCast input at '{0}'", origOp.getLoc());
            return mlir::failure();
        }
    }

    auto outBufferDefiningOp = outBuffer.getDefiningOp();
    VPUX_THROW_WHEN(outBufferDefiningOp == nullptr, "Cannot get defining op for {0}", outBuffer);
    rewriter.setInsertionPointAfter(outBufferDefiningOp);
    for (auto input : origOp.getInputs()) {
        auto copyOp = input.getDefiningOp<VPUIP::CopyOp>();
        auto subViewOp = copyOp.getOutputBuff().getDefiningOp<VPUIP::SubViewOp>();

        auto newSubView =
                rewriter.create<VPUIP::SubViewOp>(copyOp.getLoc(), outBuffer, subViewOp.getStaticOffsetsAttr(),
                                                  subViewOp.getStaticSizesAttr(), subViewOp.getStaticStridesAttr());

        auto newCopyOp = createNewCopyOp(copyOp, newSubView, rewriter);

        concatInputs.push_back(newCopyOp->getResult(0));
    }

    rewriter.setInsertionPointAfter(firstCopyOp);
    auto newConcatOp = rewriter.create<VPUIP::ConcatViewOp>(firstCopyOp->getLoc(), concatInputs, outBuffer);
    if (permuteCastOp != nullptr) {
        auto newPermuteCastOp =
                rewriter.create<VPUIP::PermuteCastOp>(permuteCastOp->getLoc(), origBufferType, newConcatOp,
                                                      permuteCastOp.getDstOrderAttr(), permuteCastOp.getMemPermAttr());
        for (auto userCopyOp : llvm::make_early_inc_range(origOp.getOutput().getUsers())) {
            rewriter.replaceOp(userCopyOp, newPermuteCastOp.getResult());
        }
    } else {
        for (auto userCopyOp : llvm::make_early_inc_range(origOp.getOutput().getUsers())) {
            rewriter.replaceOp(userCopyOp, newConcatOp.getOutput());
        }
    }

    _log.nest().trace("Successfully simplified ConcatView {0}", origOp->getLoc());
    return mlir::success();
}

/*
  Check pattern:
  Copy (DDR2DDR)  ...  Copy (DDR2DDR)
       \               /
        Concat View (DDR)
             |
        [PermuteCast]
             |
        Copy(DDR2CMX)
*/
bool ConcatViewWithCopyBase::isLegalConcatViewPattern(VPUIP::ConcatViewOp origOp, vpux::Logger log) const {
    if (!origOp.getOutput().hasOneUse() && !hasDuplicatedCopyOutput(origOp)) {
        log.nest().trace("Cannot find user copy op at '{0}'", origOp);
        return false;
    }
    for (auto input : origOp.getInputs()) {
        auto op = mlir::dyn_cast_or_null<VPUIP::CopyOp>(input.getDefiningOp());
        if (op == nullptr || !VPUIP::isCopyToDDR(op) || !VPUIP::isCopyFromDDR(op)) {
            return false;
        }
    }

    return hasLegalCopyUser(origOp);
}

bool ConcatViewWithCopyBase::hasDuplicatedCopyOutput(VPUIP::ConcatViewOp origOp) const {
    if (origOp.use_empty()) {
        return false;
    }
    auto isSameCopyType = [](mlir::Operation* preOp, mlir::Operation* nextOp) {
        auto preCopyOp = mlir::dyn_cast<VPUIP::CopyOp>(preOp);
        auto nextCopyOp = mlir::dyn_cast<VPUIP::CopyOp>(nextOp);
        if (preCopyOp != nullptr && nextCopyOp != nullptr) {
            auto preOutType = preCopyOp.getOutput().getType().dyn_cast<vpux::NDTypeInterface>();
            auto nextOutType = preCopyOp.getOutput().getType().dyn_cast<vpux::NDTypeInterface>();
            return preOutType == nextOutType;
        }

        auto preClusterCopyOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(preOp);
        auto nextClusterCopyOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(nextOp);
        if (preClusterCopyOp == nullptr || nextClusterCopyOp == nullptr) {
            return false;
        }
        auto preInnerCopyOp = mlir::dyn_cast<VPUIP::CopyOp>(preClusterCopyOp.getInnerTaskOp());
        auto nextInnerCopyOp = mlir::dyn_cast<VPUIP::CopyOp>(nextClusterCopyOp.getInnerTaskOp());
        if (preInnerCopyOp == nullptr || nextInnerCopyOp == nullptr) {
            return false;
        }
        auto preOutputType = preClusterCopyOp.getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
        auto nextOutputType = nextClusterCopyOp.getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
        return preOutputType == nextOutputType;
    };

    auto firstUser = *origOp.getOutput().getUsers().begin();
    return llvm::all_of(origOp.getOutput().getUsers(), [&](auto user) {
        return isSameCopyType(firstUser, user);
    });
}

//
// ConcatViewWithCopy
//

/*
  Copy (DDR -> DDR)  ...  Copy (DDR -> DDR)
                \               /
                Concat View (DDR)             =>           Copy (DDR -> CMX) ... Copy (DDR -> CMX)
                        |                                           \               /
                  [PermuteCast]                                     Concat View (CMX)
                        |                                                   |
                Copy (DDR -> CMX)                                     [PermuteCast]
*/

class ConcatViewWithCopy final : public ConcatViewWithCopyBase {
public:
    ConcatViewWithCopy(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : ConcatViewWithCopyBase(ctx, benefit, log) {
    }

public:
    bool hasLegalCopyUser(VPUIP::ConcatViewOp sourceOp) const override;
    mlir::Value getOutputBuffer(mlir::Operation* sourceOp) const override;
    mlir::LogicalResult adaptBufferTypeToPemuteCastInput(mlir::Value buffer, VPUIP::PermuteCastOp permuteCast,
                                                         Logger log) const override;
    VPUIP::LayerOpInterface createNewCopyOp(VPUIP::CopyOp copyInput, VPUIP::SubViewOp subViewOp,
                                            mlir::PatternRewriter& rewriter) const override;
};

bool ConcatViewWithCopy::hasLegalCopyUser(VPUIP::ConcatViewOp sourceOp) const {
    auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(*sourceOp->getUsers().begin());
    if (copyOp == nullptr) {
        auto maybePermuteCast = mlir::dyn_cast<VPUIP::PermuteCastOp>(*sourceOp->getUsers().begin());
        if (maybePermuteCast == nullptr || !maybePermuteCast->hasOneUse()) {
            return false;
        }

        copyOp = mlir::dyn_cast<VPUIP::CopyOp>(*maybePermuteCast->getUsers().begin());
    }

    return copyOp != nullptr && VPUIP::isCopyFromDDR(copyOp) && !VPUIP::isCopyToDDR(copyOp) &&
           !VPUIP::isCopyWithStaticStrides(copyOp);
}

mlir::Value ConcatViewWithCopy::getOutputBuffer(mlir::Operation* sourceOp) const {
    auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(sourceOp);
    VPUX_THROW_WHEN(copyOp == nullptr, "Unexpected op type at '{0}'", sourceOp->getLoc());
    return copyOp.getOutputBuff();
}

mlir::LogicalResult ConcatViewWithCopy::adaptBufferTypeToPemuteCastInput(mlir::Value buffer,
                                                                         VPUIP::PermuteCastOp permuteCastOp,
                                                                         Logger log) const {
    auto origBufferType = buffer.getType();
    auto permuteCastInputType = permuteCastOp.getSource().getType().cast<NDTypeInterface>();
    auto permuteCastInputOrder = permuteCastInputType.getDimsOrder();
    auto permuteCastInputShape = permuteCastInputType.getShape();

    if (origBufferType.isa<mlir::MemRefType>()) {
        auto masterBuffer = VPUIP::getRootAlloc<mlir::memref::AllocOp>(buffer);
        if (masterBuffer == nullptr) {
            log.trace("Cannot match because buffer isn't master buffer");
            return mlir::failure();
        }

        auto outputType = buffer.getType().cast<NDTypeInterface>();
        buffer.setType(outputType.changeDimsOrder(permuteCastInputOrder).changeShape(permuteCastInputShape));
    } else if (auto sparseType = origBufferType.dyn_cast<VPUIP::SparseBufferType>()) {
        if (!mlir::isa<mlir::MemRefType>(sparseType.getData())) {
            log.trace("Unknown SparseBuffer type {0}", sparseType);
            return mlir::failure();
        }

        auto masterBuffer = VPUIP::getRootAlloc<mlir::memref::AllocOp>(buffer);
        if (masterBuffer == nullptr) {
            log.trace("Cannot match because buffer isn't master buffer");
            return mlir::failure();
        }

        auto groupSparseBuffer = mlir::dyn_cast<VPUIP::GroupSparseBufferOp>(masterBuffer);
        VPUX_THROW_WHEN(groupSparseBuffer == nullptr, "Can not find GroupSparseBufferOp");

        if (groupSparseBuffer.getStorageElementTable() != nullptr) {
            log.trace("Not support when GroupSparseBufferOp has storage element table");
            return mlir::failure();
        }

        // Change DimsOrder and Shape for Data and SparsityMap
        auto inputData = groupSparseBuffer.getData();
        auto inputDataType = inputData.getType()
                                     .cast<NDTypeInterface>()
                                     .changeDimsOrder(permuteCastInputOrder)
                                     .changeShape(permuteCastInputShape);
        inputData.setType(inputDataType);

        auto sparsityMap = groupSparseBuffer.getSparsityMap();
        if (sparsityMap != nullptr) {
            Shape newSMShape;
            if (sparseType.getIsWeights() == nullptr) {
                newSMShape = Shape(permuteCastInputShape.raw());
            } else {
                newSMShape = VPU::NCESparsity::inferWeightsSparsityMapShape(permuteCastInputShape);
            }
            auto sparsityMapType = sparsityMap.getType()
                                           .cast<NDTypeInterface>()
                                           .changeDimsOrder(permuteCastInputOrder)
                                           .changeShape(newSMShape);
            sparsityMap.setType(sparsityMapType);
        }

        auto newSparseType = sparseType.changeDimsOrder(permuteCastInputOrder).changeShape(permuteCastInputShape);
        buffer.setType(newSparseType);
    } else {
        log.trace("Unknown buffer type {0}", origBufferType);
        return mlir::failure();
    }

    return mlir::success();
}

VPUIP::LayerOpInterface ConcatViewWithCopy::createNewCopyOp(VPUIP::CopyOp copyInput, VPUIP::SubViewOp subViewOp,
                                                            mlir::PatternRewriter& rewriter) const {
    return rewriter.replaceOpWithNewOp<VPUIP::CopyOp>(copyInput, copyInput.getInput(), subViewOp.getResult());
}

//
// ConcatViewWithTilingCopy
//

/*
 Copy (DDR -> DDR)  ...  Copy (DDR -> DDR)
                \               /
                Concat View (DDR)             =>  Cluster Copy (DDR -> CMX) ... Cluster Copy (DDR -> CMX)
                        |                                           \               /
                  [PermuteCast]                                     Concat View (CMX)
                        |                                                   |
              Cluster Copy (DDR -> CMX)                             [PermuteCast]
*/

class ConcatViewWithTilingCopy final : public ConcatViewWithCopyBase {
public:
    ConcatViewWithTilingCopy(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : ConcatViewWithCopyBase(ctx, benefit, log) {
    }

public:
    bool hasLegalCopyUser(VPUIP::ConcatViewOp sourceOp) const override;
    mlir::Value getOutputBuffer(mlir::Operation* sourceOp) const override;
    mlir::LogicalResult adaptBufferTypeToPemuteCastInput(mlir::Value buffer, VPUIP::PermuteCastOp permuteCast,
                                                         Logger log) const override;
    VPUIP::LayerOpInterface createNewCopyOp(VPUIP::CopyOp copyInput, VPUIP::SubViewOp subViewOp,
                                            mlir::PatternRewriter& rewriter) const override;
};

bool ConcatViewWithTilingCopy::hasLegalCopyUser(VPUIP::ConcatViewOp sourceOp) const {
    auto clusterOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(*sourceOp->getUsers().begin());
    VPUIP::PermuteCastOp maybePermuteCast = nullptr;
    if (clusterOp == nullptr) {
        maybePermuteCast = mlir::dyn_cast<VPUIP::PermuteCastOp>(*sourceOp->getUsers().begin());
        if (maybePermuteCast == nullptr || !maybePermuteCast->hasOneUse()) {
            return false;
        }

        clusterOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(*maybePermuteCast->getUsers().begin());
    }

    if (clusterOp == nullptr) {
        return false;
    }

    auto copyOp = clusterOp.getInnerTaskOpOfType<VPUIP::CopyOp>();
    if (copyOp == nullptr || isStridedCopy(copyOp)) {
        return false;
    }

    // Get the concat dims
    const auto inputType = sourceOp.getInputs()[0].getType().cast<vpux::NDTypeInterface>();
    const auto outputType = sourceOp.getOutput().getType().cast<vpux::NDTypeInterface>();
    const auto inShape = inputType.getShape();
    const auto outShape = outputType.getShape();
    VPUX_THROW_UNLESS(inShape.size() == outShape.size(), "Input shape size {0} is not equal to output shape size {1}",
                      inShape.size(), outShape.size());
    SmallVector<Dim> concatDims;
    for (auto idx : irange(inShape.size())) {
        if (inShape[Dim(idx)] != outShape[Dim(idx)]) {
            concatDims.push_back(Dim(idx));
        }
    }
    VPUX_THROW_WHEN(concatDims.empty(), "ConcatView inShape '{0}' same with the outShape '{1}'", inputType.getShape(),
                    outputType.getShape());

    const auto distributedType =
            VPUIP::extractDataType(clusterOp.getOutputBuffs()[0]).dyn_cast<VPUIP::DistributedBufferType>();
    VPUX_THROW_UNLESS(distributedType != nullptr, "Cannot get distributedType");

    auto distribution = distributedType.getDistribution();
    if (maybePermuteCast != nullptr) {
        distribution = deducePermuteCastInputDistributedTensorAttr(maybePermuteCast, distribution);
    }

    // For Overlapped mode, use compute_shape and compute_offset to unroll the DMA copy in unroll cluster copy
    // Then we will lost the stride info of the input. It will cause result incorrect
    //     TilingCopy (1x16x8x8)      TilingCopy(1x16x8x8)
    //                      \           /
    //                    Concat(1x32x8x8) (shape[1,32,5,8][1,32,5,8], offset[0,0,0,0][0,0,3,0])
    // TODO: E#78122 remove the checking after the jira fixed
    if (distribution.getMode().getValue() == VPU::DistributionMode::OVERLAPPED) {
        return false;
    }
    if (distribution.getNumTiles() != nullptr) {
        const auto tilingScheme = parseIntArrayAttr<int64_t>(distribution.getNumTiles());
        const auto tileAxis = vpux::VPU::getDistributedTilingAxis(tilingScheme);

        if (llvm::find(concatDims, Dim(tileAxis)) != concatDims.end() ||
            (outShape[Dim(tileAxis)] % tilingScheme[tileAxis] != 0)) {
            // If the output buffer on tile dim can not be divided evenly on each tile, the buffer will be discontinous
            // after concat, so need to avoid such tranform.
            // E.g.:
            // VPUIP.SubView %source [0, 0, 0, 0] [1, 512, 35, 36] ->SEGMENTED with numTiles = [1, 1, 4, 1]
            // VPUIP.SubView %source [0, 128, 0, 0] [1, 512, 35, 36] -> SEGMENTED with numTiles = [1, 1, 4, 1]
            // The distribution in memory for this example would be:
            //             Cluster 0        Cluster 1        Cluster 2        Cluster 3
            // offset0  x_______________________________________________________________
            //          |  9 lines of   |  9 lines of   |  9 lines of   |  8 lines of   |
            //          | actual data   | actual data   | actual data   | actual data   |
            //          |               |               |               |---------------|
            // offset1  x---------------|---------------|---------------|---------------|
            //          |  9 lines of   |  9 lines of   |  9 lines of   |  8 lines of   |
            //          | actual data   | actual data   | actual data   | actual data   |
            //          |_______________|_______________|_______________|_______________|
            // Unexpected concat on cluster3
            return false;
        }
    }

    return VPUIP::isCopyFromDDR(copyOp) && !VPUIP::isCopyToDDR(copyOp);
}

mlir::Value ConcatViewWithTilingCopy::getOutputBuffer(mlir::Operation* sourceOp) const {
    auto clusterTilingOp = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(sourceOp);
    VPUX_THROW_WHEN(clusterTilingOp == nullptr, "Unexpected op type at '{0}'", sourceOp);
    return clusterTilingOp.getOutputBuffs()[0];
}

mlir::LogicalResult ConcatViewWithTilingCopy::adaptBufferTypeToPemuteCastInput(mlir::Value buffer,
                                                                               VPUIP::PermuteCastOp permuteCastOp,
                                                                               Logger log) const {
    auto ctx = permuteCastOp->getContext();
    auto origBufferType = buffer.getType();
    auto permuteCastInputType = permuteCastOp.getSource().getType().cast<NDTypeInterface>();
    auto permuteCastInputOrder = permuteCastInputType.getDimsOrder();
    auto permuteCastInputShape = permuteCastInputType.getShape();

    auto getNewDistributedType = [&](VPUIP::DistributedBufferType origType, ShapeRef newShape,
                                     DimsOrder newOrder) -> VPUIP::DistributedBufferType {
        auto origDistribution = origType.getDistribution();
        auto newDistribution = deducePermuteCastInputDistributedTensorAttr(permuteCastOp, origDistribution);
        const auto newOrderMap = mlir::AffineMapAttr::get(newOrder.toAffineMap(ctx));
        return VPUIP::DistributedBufferType::get(ctx, newShape.raw(), origType.getElementType(), newOrderMap,
                                                 origType.getMemSpace(), newDistribution);
    };

    if (auto origDistributedBufferType = origBufferType.dyn_cast<VPUIP::DistributedBufferType>()) {
        auto masterBuffer = VPUIP::getRootAlloc<VPURT::AllocDistributed>(buffer);
        if (masterBuffer == nullptr) {
            log.trace("Cannot match because buffer isn't master buffer");
            return mlir::failure();
        }

        auto newBufferType =
                getNewDistributedType(origDistributedBufferType, permuteCastInputShape, permuteCastInputOrder);
        buffer.setType(newBufferType);
    } else if (auto sparseType = origBufferType.dyn_cast<VPUIP::SparseBufferType>()) {
        auto distDataType = sparseType.getData().dyn_cast<VPUIP::DistributedBufferType>();
        if (distDataType == nullptr) {
            log.trace("Unknown SparseBuffer type {0}", sparseType);
            return mlir::failure();
        }

        auto masterBuffer = VPUIP::getRootAlloc<VPURT::AllocDistributed>(buffer);
        if (masterBuffer == nullptr) {
            log.trace("Cannot match because buffer isn't master buffer");
            return mlir::failure();
        }

        auto groupSparseBuffer = mlir::dyn_cast<VPUIP::GroupSparseBufferOp>(masterBuffer);
        VPUX_THROW_WHEN(groupSparseBuffer == nullptr, "Can not find GroupSparseBufferOp");

        if (groupSparseBuffer.getStorageElementTable() != nullptr) {
            log.trace("Not support when GroupSparseBufferOp has storage element table");
            return mlir::failure();
        }

        // Change distributed types for Data and SparsityMap
        auto inputData = groupSparseBuffer.getData();
        auto newDataDistributedType = getNewDistributedType(sparseType.getData().cast<VPUIP::DistributedBufferType>(),
                                                            permuteCastInputShape, permuteCastInputOrder);
        inputData.setType(newDataDistributedType);

        auto sparsityMap = groupSparseBuffer.getSparsityMap();
        VPUIP::DistributedBufferType newSMDistributedType = nullptr;
        if (sparsityMap != nullptr) {
            Shape newSMShape;
            if (sparseType.getIsWeights() == nullptr) {
                newSMShape = Shape(permuteCastInputShape.raw());
            } else {
                newSMShape = VPU::NCESparsity::inferWeightsSparsityMapShape(permuteCastInputShape);
            }
            newSMDistributedType =
                    getNewDistributedType(sparseType.getSparsityMap().cast<VPUIP::DistributedBufferType>(), newSMShape,
                                          permuteCastInputOrder);
            sparsityMap.setType(newSMDistributedType);
        }

        auto newSparseType = VPUIP::SparseBufferType::get(newDataDistributedType, newSMDistributedType, nullptr,
                                                          sparseType.getIsWeights(), sparseType.getCompressionScheme());
        buffer.setType(newSparseType);
    } else {
        log.trace("Unknown buffer type {0}", origBufferType);
        return mlir::failure();
    }

    return mlir::success();
}

VPUIP::LayerOpInterface ConcatViewWithTilingCopy::createNewCopyOp(VPUIP::CopyOp copyInput, VPUIP::SubViewOp subViewOp,
                                                                  mlir::PatternRewriter& rewriter) const {
    const auto bodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location, mlir::ValueRange newOperands) {
        builder.create<VPUIP::CopyOp>(copyInput->getLoc(), newOperands[0], newOperands[1]);
    };
    auto inputsOutputOperands = {copyInput.getInput(), subViewOp.getResult()};
    auto newClusterTilingOutType = subViewOp.getResult().getType().cast<vpux::NDTypeInterface>();
    return rewriter.replaceOpWithNewOp<VPUIP::NCEClusterTilingOp>(copyInput, newClusterTilingOutType,
                                                                  inputsOutputOperands, bodyBuilder);
}

//
// FuseCopyToTheFrontOfTillingCopy
//
/*
 Fuse copy into the front Tilling copy
          |                |
  TillingCopy    =>  TillingCopy
          |                |
         Copy
          |
*/

class FuseCopyToTheFrontOfTillingCopy final : public mlir::OpRewritePattern<VPUIP::NCEClusterTilingOp> {
public:
    FuseCopyToTheFrontOfTillingCopy(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, Logger log)
            : mlir::OpRewritePattern<VPUIP::NCEClusterTilingOp>(ctx, benefit), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPUIP::NCEClusterTilingOp clusterTilingCopyOp,
                                        mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult FuseCopyToTheFrontOfTillingCopy::matchAndRewrite(VPUIP::NCEClusterTilingOp clusterTilingCopy,
                                                                     mlir::PatternRewriter& rewriter) const {
    /*
    case 1:
              |                          |
      TillingCopy(CMX2DDR)    =>     TillingCopy(CMX2CMX)
              |                          |
           Copy(DDR2CMX)
              |

    case 2:
              |                          |
      TillingCopy(CMX2DDR)    =>     TillingCopy(CMX2DDR)
              |                          |
           Copy(DDR2DDR)
              |
    */

    auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(clusterTilingCopy.getInnerTaskOp());
    if (copyOp == nullptr || VPUIP::isCopyFromDDR(copyOp) || !VPUIP::isCopyToDDR(copyOp)) {
        return mlir::failure();
    }

    if (!clusterTilingCopy->hasOneUse()) {
        return mlir::failure();
    }

    auto tilingCopyOutput = clusterTilingCopy.getResult(0);
    auto outType = tilingCopyOutput.getType().dyn_cast<vpux::NDTypeInterface>();
    auto userCopyOp = mlir::dyn_cast<VPUIP::CopyOp>(*(tilingCopyOutput.getUsers().begin()));
    if (!userCopyOp) {
        return mlir::failure();
    }

    auto userOutType = userCopyOp.getOutputBuff().getType().dyn_cast<vpux::NDTypeInterface>();
    if (userOutType.changeMemSpace(VPU::MemoryKind::DDR) != outType) {
        return mlir::failure();
    }

    auto userOutputMemKind = userOutType.getMemoryKind();
    if (userOutputMemKind == VPU::MemoryKind::CMX_NN) {
        auto inputType = clusterTilingCopy.getOperand(0).getType().dyn_cast<vpux::NDTypeInterface>();
        if (auto subviewOp = clusterTilingCopy.getInputs()[0].getDefiningOp<VPUIP::SubViewOp>()) {
            inputType = subviewOp.getViewSource().getType().cast<vpux::NDTypeInterface>();
        }

        Byte requiredCMX(0);
        requiredCMX += inputType.getTotalAllocSize();
        requiredCMX += userOutType.getTotalAllocSize();
        if (requiredCMX > VPU::getTotalCMXSize(userCopyOp)) {
            _log.trace("Available CMX size is {0}, but need {1}", VPU::getTotalCMXSize(userCopyOp), requiredCMX);
            return mlir::failure();
        }
    }

    const auto bodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location, mlir::ValueRange newOperands) {
        builder.create<VPUIP::CopyOp>(clusterTilingCopy->getLoc(), newOperands[0], newOperands[1]);
    };

    SmallVector<mlir::Value> inputsOutputOperands = {clusterTilingCopy->getOperand(0), userCopyOp.getOutputBuff()};

    rewriter.setInsertionPointAfter(userCopyOp);
    auto newClusterTilingCopyOp = rewriter.create<VPUIP::NCEClusterTilingOp>(clusterTilingCopy->getLoc(), userOutType,
                                                                             inputsOutputOperands, bodyBuilder);
    userCopyOp.replaceAllUsesWith(newClusterTilingCopyOp);
    rewriter.eraseOp(userCopyOp);
    rewriter.eraseOp(clusterTilingCopy);
    return mlir::success();
}

//
// SubViewWithCopyBase
//
/*
 Move SubView after TillingCopy, the assumption is to reduce copy op numbers if subview have multi tiling copy users
                        buffer
            /                            \
      subview(Tile on N)               subview(Tile on N)
           |                               |
      TilingCopy(Segmented on N)       TilingCopy(Segmented on N)
           |                               |
         MatMul                         MatMul

                           =>

                       buffer
                         |
                   TilingCopy(Duplicated)
               /                            \
      subview(Tile on N)                 subview(Tile on N)
              |                              |
DistributedCast(Duplicated|Segmented)    DistributedCast(Duplicated|Segmented)
              |                              |
           MatMul                          MatMul

*/

class SubViewWithCopyBase : public mlir::OpRewritePattern<VPUIP::CopyOp> {
public:
    SubViewWithCopyBase(mlir::MLIRContext* ctx, mlir::PatternBenefit benefit, int64_t cmxSize, Logger log)
            : mlir::OpRewritePattern<VPUIP::CopyOp>(ctx, benefit), _cmxSize(cmxSize), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(VPUIP::CopyOp origOp, mlir::PatternRewriter& rewriter) const final;
    mlir::Value getSuitableSubViewPatternSourceBuffer(VPUIP::CopyOp origOp, vpux::Logger log) const;
    bool checkCMXFit(mlir::Value topBuffer) const;

private:
    int64_t _cmxSize{};
    Logger _log;
};

bool SubViewWithCopyBase::checkCMXFit(mlir::Value topBuffer) const {
    auto type = topBuffer.getType().dyn_cast<vpux::NDTypeInterface>();
    // buffer will keep duplicated in cmx after tiling copy, so need to check the required cmx
    Byte requiredSize = type.getTotalAllocSize();
    if (type.getMemoryKind() == VPU::MemoryKind::CMX_NN) {
        requiredSize += type.getTotalAllocSize();
    }
    return vpux::Byte(_cmxSize) >= requiredSize;
}

mlir::LogicalResult SubViewWithCopyBase::matchAndRewrite(VPUIP::CopyOp origOp, mlir::PatternRewriter& rewriter) const {
    auto nestedLogger = _log.nest();
    auto topBuffer = getSuitableSubViewPatternSourceBuffer(origOp, nestedLogger);
    if (topBuffer == nullptr) {
        return mlir::failure();
    }

    auto ctx = origOp->getContext();
    const auto topBufferType = topBuffer.getType().cast<vpux::NDTypeInterface>();
    const auto copyOutputType = origOp->getResult(0).getType().cast<vpux::NDTypeInterface>();
    const auto layout = mlir::AffineMapAttr::get(topBufferType.getDimsOrder().toAffineMap(origOp->getContext()));
    auto tilingCopy = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(origOp->getParentOp());
    auto distributedType = tilingCopy->getResult(0).getType().cast<VPUIP::DistributedBufferType>();
    auto distribution = distributedType.getDistribution();

    // create duplicated type
    const auto distributionModeAttr = VPU::DistributionModeAttr::get(ctx, VPU::DistributionMode::DUPLICATED);
    const auto distributedAttr =
            VPU::DistributedTensorAttr::get(ctx, distributionModeAttr, distribution.getNumTiles(), nullptr, nullptr,
                                            nullptr, distribution.getNumClusters(), distribution.getAlignment(),
                                            nullptr, nullptr, nullptr, nullptr, nullptr, nullptr);

    auto distributedBufferType = VPUIP::DistributedBufferType::get(origOp->getContext(), topBufferType.getShape().raw(),
                                                                   topBufferType.getElementType(), layout,
                                                                   copyOutputType.getMemSpace(), distributedAttr);

    rewriter.setInsertionPointAfterValue(topBuffer);
    auto newBuffer = rewriter.create<VPURT::AllocDistributed>(appendLoc(origOp->getLoc(), "_extract"),
                                                              distributedBufferType, nullptr, nullptr);
    nestedLogger.trace("create new buff {0}", newBuffer);

    const auto bodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location, mlir::ValueRange newOperands) {
        builder.create<VPUIP::CopyOp>(appendLoc(origOp->getLoc(), "_extract"), newOperands[0], newOperands[1]);
    };
    SmallVector<mlir::Value> inputsOutputOperands = {topBuffer, newBuffer};
    auto newCopy = rewriter.create<VPUIP::NCEClusterTilingOp>(appendLoc(origOp->getLoc(), "_extract"),
                                                              newBuffer.getType(), inputsOutputOperands, bodyBuilder);
    nestedLogger.trace("Created ops '{0}'", newCopy);

    for (auto siblingOp : llvm::make_early_inc_range(topBuffer.getUsers())) {
        auto siblingSubViewOp = mlir::dyn_cast<VPUIP::SubViewOp>(siblingOp);
        if (siblingSubViewOp == nullptr) {
            continue;
        }
        VPUX_THROW_UNLESS(siblingSubViewOp.getResult().hasOneUse(), "subview should has one use");
        auto siblingCopyOp = *siblingSubViewOp.getResult().getUsers().begin();

        rewriter.setInsertionPoint(siblingSubViewOp);
        nestedLogger.trace("Creating VPUIP.SubView '{0}' at '{1}'", siblingSubViewOp->getName(),
                           siblingSubViewOp->getLoc());
        auto newSliceOp = rewriter.create<VPUIP::SubViewOp>(
                appendLoc(siblingSubViewOp->getLoc(), "_CMX"), newCopy->getResult(0),
                siblingSubViewOp.getStaticOffsetsAttr(), siblingSubViewOp.getStaticSizesAttr());

        auto siblingCopyOutType = siblingCopyOp->getResult(0).getType().dyn_cast<VPUIP::DistributedBufferType>();
        auto siblingDistribution = siblingCopyOutType.getDistribution();

        const auto targetDistributionModeAttr = VPU::DistributionModeAttr::get(
                ctx, VPU::DistributionMode::DUPLICATED | VPU::DistributionMode::SEGMENTED);
        const auto targetDistributedAttr = VPU::DistributedTensorAttr::get(
                ctx, targetDistributionModeAttr, siblingDistribution.getNumTiles(), siblingDistribution.getKernel(),
                siblingDistribution.getPads(), siblingDistribution.getStrides(), siblingDistribution.getNumClusters(),
                siblingDistribution.getAlignment(), nullptr, nullptr, nullptr, nullptr, nullptr, nullptr);

        auto targetDistributedBufferType = VPUIP::DistributedBufferType::get(
                ctx, siblingCopyOutType.getShape().raw(), siblingCopyOutType.getElementType(),
                siblingCopyOutType.getLayout(), siblingCopyOutType.getMemSpace(), targetDistributedAttr);

        nestedLogger.trace("create new subview {0}", newSliceOp);
        auto distributedCastOp = rewriter.create<VPUIP::DistributedCastOp>(
                newSliceOp->getLoc(), targetDistributedBufferType, newSliceOp.getResult());
        nestedLogger.trace("create new cast {0}", distributedCastOp);

        siblingCopyOp->getResult(0).replaceAllUsesWith(distributedCastOp);

        rewriter.eraseOp(siblingCopyOp);
        rewriter.eraseOp(siblingSubViewOp);
    }

    return mlir::success();
}

/*
  Check pattern:
          TopBuffer
             |
          SubView
             |
    Tiling Copy(Segmented on dim N)
*/

mlir::Value SubViewWithCopyBase::getSuitableSubViewPatternSourceBuffer(VPUIP::CopyOp origOp, vpux::Logger log) const {
    auto isTilingCopyOpSegmentedOnN = [&log](VPUIP::NCEClusterTilingOp tilingCopyOp) {
        auto copyOp = mlir::dyn_cast<VPUIP::CopyOp>(tilingCopyOp.getInnerTaskOp());
        if (copyOp == nullptr) {
            log.trace("Not NCE Cluster Tiling Copy");
            return false;
        }
        auto outType = tilingCopyOp.getResults()[0].getType().cast<vpux::NDTypeInterface>();
        const auto distributedType = outType.dyn_cast<VPUIP::DistributedBufferType>();
        if (outType == nullptr) {
            return false;
        }

        return VPU::isSegmentedOverN(distributedType.getDistribution());
    };

    auto doesTilingCopyOpHasStridedOuput = [](VPUIP::NCEClusterTilingOp tilingCopyOp) {
        auto tilingCopyOutput = tilingCopyOp.getOutputs()[0];
        auto tilingCopyOutputType = VPUIP::extractDataType(tilingCopyOutput).cast<vpux::NDTypeInterface>();

        const auto outReqs = StrideReqs::compact(tilingCopyOutputType.getRank());
        return !outReqs.checkStrides(tilingCopyOutputType);
    };

    auto wrapperOp = origOp->getParentOfType<VPUIP::NCEClusterTilingOp>();
    if (wrapperOp == nullptr) {
        return nullptr;
    }
    auto parentSubViewOp = wrapperOp.getInputs()[0].getDefiningOp<VPUIP::SubViewOp>();
    if (parentSubViewOp == nullptr) {
        return nullptr;
    }
    auto topBuffer = parentSubViewOp.getSource();

    if (!checkCMXFit(topBuffer)) {
        return nullptr;
    }

    if (topBuffer.hasOneUse()) {
        return nullptr;
    }

    // Calculate the new required cmx size for user op, since the new input will be
    // changed into SEG|DUP instead of SEG
    auto allUserOpsCanFitCMX = llvm::all_of(wrapperOp->getUsers(), [&](auto user) {
        Byte requiredCMX = VPUIP::getRequiredCMXSize(user);

        // replace the original operand's required cmx size with new one
        requiredCMX -= getTotalSize(wrapperOp->getResult(0));
        requiredCMX += getTotalSize(topBuffer);
        return requiredCMX <= Byte(_cmxSize);
    });
    if (!allUserOpsCanFitCMX) {
        return nullptr;
    }

    auto topBufferUsers = topBuffer.getUsers();
    for (auto user : topBufferUsers) {
        if (!user->hasOneUse()) {
            return nullptr;
        }
        auto anotherSubView = mlir::dyn_cast<VPUIP::SubViewOp>(user);
        if (anotherSubView == nullptr || !VPUIP::isOpOnlySplitOnDim(anotherSubView, Dims4D::Act::N)) {
            return nullptr;
        }
        auto tilingCopy = mlir::dyn_cast<VPUIP::NCEClusterTilingOp>(*anotherSubView.getResult().getUsers().begin());
        if (tilingCopy == nullptr || !isTilingCopyOpSegmentedOnN(tilingCopy) ||
            doesTilingCopyOpHasStridedOuput(tilingCopy)) {
            return nullptr;
        }
    }

    return topBuffer;
}

//
// fuseLastCopy
//

template <typename OpTy>
mlir::Value replaceCastWith(mlir::Operation* op, mlir::Value sourceRoot, mlir::Value inputValue) {
    mlir::OpBuilder builder(op);
    builder.setInsertionPoint(sourceRoot.getDefiningOp());
    auto newOperation = builder.create<OpTy>(op->getLoc(), sourceRoot.getType(), inputValue);
    return newOperation.getResult();
};

void fuseLastCopy(VPUIP::CopyOp copyOp, const AliasesInfo& aliasesInfo, Logger log) {
    log.trace("fuseLastCopy: Copy at {0}", copyOp->getLoc());
    auto nestedLogger = log.nest();

    auto inSourceMemory = copyOp.getInput().getType().cast<vpux::NDTypeInterface>().getMemoryKind();
    auto outSourceMemory = copyOp.getOutput().getType().cast<vpux::NDTypeInterface>().getMemoryKind();
    if (inSourceMemory != outSourceMemory) {
        nestedLogger.trace("Cannot match because the copy is not within the same memory space");
        return;
    }

    auto sourceOp = copyOp.getInput().getDefiningOp();
    if (sourceOp == nullptr) {
        nestedLogger.trace("Cannot match because copy input is a block argument");
        return;
    }

    const auto sourceRoots = aliasesInfo.getRoots(copyOp.getInput());
    mlir::Value sourceRoot = nullptr;
    if (sourceRoots.size() == 1) {
        sourceRoot = *sourceRoots.begin();
    } else if (sourceRoots.size() > 1) {
        mlir::Operation* sourceRootCandidate = nullptr;
        for (auto root : sourceRoots) {
            if (!root.hasOneUse()) {
                nestedLogger.trace("Cannot match because one of the roots has multiple uses : '{0}'", root);
                return;
            }
            auto firstConsumer = *root.getUsers().begin();
            auto groupedViewOp = mlir::dyn_cast<vpux::GroupedViewOpInterface>(firstConsumer);
            if (groupedViewOp == nullptr) {
                nestedLogger.trace("The consumer of a source is not a GroupedViewOp: {0}", firstConsumer->getName());
                return;
            }
            if (sourceRootCandidate == nullptr) {
                sourceRootCandidate = groupedViewOp;
            }
            if (sourceRootCandidate != groupedViewOp) {
                nestedLogger.trace(
                        "Cannot match because roots do not share common GroupedViewOp. Expected '{0}', but got '{1}'",
                        sourceRootCandidate, groupedViewOp);
                return;
            }
        }
        sourceRoot = sourceRootCandidate->getResult(0);
    }
    if (sourceRoot == nullptr) {
        nestedLogger.trace("Cannot match because of unexpected root of pattern");
        return;
    }

    if (sourceRoot.isa<mlir::BlockArgument>()) {
        nestedLogger.trace("Cannot match because input also is block argument");
        return;
    }

    auto sourceRootOp = sourceRoot.getDefiningOp();
    if (!isBufAllocOp(sourceRootOp) && !mlir::isa<VPUIP::GroupSparseBufferOp>(sourceRootOp)) {
        nestedLogger.trace("Cannot match because input isn't allocate op: '{0}'", sourceRootOp->getName());
        return;
    }

    auto allRootAliases = aliasesInfo.getAllAliases(*sourceRoots.begin());
    for (auto alias : allRootAliases) {
        for (auto userOp : alias.getUsers()) {
            if (auto copyUserOp = mlir::dyn_cast<VPUIP::CopyOp>(userOp)) {
                if (copyUserOp != copyOp && copyUserOp.getOutputBuff().isa<mlir::BlockArgument>()) {
                    nestedLogger.trace("Cannot fuse when there are multiple output copy operations");
                    return;
                }
            }
        }
    }

    VPUIP::ConcatViewOp concatViewOp;
    auto newBuffer = copyOp.getOutputBuff();
    auto newOutput = copyOp.getInput();

    if (sourceRoot.getType() != copyOp.getOutputBuff().getType()) {
        // check what operation changes the type
        auto typeCastOp = copyOp.getInput().getDefiningOp();

        if (typeCastOp == nullptr || std::distance(typeCastOp->getUsers().begin(), typeCastOp->getUsers().end()) != 1) {
            // skip if typeCastOp has multi users
            return;
        }

        if (mlir::isa<VPUIP::GenericReshapeOp, VPUIP::QuantizeCastOp>(typeCastOp)) {
            auto preOfTypeCastOp = typeCastOp->getOperand(0).getDefiningOp();
            while (mlir::isa<VPUIP::GenericReshapeOp, VPUIP::QuantizeCastOp, VPUIP::PermuteCastOp>(preOfTypeCastOp)) {
                if (!preOfTypeCastOp->hasOneUse()) {
                    return;
                }
                typeCastOp = preOfTypeCastOp;
                preOfTypeCastOp = preOfTypeCastOp->getOperand(0).getDefiningOp();
            }
            if (!mlir::isa<VPUIP::ConcatViewOp, VPUIP::NCEClusterTilingOp>(preOfTypeCastOp)) {
                nestedLogger.trace("Cannot match because of missed concat/clusterTiling in case");
                return;
            }
            concatViewOp = mlir::dyn_cast<VPUIP::ConcatViewOp>(preOfTypeCastOp);
            if (concatViewOp && !concatViewOp.getOutput().hasOneUse()) {
                return;
            }
        }

        // we will make a OpTy(QuantizeCast/GenericReshape) over the output buffer and we will copy from CMX directly
        // to output buffer, and we will return the output buffer. After ConcatView and OpTy will be redundant.
        // from CMX -> CopyOp[DDR] -> (ConcatViewOp) -> OpTy -> CopyOp[block-arg] -> return CopyOp
        // Output of this step:
        //                        CMX -> CopyOp[OpTy] -> return block-arg
        //   block-arg -> OpTy /
        if (mlir::isa<VPUIP::GenericReshapeOp>(typeCastOp)) {
            newBuffer = replaceCastWith<VPUIP::GenericReshapeOp>(typeCastOp, sourceRoot, copyOp.getOutputBuff());
        } else if (mlir::isa<VPUIP::QuantizeCastOp>(typeCastOp)) {
            newBuffer = replaceCastWith<VPUIP::QuantizeCastOp>(typeCastOp, sourceRoot, copyOp.getOutputBuff());
        } else if (auto permuteCastOp = mlir::dyn_cast<VPUIP::PermuteCastOp>(typeCastOp)) {
            // do the permute in output
            mlir::OpBuilder builder(permuteCastOp);
            builder.setInsertionPoint(sourceRoot.getDefiningOp());

            auto newPermuteCast = builder.create<VPUIP::PermuteCastOp>(
                    permuteCastOp.getLoc(), sourceRoot.getType(), copyOp.getOutputBuff(),
                    permuteCastOp.getDstOrderAttr(), permuteCastOp.getMemPermAttr());

            newBuffer = newPermuteCast.getResult();
        } else {
            nestedLogger.trace("Cannot match because of missed concat in generic branch");
            return;
        }

        auto childTypeCast = *typeCastOp->getResult(0).getUsers().begin();
        if (mlir::isa<VPUIP::GenericReshapeOp, VPUIP::QuantizeCastOp, VPUIP::PermuteCastOp>(typeCastOp)) {
            childTypeCast->setOperand(0, newBuffer);
        }
        typeCastOp->replaceAllUsesWith(typeCastOp->getOperands());
        typeCastOp->erase();
        newOutput = copyOp.getOutputBuff();
    }

    // Function outputs have to be an alias of the output buffer
    log.trace("Root of the copy operation input {0}", sourceRoot);
    log.trace("Reassign outputs from {0} to {1}", sourceRoot, newBuffer);

    for (auto& use : llvm::make_early_inc_range(sourceRoot.getUses())) {
        log.nest().trace("Got user {0}", use.getOwner()->getName());
        log.nest().trace("Reassign {0} to {1}", use.get(), newBuffer);
        use.set(newBuffer);
    }

    copyOp.replaceAllUsesWith(newOutput);
    copyOp->erase();
    if (concatViewOp) {
        concatViewOp->erase();
    }

    if (sourceRootOp->use_empty()) {
        sourceRootOp->erase();
    }
}

//
// OptimizeCopiesPass
//

class OptimizeCopiesPass final : public VPUIP::OptimizeCopiesBase<OptimizeCopiesPass> {
public:
    explicit OptimizeCopiesPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
};

//
// safeRunOnFunc
//

void OptimizeCopiesPass::safeRunOnFunc() {
    auto& ctx = getContext();
    auto func = getOperation();

    auto module = func->getParentOfType<mlir::ModuleOp>();
    auto cmxSize = VPU::getTotalCMXSize(module).count();

    // Note the below patterns exec order is defined by "benefitLevels" at the head
    mlir::RewritePatternSet patterns(&ctx);
    patterns.add<CopyOpSequence>(&ctx, benefitLevels[0], _log);
    patterns.add<NCEClusterCopyOpSequence>(&ctx, benefitLevels[0], _log);
    patterns.add<CMXToCMXCopy>(&ctx, benefitLevels[1], _log);
    patterns.add<DDRToDDRCopyOfNCECluster>(&ctx, benefitLevels[2], _log);
    patterns.add<ConcatViewWithCopy>(&ctx, benefitLevels[3], _log);
    patterns.add<ConcatViewWithTilingCopy>(&ctx, benefitLevels[3], _log);
    patterns.add<FuseCopyToTheFrontOfTillingCopy>(&ctx, benefitLevels[3], _log);
    patterns.add<SubViewWithCopyBase>(&ctx, benefitLevels[3], cmxSize, _log);

    if (mlir::failed(mlir::applyPatternsAndFoldGreedily(func, std::move(patterns), getDefaultGreedyRewriteConfig()))) {
        signalPassFailure();
    }

    func->walk([&](VPUIP::CopyOp op) {
        if (!op.getOutputBuff().isa<mlir::BlockArgument>()) {
            return;
        }

        auto& aliasInfo = getAnalysis<AliasesInfo>();
        fuseLastCopy(op, aliasInfo, _log);
    });
}

}  // namespace

//
// createOptimizeCopiesPass
//

std::unique_ptr<mlir::Pass> vpux::VPUIP::createOptimizeCopiesPass(Logger log) {
    return std::make_unique<OptimizeCopiesPass>(log);
}
