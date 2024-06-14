//
// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: Apache-2.0
//
#include "vpux/compiler/NPU37XX/dialect/IE/transforms/passes.hpp"
#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/dialect/IE/utils/permute_quantize_utils.hpp"
#include "vpux/compiler/utils/permute_utils.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

#include "vpux/utils/core/enums.hpp"

#include <mlir/Dialect/Quant/QuantTypes.h>
#include <mlir/IR/PatternMatch.h>
#include <mlir/Transforms/GreedyPatternRewriteDriver.h>

using namespace vpux;

namespace {
class FusePermuteQuantizeExpandBase : public mlir::OpRewritePattern<IE::ReorderOp> {
public:
    FusePermuteQuantizeExpandBase(mlir::MLIRContext* ctx, Logger log)
            : mlir::OpRewritePattern<IE::ReorderOp>(ctx, benefitHigh), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(IE::ReorderOp origOp, mlir::PatternRewriter& rewriter) const final;
    virtual bool isLegalPattern(IE::ReorderOp origOp) const = 0;
    virtual void replaceByNewOp(mlir::Operation* opNce, mlir::Value input, mlir::PatternRewriter& rewriter) const = 0;
    virtual mlir::Type getNceOutType(mlir::Operation* opNce) const = 0;

private:
    Logger _log;
};

mlir::LogicalResult FusePermuteQuantizeExpandBase::matchAndRewrite(IE::ReorderOp origOp,
                                                                   mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Got '{1}' at '{2}'", getDebugName(), origOp->getName(), origOp->getLoc());
    auto opExpand = origOp.getInput().getDefiningOp<IE::ExpandOp>();
    if (opExpand == nullptr) {
        return mlir::failure();
    }
    if (!opExpand.getResult().hasOneUse()) {
        return mlir::failure();
    }

    if (origOp.getOutput().use_empty()) {
        return mlir::failure();
    }

    // check reorder and nce pattern
    if (!isLegalPattern(origOp)) {
        return mlir::failure();
    }

    auto opNce = *origOp.getOutput().getUsers().begin();
    const auto inType = opNce->getOperand(0).getType().cast<vpux::NDTypeInterface>().getElementType();
    const auto outType = opNce->getResult(0).getType().cast<vpux::NDTypeInterface>().getElementType();
    if (!(inType.isF16() && outType.isa<mlir::quant::QuantizedType>())) {
        return mlir::failure();
    }

    // check uniform quantize
    const auto qType = outType.cast<mlir::quant::QuantizedType>();
    if (!qType.isa<mlir::quant::UniformQuantizedType>()) {
        return mlir::failure();
    }

    // check if reorder will not be removed
    auto inOrder = DimsOrder::fromValue(origOp.getInput());
    auto outOrder = DimsOrder::fromValue(origOp.getOutput());
    if (inOrder == outOrder) {
        return mlir::failure();
    }
    // check and add pass for verified orders and scenarios
    if (!((inOrder == DimsOrder::NCHW) && (outOrder == DimsOrder::NHWC))) {
        return mlir::failure();
    }
    // allow expand just on C dim, that will be last after reorder.
    const auto iExpType = opExpand.getInput().getType().cast<vpux::NDTypeInterface>();
    const auto oExpType = opExpand.getOutput().getType().cast<vpux::NDTypeInterface>();
    if (iExpType.getShape()[Dims4D::Act::N] != oExpType.getShape()[Dims4D::Act::N]) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::W] != oExpType.getShape()[Dims4D::Act::W]) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::H] != oExpType.getShape()[Dims4D::Act::H]) {
        return mlir::failure();
    }

    // experiments show that shave is far more performant when C == 1, C == 3 or C == 4 than DMA-MemPermute
    if ((iExpType.getShape()[Dims4D::Act::C] != 3) && (iExpType.getShape()[Dims4D::Act::C] != 1) &&
        (iExpType.getShape()[Dims4D::Act::C] != 4)) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::N] != 1) {
        return mlir::failure();
    }

    // input can be fp32, so fuse and convertOp if it is possible.
    auto paternInput = opExpand.getInput();
    auto opReshape = opExpand.getInput().getDefiningOp<IE::AffineReshapeOp>();
    auto opConvert = opExpand.getInput().getDefiningOp<IE::ConvertOp>();
    // first patern when no reshape involve, just fuse ConvertOp
    if (opConvert != nullptr) {
        if (opConvert.getResult().hasOneUse() &&
            opConvert.getInput().getType().cast<vpux::NDTypeInterface>().getElementType().isF32()) {
            paternInput = opConvert.getInput();
        }
    }
    // pattern 2 when we have Convert->Reshape>PermuteQuantizePattern
    // in this case Reshape will be move before ConvertOp
    if (opReshape != nullptr) {
        opConvert = opReshape.getInput().getDefiningOp<IE::ConvertOp>();
        if (opConvert != nullptr) {
            if (opReshape.getResult().hasOneUse() && opConvert.getResult().hasOneUse() &&
                opConvert.getInput().getType().cast<vpux::NDTypeInterface>().getElementType().isF32()) {
                const auto newReshapeOpLoc = appendLoc(origOp->getLoc(), "AffineReshape");
                auto newReshapeOp = rewriter.create<IE::AffineReshapeOp>(newReshapeOpLoc, opConvert.getInput(),
                                                                         opReshape.getDimMappingAttr(),
                                                                         opReshape.getShapeValueAttr());
                paternInput = newReshapeOp.getOutput();
            }
        }
    }

    auto memPermAttr = mlir::AffineMapAttr::get(getPermutationFromOrders(inOrder, outOrder, origOp->getContext()));
    auto permQuantOutType = getNceOutType(opNce);
    const auto permQuantElemType = permQuantOutType.cast<vpux::NDTypeInterface>().getElementType();
    const auto dstElemTypeAttr = mlir::TypeAttr::get(permQuantElemType);
    const auto permQuantLoc = appendLoc(origOp->getLoc(), "PermuteQuantizeExpand");
    auto permuteQuantizeOp = rewriter.create<IE::PermuteQuantizeOp>(
            permQuantLoc, permQuantOutType, paternInput, origOp.getDstOrderAttr(), memPermAttr, dstElemTypeAttr,
            opExpand.getPadsBeginAttr(), opExpand.getPadsEndAttr());

    replaceByNewOp(opNce, permuteQuantizeOp.getOutput(), rewriter);

    return mlir::success();
}

