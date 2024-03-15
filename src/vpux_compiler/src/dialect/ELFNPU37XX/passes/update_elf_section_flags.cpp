//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/ELFNPU37XX/passes.hpp"

using namespace vpux;

namespace {

class UpdateELFSectionFlagsPass final : public ELFNPU37XX::UpdateELFSectionFlagsBase<UpdateELFSectionFlagsPass> {
public:
    explicit UpdateELFSectionFlagsPass(Logger log): _log(log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    template <typename OpTy>
    void runOnSectionOps(mlir::func::FuncOp& funcOp) {
        for (auto sectionOp : funcOp.getOps<OpTy>()) {
            auto currFlagsAttrVal = sectionOp.getSecFlags();
            auto tempFlagsAttrVal = currFlagsAttrVal;

            for (auto sectionOpMember : sectionOp.template getOps<ELFNPU37XX::BinaryOpInterface>()) {
                tempFlagsAttrVal = tempFlagsAttrVal | sectionOpMember.getAccessingProcs();
            }

            if (tempFlagsAttrVal != currFlagsAttrVal) {
                sectionOp.setSecFlagsAttr(
                        ELFNPU37XX::SectionFlagsAttrAttr::get(sectionOp.getContext(), tempFlagsAttrVal));
            }
        }
    }

    void safeRunOnModule() final {
        mlir::ModuleOp moduleOp = getOperation();

        IE::CNNNetworkOp cnnOp;
        mlir::func::FuncOp funcOp;
        IE::CNNNetworkOp::getFromModule(moduleOp, cnnOp, funcOp);

        runOnSectionOps<ELFNPU37XX::CreateSectionOp>(funcOp);
        runOnSectionOps<ELFNPU37XX::CreateLogicalSectionOp>(funcOp);
    };

    Logger _log;
};

}  // namespace

std::unique_ptr<mlir::Pass> vpux::ELFNPU37XX::createUpdateELFSectionFlagsPass(Logger log) {
    return std::make_unique<UpdateELFSectionFlagsPass>(log);
}
