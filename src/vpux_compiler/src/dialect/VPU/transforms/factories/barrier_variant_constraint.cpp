//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/NPU37XX/dialect/VPU/impl/barrier_variant_constraint.hpp"
#include "vpux/compiler/NPU40XX/dialect/VPU/impl/barrier_variant_constraint.hpp"
#include "vpux/compiler/dialect/VPU/transforms/factories/barrier_variant_constraint.hpp"

#include "vpux/utils/core/error.hpp"

using namespace vpux;

VPU::PerBarrierVariantConstraint VPU::getPerBarrierVariantConstraint(VPU::ArchKind arch,
                                                                     bool enablePartialWorkloadManagement) {
    switch (arch) {
    case VPU::ArchKind::NPU37XX: {
        return VPU::arch37xx::PerBarrierVariantConstraint{};
    }
    case VPU::ArchKind::NPU40XX: {
        return VPU::arch40xx::PerBarrierVariantConstraint{enablePartialWorkloadManagement};
    }
    case VPU::ArchKind::UNKNOWN:
    default: {
        VPUX_THROW("Unexpected architecture {0}", arch);
    }
    }
}