// ======================================================================================
// FusePermuteQuantizeExpandForAdd
//   FusePermuteQuantizeExpandForAdd -> [Expand -> Reorder -> Add -> QuantizeCastOp] -> [PermuteQuantizeExpand
//   -> QuantizeCastOp]

class FusePermuteQuantizeExpandForAdd final : public FusePermuteQuantizeExpandBase {
public:
    FusePermuteQuantizeExpandForAdd(mlir::MLIRContext* ctx, Logger log): FusePermuteQuantizeExpandBase(ctx, log) {
    }

public:
    bool isLegalPattern(IE::ReorderOp origOp) const override;
    void replaceByNewOp(mlir::Operation* opNce, mlir::Value input, mlir::PatternRewriter& rewriter) const override;
    mlir::Type getNceOutType(mlir::Operation* opNce) const override;
};

bool FusePermuteQuantizeExpandForAdd::isLegalPattern(IE::ReorderOp origOp) const {
    return IE::isLegalReorderAddPattern(origOp);
}

mlir::Type FusePermuteQuantizeExpandForAdd::getNceOutType(mlir::Operation* opNce) const {
    // QuantizeToAddRewriter multiplies output scale by 2. It is necessary to cancel out this factor.
    return rescaleUniformQuantizedType(opNce->getResult(0).getType(), 0.5);
}

void FusePermuteQuantizeExpandForAdd::replaceByNewOp(mlir::Operation* opNce, mlir::Value input,
                                                     mlir::PatternRewriter& rewriter) const {
    auto orginalQuantizeCast = mlir::dyn_cast<IE::QuantizeCastOp>(*opNce->getResult(0).getUsers().begin());
    auto quantCast =
            rewriter.create<IE::QuantizeCastOp>(opNce->getLoc(), input, orginalQuantizeCast.getDstElemTypeAttr());
    rewriter.replaceOp(orginalQuantizeCast, quantCast.getOutput());
}

