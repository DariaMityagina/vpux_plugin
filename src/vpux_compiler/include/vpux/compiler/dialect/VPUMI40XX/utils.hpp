//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPUMI40XX/ops.hpp"
#include "vpux/compiler/dialect/VPUMI40XX/ops_interfaces.hpp"

namespace vpux {
namespace VPUMI40XX {

enum class DmaNnSrcType { DDR, CMX_NN, Count };

uint64_t computeMaskHi(mlir::ArrayAttr barriers);
uint64_t computeMaskLo(mlir::ArrayAttr barriers);
bool isConfigureBarrierOpType(const mlir::Operation::operand_range& barriers);

constexpr std::pair<size_t, size_t> compute_dma_split(size_t ddr_tasks, size_t cmx_tasks) {
    // [task with CMX src]                       //
    // ^         /                           . ' //
    // |        /                        . '     //
    // |   C   /                     . '         //
    // |      /                  . '             //
    // |     /      B        . '                 //
    // |    /            . '                     //
    // |   /         . '                         //
    // |  /      . '             A               //
    // | /   . '                                 //
    // |/. '                                     //
    // +---------------------------------------> //
    //                      [tasks with DDR src] //

    return ddr_tasks > 2 * cmx_tasks ? std::make_pair(size_t{64}, size_t{16}) :         // A
                   cmx_tasks > ddr_tasks * 2 ? std::make_pair(size_t{16}, size_t{64})   // C
                                             : std::make_pair(size_t{32}, size_t{32});  // B
}

MappedInferenceOp getMPI(mlir::func::FuncOp mainFunc);

// Update indexes in list of operations
size_t reindexList(VPURegMapped::TaskOpInterface head);
VPURegMapped::ExecutionGroupOp getNextGroup(VPURegMapped::ExecutionGroupOp op);

void printIndex(llvm::raw_ostream& os, VPURegMapped::IndexType index, llvm::StringRef head, llvm::StringRef middle,
                llvm::StringRef end);
bool checkBarrierProductionRelationship(mlir::Operation* barr, VPUMI40XX::ExecutableTaskOpInterface exec);

template <typename T>
T getNextOp(T op) {
    auto users = op.getResult().getUsers();
    auto nextOpIt = llvm::find_if(users, [&op](mlir::Operation* user) {
        auto nextTask = mlir::dyn_cast<T>(user);
        return nextTask && (nextTask.getPreviousTask() == op);
    });

    return llvm::cast_if_present<T>(nextOpIt == users.end() ? nullptr : *nextOpIt);
}

}  // namespace VPUMI40XX
}  // namespace vpux
