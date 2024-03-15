//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/VPU37XX/interfaces_registry.hpp"
#include <mlir/IR/DialectRegistry.h>

#include "vpux/compiler/VPU37XX/conversion/passes/VPU2VPUIP/bufferizable_op_interface.hpp"
#include "vpux/compiler/VPU37XX/dialect/IE/ops_interfaces.hpp"
#include "vpux/compiler/VPU37XX/dialect/VPU/IR/ops_interfaces.hpp"
#include "vpux/compiler/VPU37XX/dialect/VPUIP/ops_interfaces.hpp"

namespace vpux {

void InterfacesRegistry37XX::registerInterfaces(mlir::DialectRegistry& registry) {
    IE::arch37xx::registerElemTypeInfoOpInterfaces(registry);
    VPU::arch37xx::registerLayerWithPostOpModelInterface(registry);
    VPU::arch37xx::registerLayoutInfoOpInterfaces(registry);
    VPU::arch37xx::registerDDRAccessOpModelInterface(registry);
    VPUIP::arch37xx::registerAlignedChannelsOpInterfaces(registry);
    VPUIP::arch37xx::registerAlignedWorkloadChannelsOpInterfaces(registry);
    vpux::arch37xx::registerBufferizableOpInterfaces(registry);
}

}  // namespace vpux