// ======================================================================================
// FusePermuteQuantizeExpandForAvgPool
//   FusePermuteQuantizeExpandForAvgPool -> [Expand -> Reorder -> AvgPool] -> [PermuteQuantizeExpand]

class FusePermuteQuantizeExpandForAvgPool final : public FusePermuteQuantizeExpandBase {
public:
    FusePermuteQuantizeExpandForAvgPool(mlir::MLIRContext* ctx, Logger log): FusePermuteQuantizeExpandBase(ctx, log) {
    }

public:
    bool isLegalPattern(IE::ReorderOp origOp) const override;
    void replaceByNewOp(mlir::Operation* opNce, mlir::Value input, mlir::PatternRewriter& rewriter) const override;
    mlir::Type getNceOutType(mlir::Operation* opNce) const override;
};

bool FusePermuteQuantizeExpandForAvgPool::isLegalPattern(IE::ReorderOp origOp) const {
    return IE::isLegalReorderAvgPoolPattern(origOp);
}

mlir::Type FusePermuteQuantizeExpandForAvgPool::getNceOutType(mlir::Operation* opNce) const {
    return opNce->getResult(0).getType();
}

void FusePermuteQuantizeExpandForAvgPool::replaceByNewOp(mlir::Operation* opNce, mlir::Value input,
                                                         mlir::PatternRewriter& rewriter) const {
    rewriter.replaceOp(opNce, input);
}

// ======================================================================================
// FuseExpandIntoPermuteQuantizeRewrite
//   FuseExpandIntoPermuteQuantizeRewrite -> [PermuteQuantize -> Expand ] -> PermuteQuantizeExpand

class FuseExpandIntoPermuteQuantizeRewrite final : public mlir::OpRewritePattern<IE::ExpandOp> {
public:
    FuseExpandIntoPermuteQuantizeRewrite(mlir::MLIRContext* ctx, Logger log)
            : mlir::OpRewritePattern<IE::ExpandOp>(ctx, benefitHigh), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(IE::ExpandOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult FuseExpandIntoPermuteQuantizeRewrite::matchAndRewrite(IE::ExpandOp origOp,
                                                                          mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Got '{1}' at '{2}'", getDebugName(), origOp->getName(), origOp->getLoc());

    // check patern
    auto opPermuteQuantize = origOp.getInput().getDefiningOp<IE::PermuteQuantizeOp>();
    if (opPermuteQuantize == nullptr) {
        return mlir::failure();
    }
    if (!opPermuteQuantize.getResult().hasOneUse()) {
        return mlir::failure();
    }

    // alow expand just on C dim, that will be last after reoreder.
    const auto iExpType = origOp.getInput().getType().cast<vpux::NDTypeInterface>();
    const auto oExpType = origOp.getOutput().getType().cast<vpux::NDTypeInterface>();
    if (!((4 == iExpType.getRank()) && (4 == oExpType.getRank()))) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::N] != oExpType.getShape()[Dims4D::Act::N]) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::W] != oExpType.getShape()[Dims4D::Act::W]) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::H] != oExpType.getShape()[Dims4D::Act::H]) {
        return mlir::failure();
    }

    auto permuteQuantizeOp = rewriter.create<IE::PermuteQuantizeOp>(
            origOp->getLoc(), opPermuteQuantize.getInput(), opPermuteQuantize.getDstOrderAttr(),
            opPermuteQuantize.getMemPermAttr(), opPermuteQuantize.getDstElemTypeAttr(), origOp.getPadsBeginAttr(),
            origOp.getPadsEndAttr());
    rewriter.replaceOp(origOp, permuteQuantizeOp.getOutput());

    return mlir::success();
}

// ======================================================================================
// FuseQuantizeCastExpandIntoPermuteQuantizeQuantizeCastRewrite
//   FuseQuantizeCastExpandIntoPermuteQuantizeQuantizeCastRewrite -> [PermuteQuantize-> QuantizeCast -> Expand] ->
//   PermuteQuantizeExpand->QuantizeCast

