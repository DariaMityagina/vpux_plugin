//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/dialect/IE/passes.hpp"

#include "vpux/utils/core/func_ref.hpp"
#include "vpux/utils/core/numeric.hpp"
namespace vpux {

//
// calcPadsEnd
//

Shape calcPadsEnd(ShapeRef origShape, ShapeRef extendedShape);
Shape calcPadsEnd(vpux::NDTypeInterface origType, int64_t channelAlignment);

mlir::Value expandChannelWithOffset(mlir::PatternRewriter& rewriter, mlir::Operation* origOp, IE::SliceOp sliceOp,
                                    mlir::Value expandValue, ShapeRef inPadsEnd);
mlir::Value paddingActivation(mlir::Operation* origOp, mlir::PatternRewriter& rewriter, mlir::Value expandValue,
                              ShapeRef filterPadsEnd);
mlir::Value paddingFilter(mlir::Operation* origOp, mlir::PatternRewriter& rewriter, mlir::Value expandValue,
                          Shape filterPadsEnd);
SmallVector<int64_t> extractMeaningfulOutput(mlir::Operation* origOp, Shape outPadsEnd);

//
// generalRewrite
//

//
// Max/Avg Pooling and Convolution Ops should be handled there
//
// opCreator - function, which should place back operation, which being proceed, with new expanded input
// calcOutputSliceOffset - function, calcualte output slice offset, it's different for Conv and per-channel ops
//

mlir::LogicalResult generalRewrite(mlir::Operation* origOp, mlir::PatternRewriter& rewriter,
                                   FuncRef<mlir::Operation*(mlir::Value, int64_t)> opCreator,
                                   FuncRef<SmallVector<int64_t>(mlir::Operation*, Shape)> calcOutputSliceOffset,
                                   Logger log);

namespace IE {

//
// MaxPoolRewriter
//

class MaxPoolRewriter final : public mlir::OpRewritePattern<IE::MaxPoolOp> {
public:
    MaxPoolRewriter(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::MaxPoolOp>(ctx), _log(log) {
        setDebugName("MaxPoolRewriter");
    }

    mlir::LogicalResult matchAndRewrite(IE::MaxPoolOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

//
// ConvolutionRewriter
//

class ConvolutionRewriter final : public mlir::OpRewritePattern<IE::ConvolutionOp> {
public:
    ConvolutionRewriter(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::ConvolutionOp>(ctx), _log(log) {
        setDebugName("ConvolutionRewriter");
    }

    mlir::LogicalResult matchAndRewrite(IE::ConvolutionOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

//
// EltwiseRewriter
//

template <class ConcreteOp>
class EltwiseRewriter final : public mlir::OpRewritePattern<ConcreteOp> {
public:
    EltwiseRewriter(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<ConcreteOp>(ctx), _log(log) {
        this->setDebugName("EltwiseRewriter");
    }

    mlir::LogicalResult matchAndRewrite(ConcreteOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

template <class ConcreteOp>
mlir::LogicalResult EltwiseRewriter<ConcreteOp>::matchAndRewrite(ConcreteOp origOp,
                                                                 mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Got eltwise layer at '{1}'", this->getDebugName(), origOp->getLoc());

    const auto opCreator = [&](mlir::Value expandedInput1, int64_t outChanPadEnd) -> mlir::Operation* {
        mlir::Value expandedInput2;
        if (origOp.getInput1() == origOp.getInput2()) {
            expandedInput2 = expandedInput1;
        } else if (outChanPadEnd == 0) {
            expandedInput2 = origOp.getInput2();
        } else {
            _log.trace("Expand second input tensor");

            const auto origShape = getShape(origOp.getInput2());
            const auto extendedShape = getShape(expandedInput1);
            VPUX_THROW_UNLESS(origShape.size() == extendedShape.size(), "Got non equal shapes in EltwiseRewriter");

            const auto padsEnd = calcPadsEnd(origShape, extendedShape);

            auto sliceOp = origOp.getInput1().template getDefiningOp<IE::SliceOp>();
            expandedInput2 = expandChannelWithOffset(rewriter, origOp, sliceOp, origOp.getInput2(), padsEnd);
        }

        const Shape outPadBefore(checked_cast<size_t>(origOp.getType().getRank()), 0);

        Shape outPadAfter(checked_cast<size_t>(origOp.getType().getRank()), 0);
        outPadAfter[Dims4D::Act::C] = outChanPadEnd;

        const auto ndType = origOp.getType().template cast<vpux::NDTypeInterface>();
        const auto newOutputType = ndType.pad(outPadBefore, outPadAfter);

        return rewriter.create<ConcreteOp>(origOp.getLoc(), newOutputType, expandedInput1, expandedInput2,
                                           origOp.getAutoBroadcast(), origOp.getPostOpAttr(), origOp.getClampAttr());
    };

    return generalRewrite(origOp, rewriter, opCreator, extractMeaningfulOutput, _log.nest());
}

//
// GroupConvolutionRewriter
//

class GroupConvolutionRewriter final : public mlir::OpRewritePattern<IE::GroupConvolutionOp> {
public:
    GroupConvolutionRewriter(mlir::MLIRContext* ctx, Logger log)
            : mlir::OpRewritePattern<IE::GroupConvolutionOp>(ctx), _log(log) {
        setDebugName("GroupConvolutionRewriter");
    }

    mlir::LogicalResult matchAndRewrite(IE::GroupConvolutionOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

//
// InterpolateRewriter
//

class InterpolateRewriter final : public mlir::OpRewritePattern<IE::InterpolateOp> {
public:
    InterpolateRewriter(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::InterpolateOp>(ctx), _log(log) {
        setDebugName("InterpolateRewriter");
    }

    mlir::LogicalResult matchAndRewrite(IE::InterpolateOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

//
// TransposedConvolutionRewriter
//

class TransposedConvolutionRewriter final : public mlir::OpRewritePattern<IE::TransposedConvolutionOp> {
public:
    TransposedConvolutionRewriter(mlir::MLIRContext* ctx, Logger log)
            : mlir::OpRewritePattern<IE::TransposedConvolutionOp>(ctx), _log(log) {
        setDebugName("TransposedConvolutionRewriter");
    }

    mlir::LogicalResult matchAndRewrite(IE::TransposedConvolutionOp origOp,
                                        mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

}  // namespace IE
}  // namespace vpux
