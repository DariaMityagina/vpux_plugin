//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/VPU37XX/core/pipelines_options.hpp"

#include "vpux/compiler/dialect/VPUIP/passes.hpp"
#include "vpux/compiler/dialect/VPUIP/pipelines_options.hpp"

namespace vpux {
namespace VPUIP {
namespace arch37xx {

//
// Passes
//

std::unique_ptr<mlir::Pass> createAddSwKernelCacheHandlingOpsPass(Logger log = Logger::global());
std::unique_ptr<mlir::Pass> createUnrollClusterTilingPass(Logger log = Logger::global());

//
// Memory allocation pipeline
//

struct MemoryAllocationOptions final : public VPUIP::MemoryAllocationOptionsBase {
    MemoryAllocationOptions() = default;

    template <class OtherOptions>
    explicit MemoryAllocationOptions(const OtherOptions& options): MemoryAllocationOptionsBase(options) {
    }
};

void buildMemoryAllocationPipeline(mlir::OpPassManager& pm, const MemoryAllocationOptions& options,
                                   Logger log = Logger::global());

//
// DefaultHWOptions
//

struct DefaultHWOptions :
        public VPUIP::DefaultHWOptionsDialectBase,
        virtual vpux::arch37xx::DefaultHWOptionsDeviceBase {
    BoolOption enableDMAProfiling{*this, "dma-profiling", llvm::cl::desc("Enable DMA task profiling"),
                                  llvm::cl::init(true)};

    BoolOption enableCompressWeightsBTC{*this, "compress-weights-btc", ::llvm::cl::desc("Enable compress-weights pass"),
                                        ::llvm::cl::init(false)};

    BoolOption enableWeightsSwizzling{*this, "enable-weights-swizzling", ::llvm::cl::desc("Enable weights swizzling"),
                                      ::llvm::cl::init(true)};

    BoolOption enableActivationSwizzling{*this, "enable-activation-swizzling",
                                         ::llvm::cl::desc("Enable activation swizzling"), ::llvm::cl::init(true)};
};

void buildDefaultHWPipeline(mlir::OpPassManager& pm, const DefaultHWOptions& options, Logger log = Logger::global());

//
// registerVPUIPPipelines
//

void registerVPUIPPipelines();

//
// Generated
//

#define GEN_PASS_CLASSES
#include <vpux/compiler/VPU37XX/dialect/VPUIP/passes.hpp.inc>
#undef GEN_PASS_CLASSES

#define GEN_PASS_REGISTRATION
#include <vpux/compiler/VPU37XX/dialect/VPUIP/passes.hpp.inc>
#undef GEN_PASS_REGISTRATION

}  // namespace arch37xx
}  // namespace VPUIP
}  // namespace vpux