class FuseQuantizeCastExpandIntoPermuteQuantizeQuantizeCastRewrite final : public mlir::OpRewritePattern<IE::ExpandOp> {
public:
    FuseQuantizeCastExpandIntoPermuteQuantizeQuantizeCastRewrite(mlir::MLIRContext* ctx, Logger log)
            : mlir::OpRewritePattern<IE::ExpandOp>(ctx, benefitHigh), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(IE::ExpandOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult FuseQuantizeCastExpandIntoPermuteQuantizeQuantizeCastRewrite::matchAndRewrite(
        IE::ExpandOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Got '{1}' at '{2}'", getDebugName(), origOp->getName(), origOp->getLoc());

    // check patern
    auto opQuantizeCast = origOp.getInput().getDefiningOp<IE::QuantizeCastOp>();
    if (opQuantizeCast == nullptr) {
        return mlir::failure();
    }
    auto opPermuteQuantize = opQuantizeCast.getInput().getDefiningOp<IE::PermuteQuantizeOp>();
    if (opPermuteQuantize == nullptr) {
        return mlir::failure();
    }
    if (!opQuantizeCast.getResult().hasOneUse()) {
        return mlir::failure();
    }
    if (!opPermuteQuantize.getResult().hasOneUse()) {
        return mlir::failure();
    }

    // alow expand just on C dim, that will be last after reoreder.
    const auto iExpType = origOp.getInput().getType().cast<vpux::NDTypeInterface>();
    const auto oExpType = origOp.getOutput().getType().cast<vpux::NDTypeInterface>();
    if (!((4 == iExpType.getRank()) && (4 == oExpType.getRank()))) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::N] != oExpType.getShape()[Dims4D::Act::N]) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::W] != oExpType.getShape()[Dims4D::Act::W]) {
        return mlir::failure();
    }
    if (iExpType.getShape()[Dims4D::Act::H] != oExpType.getShape()[Dims4D::Act::H]) {
        return mlir::failure();
    }

    auto permuteQuantizeOp = rewriter.create<IE::PermuteQuantizeOp>(
            origOp->getLoc(), opPermuteQuantize.getInput(), opPermuteQuantize.getDstOrderAttr(),
            opPermuteQuantize.getMemPermAttr(), opPermuteQuantize.getDstElemTypeAttr(), origOp.getPadsBeginAttr(),
            origOp.getPadsEndAttr());
    auto quantizeCastOp = rewriter.create<IE::QuantizeCastOp>(origOp.getLoc(), permuteQuantizeOp.getResult(),
                                                              opQuantizeCast.getDstElemTypeAttr());

    rewriter.replaceOp(origOp, quantizeCastOp.getOutput());

    return mlir::success();
}

//
// FusePermuteQuantizeExpandPass
//

class FusePermuteQuantizeExpandPass final :
        public IE::arch37xx::FusePermuteQuantizeExpandBase<FusePermuteQuantizeExpandPass> {
public:
    explicit FusePermuteQuantizeExpandPass(Logger log): _log(log) {
        _log.setName(Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;

private:
    Logger _log;
};

void FusePermuteQuantizeExpandPass::safeRunOnFunc() {
    auto& ctx = getContext();
    auto func = getOperation();

    mlir::RewritePatternSet patterns(&ctx);
    patterns.add<FusePermuteQuantizeExpandForAdd>(&ctx, _log);
    patterns.add<FusePermuteQuantizeExpandForAvgPool>(&ctx, _log);
    patterns.add<FuseExpandIntoPermuteQuantizeRewrite>(&ctx, _log);
    patterns.add<FuseQuantizeCastExpandIntoPermuteQuantizeQuantizeCastRewrite>(&ctx, _log);

    if (mlir::failed(applyPatternsAndFoldGreedily(func, std::move(patterns), getDefaultGreedyRewriteConfig()))) {
        signalPassFailure();
    }
}

}  // namespace

//
// createFusePermuteQuantizeExpandPass
//
std::unique_ptr<mlir::Pass> vpux::IE::arch37xx::createFusePermuteQuantizeExpandPass(Logger log) {
    return std::make_unique<FusePermuteQuantizeExpandPass>(log);
}
