//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/core/cost_model_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/cost_model/cost_model.hpp"

#include "vpux/utils/core/dense_map.hpp"
#include "vpux/utils/core/logger.hpp"

namespace vpux {

class CycleCostInfo {
public:
    using CycleCosts = DenseMap<mlir::Operation*, size_t>;

    /**
     * @brief Constructor for CycleCostInfo class.
     *
     * Initializes architecture kind, cost model, and DPU count based on the provided function.
     *
     * @param func The mlir::func::FuncOp representing the function for cycle cost analysis.
     */
    explicit CycleCostInfo(mlir::func::FuncOp);

    /**
     * @brief Checks and stores cycle cost for the operation.
     *
     * If the cycle cost is below a threshold or zero, it updates the cost and logs a warning
     * if the cost is considered invalid.
     *
     * @param cycleCost Reference to the cycle cost value to be checked and stored.
     * @param op The mlir::Operation pointer representing the operation.
     */
    void updateAndStoreInvalidCostCycles(size_t&, mlir::Operation*);

    /**
     * @brief Retrieves the cycle cost for a given operation.
     *
     * Checks if the cost is already cached, otherwise queries the cost model to calculate it.
     *
     * @param op The mlir::Operation pointer representing the operation.
     * @return The calculated cycle cost for the operation.
     */
    size_t getCycleCost(mlir::Operation*);

    inline size_t getNumberOfTasksWithInvalidCost() const {
        return _numOfTasksWithInvalidCost;
    }

    inline std::set<std::string> getLayersWithInvalidCost() const {
        return _layersWithInvalidCost;
    }

    inline std::shared_ptr<VPUNN::VPUCostModel> getCostModel() const {
        return _costModel;
    }

    inline VPU::ArchKind getArchKind() const {
        return _archKind;
    }

private:
    /**
     * @brief Stores the cycle cost for a given operation.
     *
     * Performs a sanity check to ensure that the cost for the operation is not already stored.
     * Calls updateAndStoreInvalidCostCycles to handle invalid costs.
     *
     * @param cycleCost The cycle cost value to be stored.
     * @param op The mlir::Operation pointer representing the operation.
     */
    void storeCycleCost(size_t&, mlir::Operation*);

private:
    std::shared_ptr<VPUNN::VPUCostModel> _costModel;
    std::set<std::string> _layersWithInvalidCost;
    size_t _numOfTasksWithInvalidCost = 0;
    VPU::ArchKind _archKind;
    CycleCosts _cycleCosts;

    Logger _log;
};

}  // namespace vpux
