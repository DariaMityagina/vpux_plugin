//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/utils/resources.hpp"
#include "vpux/compiler/dialect/VPUIP/passes.hpp"
#include "vpux/compiler/utils/compression_utils.hpp"

using namespace vpux;

namespace {

//
//  CompressDmaReserveMemPass
//

class CompressDmaReserveMemPass final : public VPUIP::CompressDmaReserveMemBase<CompressDmaReserveMemPass> {
public:
    explicit CompressDmaReserveMemPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnModule() final;
};

void CompressDmaReserveMemPass::safeRunOnModule() {
    auto module = getOperation();
    auto* ctx = module->getContext();

    auto memSpaceAttr = mlir::SymbolRefAttr::get(ctx, stringifyEnum(VPU::MemoryKind::CMX_NN));

    _log.trace("Compressed DMA reserved memory - size: '{0}'", ACT_COMPRESSION_RESERVED_MEM_SIZE);

    IE::setCompressDmaReservedMemory(module, memSpaceAttr, ACT_COMPRESSION_RESERVED_MEM_SIZE);
}

}  // namespace

//
// createCompressDmaReserveMemPass
//

std::unique_ptr<mlir::Pass> vpux::VPUIP::createCompressDmaReserveMemPass(Logger log) {
    return std::make_unique<CompressDmaReserveMemPass>(log);
}
