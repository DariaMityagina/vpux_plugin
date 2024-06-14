//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPUIP/transforms/passes.hpp"

#include "vpux/compiler/core/reserved_memory_info.hpp"

#include "vpux/compiler/utils/rewriter.hpp"

#include "vpux/utils/core/logger.hpp"

using namespace vpux;

namespace {

//
// QueryArgsAllocationAnalysisPass
//

class QueryArgsAllocationAnalysisPass final :
        public VPUIP::QueryArgsAllocationAnalysisBase<QueryArgsAllocationAnalysisPass> {
public:
    QueryArgsAllocationAnalysisPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnModule() final;
};

void QueryArgsAllocationAnalysisPass::safeRunOnModule() {
    std::ignore = getAnalysis<ReservedMemInfo>();
    markAllAnalysesPreserved();
}

}  // namespace

std::unique_ptr<mlir::Pass> vpux::VPUIP::createQueryArgsAllocationAnalysisPass(Logger log) {
    return std::make_unique<QueryArgsAllocationAnalysisPass>(log);
}
