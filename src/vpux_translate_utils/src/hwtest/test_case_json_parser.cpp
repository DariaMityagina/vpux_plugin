//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include <fstream>
#include <iostream>
#include <sstream>
#include <vpux/utils/core/error.hpp>

#include <llvm/Support/FormatVariadic.h>
#include <llvm/Support/Regex.h>
#include <mlir/IR/Location.h>

#include "vpux/hwtest/test_case_json_parser.hpp"

#include "vpux/utils/core/format.hpp"
#include "vpux/utils/core/string_ref.hpp"

using namespace vpux;

namespace {

llvm::json::Object parse2JSON(StringRef jsonString) {
    // Since the string we're parsing may come from a LIT test, strip off
    // trivial '//' comments.  NB The standard regex library requires C++17 in
    // order to anchor newlines, so we use the LLVM implementation instead.
    static llvm::Regex commentRE{"^ *//.*$", llvm::Regex::Newline};

    auto filteredJSON = jsonString.str();
    for (;;) {
        auto replaced = commentRE.sub("", filteredJSON);
        if (filteredJSON == replaced) {
            break;
        }
        filteredJSON = std::move(replaced);
    }

    if (filteredJSON.empty()) {
        throw std::runtime_error{"Expected non-empty filtered JSON"};
    }

    llvm::Expected<llvm::json::Value> exp = llvm::json::parse(filteredJSON);

    if (!exp) {
        auto err = exp.takeError();
        throw std::runtime_error{printToString("HWTEST JSON parsing failed: {0}", err)};
    }

    auto json_object = exp->getAsObject();
    if (!json_object) {
        throw std::runtime_error{"Expected to get JSON as an object"};
    }
    return *json_object;
}

static bool isEqual(StringRef a, const char* b) {
    if (a.size() != strlen(b)) {
        return false;
    }
    auto predicate = [](char left, char right) -> bool {
        return std::tolower(left) == std::tolower(right);
    };
    return std::equal(a.begin(), a.end(), b, predicate);
}

}  // namespace

nb::DType nb::to_dtype(StringRef str) {
    if (isEqual(str, "uint8"))
        return nb::DType::U8;
    if (isEqual(str, "uint4"))
        return nb::DType::U4;
    if (isEqual(str, "int4"))
        return nb::DType::I4;
    if (isEqual(str, "int8"))
        return nb::DType::I8;
    if (isEqual(str, "int32"))
        return nb::DType::I32;
    if (isEqual(str, "bfloat8"))
        return nb::DType::BF8;
    if (isEqual(str, "hfloat8"))
        return nb::DType::HF8;
    if (isEqual(str, "fp16"))
        return nb::DType::FP16;
    if (isEqual(str, "fp32"))
        return nb::DType::FP32;
    if (isEqual(str, "bfloat16"))
        return nb::DType::BF16;

    return nb::DType::UNK;
}

std::string nb::to_string(nb::DType dtype) {
    switch (dtype) {
    case nb::DType::U8:
        return "uint8";
    case nb::DType::U4:
        return "uint4";
    case nb::DType::I4:
        return "int4";
    case nb::DType::I8:
        return "int8";
    case nb::DType::I32:
        return "int32";
    case nb::DType::BF8:
        return "bfloat8";
    case nb::DType::HF8:
        return "hfloat8";
    case nb::DType::FP16:
        return "fp16";
    case nb::DType::FP32:
        return "fp32";
    case nb::DType::BF16:
        return "bfloat16";
    default:
        return "UNK";
    }
}

MVCNN::Permutation nb::to_odu_permutation(StringRef str) {
    if (isEqual(str, "NHWC"))
        return MVCNN::Permutation::Permutation_ZXY;
    if (isEqual(str, "NWHC"))
        return MVCNN::Permutation::Permutation_ZYX;
    if (isEqual(str, "NWCH"))
        return MVCNN::Permutation::Permutation_YZX;
    if (isEqual(str, "NCWH"))
        return MVCNN::Permutation::Permutation_YXZ;
    if (isEqual(str, "NHCW"))
        return MVCNN::Permutation::Permutation_XZY;
    if (isEqual(str, "NCHW"))
        return MVCNN::Permutation::Permutation_XYZ;
    throw std::runtime_error("ODUPermutation value not supported: " + str.str());

    return MVCNN::Permutation::Permutation_MIN;
}

nb::MemoryLocation nb::to_memory_location(StringRef str) {
    if (isEqual(str, "CMX0")) {
        return nb::MemoryLocation::CMX0;
    }
    if (isEqual(str, "CMX1")) {
        return nb::MemoryLocation::CMX1;
    }
    if (isEqual(str, "DDR")) {
        return nb::MemoryLocation::DDR;
    }

    return nb::MemoryLocation::Unknown;
}

std::string nb::to_string(nb::MemoryLocation memoryLocation) {
    switch (memoryLocation) {
    case MemoryLocation::CMX0:
        return "CMX0";
    case MemoryLocation::CMX1:
        return "CMX1";
    case MemoryLocation::DDR:
        return "DDR";
    default:
        return "Unknown";
    }
}

nb::ActivationType nb::to_activation_type(StringRef str) {
    if (!str.size() || isEqual(str, "None")) {
        return nb::ActivationType::None;
    }
    if (isEqual(str, "LeakyReLU") || isEqual(str, "PReLU")) {
        return nb::ActivationType::LeakyReLU;
    }
    if (isEqual(str, "ReLU")) {
        return nb::ActivationType::ReLU;
    }
    if (isEqual(str, "ReLUX")) {
        return nb::ActivationType::ReLUX;
    }
    if (isEqual(str, "Mish")) {
        return nb::ActivationType::Mish;
    }
    if (isEqual(str, "HSwish")) {
        return nb::ActivationType::HSwish;
    }
    if (isEqual(str, "Sigmoid")) {
        return nb::ActivationType::Sigmoid;
    }
    if (isEqual(str, "Softmax")) {
        return nb::ActivationType::Softmax;
    }
    if (isEqual(str, "round_trip_b8h8_to_fp16")) {
        return nb::ActivationType::round_trip_b8h8_to_fp16;
    }
    if (isEqual(str, "PopulateWeightTable")) {
        return nb::ActivationType::PopulateWeightTable;
    }
    if (isEqual(str, "Rsqrt")) {
        return nb::ActivationType::Rsqrt;
    }
    return nb::ActivationType::Unknown;
}

std::string nb::to_string(nb::ActivationType activationType) {
    switch (activationType) {
    case ActivationType::None:
        return "None";
    case ActivationType::ReLU:
        return "ReLU";
    case ActivationType::ReLUX:
        return "ReLUX";
    case ActivationType::LeakyReLU:
        return "LeakyReLU";
    case ActivationType::Mish:
        return "Mish";
    case ActivationType::HSwish:
        return "HSwish";
    case ActivationType::Sigmoid:
        return "Sigmoid";
    case ActivationType::Softmax:
        return "Softmax";
    case ActivationType::round_trip_b8h8_to_fp16:
        return "round_trip_b8h8_to_fp16";
    case ActivationType::PopulateWeightTable:
        return "PopulateWeightTable";
    case ActivationType::Rsqrt:
        return "Rsqrt";
    default:
        return "Unknown";
    }
}

std::string nb::to_string(CaseType case_) {
    switch (case_) {
    case CaseType::DMA:
        return "DMA";
    case CaseType::DMAcompressAct:
        return "DMAcompressAct";
    case CaseType::ZMajorConvolution:
        return "ZMajorConvolution";
    case CaseType::SparseZMajorConvolution:
        return "SparseZMajorConvolution";
    case CaseType::DepthWiseConv:
        return "DepthWiseConv";
    case CaseType::DoubleZMajorConvolution:
        return "DoubleZMajorConvolution";
    case CaseType::EltwiseDense:
        return "EltwiseDense";
    case CaseType::EltwiseMultDW:
        return "EltwiseMultDW";
    case CaseType::EltwiseSparse:
        return "EltwiseSparse";
    case CaseType::MaxPool:
        return "MaxPool";
    case CaseType::AvgPool:
        return "AvgPool";
    case CaseType::DifferentClustersDPU:
        return "DifferentClustersDPU";
    case CaseType::MultiClustersDPU:
        return "MultiClustersDPU";
    case CaseType::HaloMultiClustering:
        return "HaloMultiClustering";
    case CaseType::ActShave:
        return "ActShave";
    case CaseType::M2iTask:
        return "M2iTask";
    case CaseType::ReadAfterWriteDPUDMA:
        return "ReadAfterWriteDPUDMA";
    case CaseType::ReadAfterWriteDMADPU:
        return "ReadAfterWriteDMADPU";
    case CaseType::ReadAfterWriteACTDMA:
        return "ReadAfterWriteACTDMA";
    case CaseType::ReadAfterWriteDMAACT:
        return "ReadAfterWriteDMAACT";
    case CaseType::ReadAfterWriteDPUACT:
        return "ReadAfterWriteDPUACT";
    case CaseType::ReadAfterWriteACTDPU:
        return "ReadAfterWriteACTDPU";
    case CaseType::RaceConditionDMA:
        return "RaceConditionDMA";
    case CaseType::RaceConditionDPU:
        return "RaceConditionDPU";
    case CaseType::RaceConditionDPUDMA:
        return "RaceConditionDPUDMA";
    case CaseType::RaceConditionDPUDMAACT:
        return "RaceConditionDPUDMAACT";
    case CaseType::RaceConditionDPUACT:
        return "RaceConditionDPUACT";
    case CaseType::RaceCondition:
        return "RaceCondition";
    case CaseType::DualChannelDMA:
        return "DualChannelDMA";
    case CaseType::GenerateScaleTable:
        return "GenerateScaleTable";
    default:
        return "unknown";
    }
}

nb::CaseType nb::to_case(StringRef str) {
    if (isEqual(str, "DMA"))
        return CaseType::DMA;
    if (isEqual(str, "DMAcompressAct"))
        return CaseType::DMAcompressAct;
    if (isEqual(str, "GatherDMA"))
        return CaseType::GatherDMA;
    if (isEqual(str, "ZMajorConvolution"))
        return CaseType::ZMajorConvolution;
    if (isEqual(str, "SparseZMajorConvolution"))
        return CaseType::SparseZMajorConvolution;
    if (isEqual(str, "DepthWiseConv"))
        return CaseType::DepthWiseConv;
    if (isEqual(str, "DoubleZMajorConvolution"))
        return CaseType::DoubleZMajorConvolution;
    if (isEqual(str, "EltwiseDense"))
        return CaseType::EltwiseDense;
    if (isEqual(str, "EltwiseMultDW"))
        return CaseType::EltwiseMultDW;
    if (isEqual(str, "EltwiseSparse"))
        return CaseType::EltwiseSparse;
    if (isEqual(str, "MaxPool"))
        return CaseType::MaxPool;
    if (isEqual(str, "AvgPool"))
        return CaseType::AvgPool;
    if (isEqual(str, "DifferentClustersDPU"))
        return CaseType::DifferentClustersDPU;
    if (isEqual(str, "MultiClustersDPU"))
        return CaseType::MultiClustersDPU;
    if (isEqual(str, "HaloMultiClustering"))
        return CaseType::HaloMultiClustering;
    if (isEqual(str, "ActShave"))
        return CaseType::ActShave;
    if (isEqual(str, "M2iTask"))
        return CaseType::M2iTask;
    if (isEqual(str, "ReadAfterWriteDPUDMA"))
        return CaseType::ReadAfterWriteDPUDMA;
    if (isEqual(str, "ReadAfterWriteDMADPU"))
        return CaseType::ReadAfterWriteDMADPU;
    if (isEqual(str, "ReadAfterWriteACTDMA"))
        return CaseType::ReadAfterWriteACTDMA;
    if (isEqual(str, "ReadAfterWriteDPUACT"))
        return CaseType::ReadAfterWriteDPUACT;
    if (isEqual(str, "ReadAfterWriteACTDPU"))
        return CaseType::ReadAfterWriteACTDPU;
    if (isEqual(str, "ReadAfterWriteDMAACT"))
        return CaseType::ReadAfterWriteDMAACT;
    if (isEqual(str, "RaceConditionDMA"))
        return CaseType::RaceConditionDMA;
    if (isEqual(str, "RaceConditionDPU"))
        return CaseType::RaceConditionDPU;
    if (isEqual(str, "RaceConditionDPUDMA"))
        return CaseType::RaceConditionDPUDMA;
    if (isEqual(str, "RaceConditionDPUDMAACT"))
        return CaseType::RaceConditionDPUDMAACT;
    if (isEqual(str, "RaceConditionDPUACT"))
        return CaseType::RaceConditionDPUACT;
    if (isEqual(str, "RaceCondition"))
        return CaseType::RaceCondition;
    if (isEqual(str, "StorageElementTableDPU"))
        return CaseType::StorageElementTableDPU;
    if (isEqual(str, "DualChannelDMA"))
        return CaseType::DualChannelDMA;
    if (isEqual(str, "GenerateScaleTable"))
        return CaseType::GenerateScaleTable;
    return CaseType::Unknown;
};

nb::M2iFmt nb::to_m2i_fmt(StringRef str) {
    if (isEqual(str, "SP_NV12_8"))
        return nb::M2iFmt::SP_NV12_8;
    if (isEqual(str, "PL_YUV420_8"))
        return nb::M2iFmt::PL_YUV420_8;
    if (isEqual(str, "IL_RGB888"))
        return nb::M2iFmt::IL_RGB888;
    if (isEqual(str, "IL_BGR888"))
        return nb::M2iFmt::IL_BGR888;
    if (isEqual(str, "PL_RGB24"))
        return nb::M2iFmt::PL_RGB24;
    if (isEqual(str, "PL_FP16_RGB"))
        return nb::M2iFmt::PL_FP16_RGB;
    return M2iFmt::Unknown;
}

nb::M2iInterp nb::to_m2i_interp(StringRef str) {
    if (isEqual(str, "NEAREST"))
        return nb::M2iInterp::NEAREST;
    if (isEqual(str, "BILINEAR"))
        return nb::M2iInterp::BILINEAR;
    return nb::M2iInterp::UNKNOWN;
}

std::string nb::to_string(nb::CompilerBackend compilerBackend) {
    if (compilerBackend == nb::CompilerBackend::ELF)
        return "ELF";
    else
        return "unknown";
}

std::string nb::to_string(nb::SegmentationType segmentationType) {
    switch (segmentationType) {
    case nb::SegmentationType::SOK:
        return "SOK";
    case nb::SegmentationType::SOH:
        return "SOH";
    case nb::SegmentationType::SOW:
        return "SOW";
    case nb::SegmentationType::SOHW:
        return "SOHW";
    case nb::SegmentationType::SOHK:
        return "SOHK";
    default:
        return "Unknown";
    }
}

nb::QuantParams nb::TestCaseJsonDescriptor::loadQuantizationParams(llvm::json::Object* obj) {
    nb::QuantParams result;
    auto* qp = obj->getObject("quantization");
    if (qp) {
        result.present = true;

        const auto* jsonQuantScales = qp->getArray("scale");
        VPUX_THROW_UNLESS(jsonQuantScales != nullptr, "loadQuantizationParams: cannot find scale config param");
        for (size_t i = 0; i < jsonQuantScales->size(); i++) {
            auto elem = (*jsonQuantScales)[i].getAsNumber();  // double
            if (elem.has_value()) {
                result.scale.push_back(static_cast<double>(elem.value()));
            }
        }

        result.zeropoint = qp->getInteger("zeropoint").value();
        result.low_range = static_cast<std::int64_t>(qp->getNumber("low_range").value());
        result.high_range = static_cast<std::int64_t>(qp->getNumber("high_range").value());
    }
    return result;
}

nb::RaceConditionParams nb::TestCaseJsonDescriptor::loadRaceConditionParams(llvm::json::Object* jsonObj) {
    nb::RaceConditionParams params;
    params.iterationsCount = jsonObj->getInteger("iteration_count").value();
    params.requestedClusters = jsonObj->getInteger("requested_clusters").value();
    params.requestedUnits = jsonObj->getInteger("requested_units").value();

    return params;
}

nb::DPUTaskParams nb::TestCaseJsonDescriptor::loadDPUTaskParams(llvm::json::Object* jsonObj) {
    nb::DPUTaskParams params;
    auto* taskParams = jsonObj->getObject("DPUTaskParams");
    const auto* jsonOutClusters = taskParams->getArray("output_cluster");

    VPUX_THROW_UNLESS(jsonOutClusters != nullptr, "loadDPUTaskParams: cannot find output_cluster config param");

    params.outputClusters.resize(jsonOutClusters->size());
    for (size_t i = 0; i < jsonOutClusters->size(); i++) {
        params.outputClusters[i] = (*jsonOutClusters)[i].getAsInteger().value();
    }

    params.inputCluster = taskParams->getInteger("input_cluster").value();
    params.weightsCluster = taskParams->getInteger("weights_cluster").value();
    params.weightsTableCluster = taskParams->getInteger("weights_table_cluster").value();

    return params;
}

nb::MultiClusterDPUParams nb::TestCaseJsonDescriptor::loadMultiClusterDPUParams(llvm::json::Object* jsonObj) {
    nb::MultiClusterDPUParams params;
    auto* taskParams = jsonObj->getObject("DPUTaskParams");

    const auto* jsonTaskClusters = taskParams->getArray("task_clusters");
    VPUX_THROW_UNLESS(jsonTaskClusters != nullptr, "loadMultiClusterDPUParams: cannot find task_clusters config param");

    params.taskClusters.resize(jsonTaskClusters->size());
    for (size_t i = 0; i < jsonTaskClusters->size(); i++) {
        params.taskClusters[i] = (*jsonTaskClusters)[i].getAsInteger().value();
    }

    const std::unordered_map<llvm::StringRef, SegmentationType> segmentOptions = {{"SOK", SegmentationType::SOK},
                                                                                  {"SOH", SegmentationType::SOH}};

    auto segmentation = taskParams->getString("segmentation");
    VPUX_THROW_UNLESS(segmentation.has_value() && segmentOptions.find(segmentation.value()) != segmentOptions.end(),
                      "loadMultiClusterDPUParams: failed to get valid segmentation type");

    params.segmentation = segmentOptions.at(segmentation.value().str());
    params.broadcast = taskParams->getBoolean("broadcast").value();

    return params;
}

nb::HaloParams nb::TestCaseJsonDescriptor::loadHaloTaskParams(llvm::json::Object* jsonObj) {
    nb::HaloParams params;
    auto* taskParams = jsonObj->getObject("HaloParams");

    const auto* jsonTaskClusters = taskParams->getArray("task_clusters");
    VPUX_THROW_UNLESS(jsonTaskClusters != nullptr, "loadHaloTaskParams: cannot find task_clusters config param");

    params.taskClusters.resize(jsonTaskClusters->size());
    for (size_t i = 0; i < jsonTaskClusters->size(); i++) {
        params.taskClusters[i] = (*jsonTaskClusters)[i].getAsInteger().value();
    }

    const std::unordered_map<llvm::StringRef, SegmentationType> segmentOptions = {{"SOK", SegmentationType::SOK},
                                                                                  {"SOH", SegmentationType::SOH},
                                                                                  {"SOW", SegmentationType::SOW},
                                                                                  {"SOHW", SegmentationType::SOHW},
                                                                                  {"SOHK", SegmentationType::SOHK}};

    auto segmentation = taskParams->getString("segmentation");
    VPUX_THROW_UNLESS(segmentation.has_value() && segmentOptions.find(segmentation.value()) != segmentOptions.end(),
                      "loadHaloTaskParams: failed to get valid segmentation type");

    params.segmentation = segmentOptions.at(segmentation.value().str());

    if (params.segmentation == SegmentationType::SOHW || params.segmentation == SegmentationType::SOHK) {
        const auto* jsonClustersPerDim = taskParams->getArray("clusters_per_dim");
        VPUX_THROW_UNLESS(jsonClustersPerDim != nullptr,
                          "loadHaloTaskParams: cannot find clusters_per_dim config param");

        params.clustersPerDim.resize(jsonClustersPerDim->size());
        for (size_t i = 0; i < jsonClustersPerDim->size(); i++) {
            params.clustersPerDim[i] = (*jsonClustersPerDim)[i].getAsInteger().value();
        }
    }

    params.heightHaloSize = taskParams->getInteger("spatial_halo_h").value();
    params.widthHaloSize = taskParams->getInteger("spatial_halo_w").value();

    return params;
}

SmallVector<nb::InputLayer> nb::TestCaseJsonDescriptor::loadInputLayer(llvm::json::Object* jsonObj) {
    SmallVector<nb::InputLayer> result;

    auto* inputArray = jsonObj->getArray("input");
    if (!inputArray) {
        return result;
    }

    result.resize(inputArray->size());
    for (size_t inIdx = 0; inIdx < inputArray->size(); inIdx++) {
        auto inputObj = (*inputArray)[inIdx].getAsObject();
        auto* shape = inputObj->getArray("shape");
        VPUX_THROW_UNLESS(shape != nullptr, "loadInputLayer: missing shape");

        for (size_t i = 0; i < shape->size(); i++) {
            result[inIdx].shape[i] = (*shape)[i].getAsInteger().value();
        }

        result[inIdx].qp = loadQuantizationParams(inputObj);
        result[inIdx].dtype = to_dtype(inputObj->getString("dtype").value().str());
    }

    return result;
}

SmallVector<nb::WeightLayer> nb::TestCaseJsonDescriptor::loadWeightLayer(llvm::json::Object* jsonObj) {
    SmallVector<nb::WeightLayer> result;

    auto* weightArray = jsonObj->getArray("weight");
    if (!weightArray) {
        return result;
    }
    result.resize(weightArray->size());

    for (size_t inIdx = 0; inIdx < weightArray->size(); inIdx++) {
        auto weightObj = (*weightArray)[inIdx].getAsObject();
        auto* shape = weightObj->getArray("shape");
        VPUX_THROW_UNLESS(shape != nullptr, "loadWeightLayer: missing shape");

        for (size_t i = 0; i < shape->size(); i++) {
            result[inIdx].shape[i] = (*shape)[i].getAsInteger().value();
        }

        result[inIdx].qp = loadQuantizationParams(weightObj);
        result[inIdx].dtype = to_dtype(weightObj->getString("dtype").value().str());

        auto filename = weightObj->getString("file_path");
        if (filename) {
            result[inIdx].filename = filename.value().str();
        }
    }

    return result;
}

SmallVector<nb::SM> nb::TestCaseJsonDescriptor::loadInputSMs(llvm::json::Object* jsonObj) {
    SmallVector<nb::SM> result;

    auto* smArray = jsonObj->getArray("sparsity_map_input");
    if (!smArray) {
        return result;
    }

    result.resize(smArray->size());

    for (size_t inIdx = 0; inIdx < smArray->size(); inIdx++) {
        auto inputObj = (*smArray)[inIdx].getAsObject();
        auto* shape = inputObj->getArray("shape");
        VPUX_THROW_UNLESS(shape != nullptr, "loadInputSMs: missing shape");

        for (size_t i = 0; i < shape->size(); i++) {
            result[inIdx].shape[i] = (*shape)[i].getAsInteger().value();
        }
    }

    return result;
}

SmallVector<nb::SM> nb::TestCaseJsonDescriptor::loadWeightSMs(llvm::json::Object* jsonObj) {
    SmallVector<nb::SM> result;

    auto* smArray = jsonObj->getArray("sparsity_map_weights");
    if (!smArray) {
        return result;
    }

    result.resize(smArray->size());
    for (size_t inIdx = 0; inIdx < smArray->size(); inIdx++) {
        auto inputObj = (*smArray)[inIdx].getAsObject();
        auto* shape = inputObj->getArray("shape");
        VPUX_THROW_UNLESS(shape != nullptr, "loadWeightSMs: missing shape");

        for (size_t i = 0; i < shape->size(); i++) {
            result[inIdx].shape[i] = (*shape)[i].getAsInteger().value();
        }
    }

    return result;
}

SmallVector<nb::OutputLayer> nb::TestCaseJsonDescriptor::loadOutputLayer(llvm::json::Object* jsonObj) {
    SmallVector<nb::OutputLayer> result;

    auto* outputArray = jsonObj->getArray("output");
    if (!outputArray) {
        return result;
    }

    result.resize(outputArray->size());
    for (size_t outIdx = 0; outIdx < outputArray->size(); outIdx++) {
        auto outputObj = (*outputArray)[outIdx].getAsObject();
        auto* shape = outputObj->getArray("shape");
        VPUX_THROW_UNLESS(shape != nullptr, "loadOutputLayer: missing shape");

        for (size_t i = 0; i < shape->size(); i++) {
            result[outIdx].shape[i] = (*shape)[i].getAsInteger().value();
        }

        result[outIdx].qp = loadQuantizationParams(outputObj);
        result[outIdx].dtype = to_dtype(outputObj->getString("dtype").value().str());
    }

    return result;
}

nb::DMAparams nb::TestCaseJsonDescriptor::loadDMAParams(llvm::json::Object* jsonObj) {
    nb::DMAparams result;

    auto* params = jsonObj->getObject("DMA_params");
    if (!params) {
        VPUX_THROW("DMA params doesn't provided");
    }

    auto srcMemLoc = params->getString("src_memory_location");
    VPUX_THROW_UNLESS(srcMemLoc.has_value(), "Source memory location doesn't provided");
    result.srcLocation = to_memory_location(srcMemLoc.value());

    auto dstMemLoc = params->getString("dst_memory_location");
    VPUX_THROW_UNLESS(dstMemLoc.has_value(), "Destination memory location doesn't provided");
    result.dstLocation = to_memory_location(dstMemLoc.value());

    auto dmaEngine = params->getInteger("dma_engine");
    VPUX_THROW_UNLESS(dmaEngine.has_value(), "DMA engine doesn't provided");
    result.engine = dmaEngine.value();

    if (architecture_ == vpux::VPU::ArchKind::NPU40XX) {
        auto actCompressDenseMode = params->getBoolean("actCompressDenseMode");
        VPUX_THROW_UNLESS(actCompressDenseMode.has_value(), "Activation Compression wasn't provided");
        result.actCompressDenseMode = actCompressDenseMode.value();
        auto indicesMemLoc = params->getString("indicesMemoryLocation");
        result.indicesLocation =
                indicesMemLoc.has_value() ? to_memory_location(dstMemLoc.value()) : MemoryLocation::Unknown;
        auto convertDatatypeEn = params->getBoolean("convert_datatype_en");
        result.doConvert = convertDatatypeEn.has_value() ? convertDatatypeEn.value() : false;
        auto testMemSideCache = params->getBoolean("memory_side_cache");
        result.testMemSideCache = testMemSideCache.has_value() ? testMemSideCache.value() : false;
        auto cacheTrashing = params->getBoolean("cache_trashing");
        result.cacheTrashing = cacheTrashing.has_value() ? cacheTrashing.value() : false;
        auto cacheEnabled = params->getBoolean("cache_enable");
        result.cacheEnabled = cacheEnabled.has_value() ? cacheEnabled.value() : false;
    }

    return result;
}

nb::GatherIndices nb::TestCaseJsonDescriptor::loadGatherIndices(llvm::json::Object* jsonObj) {
    nb::GatherIndices result;

    auto* params = jsonObj->getObject("indices_input");
    if (!params) {
        VPUX_THROW("Indices input is not provided");
    }

    auto* shape = params->getArray("shape");
    VPUX_THROW_UNLESS(shape != nullptr, "loadGatherIndices: missing shape");
    auto nonOneDimension{0};
    for (size_t i = 0; i < shape->size(); i++) {
        result.shape[i] = (*shape)[i].getAsInteger().value();
        if (result.shape[i] > 1) {
            ++nonOneDimension;
        }
    }
    result.dtype = to_dtype(params->getString("dtype").value().str());
    VPUX_THROW_WHEN(nonOneDimension > 1, "loadGatherIndices: Incorrect shape, only 1 dimension can be larger than 1");
    return result;
}

nb::M2iLayer nb::TestCaseJsonDescriptor::loadM2iLayer(llvm::json::Object* jsonObj) {
    nb::M2iLayer result;

    auto* params = jsonObj->getObject("m2i_params");
    if (!params) {
        VPUX_THROW("M2I params not provided");
    }
    const auto inputFmt = params->getString("input_fmt");
    const auto outputFmt = params->getString("output_fmt");
    const auto cscFlag = params->getBoolean("do_csc");
    const auto normFlag = params->getBoolean("do_norm");
    const auto tilingFlag = params->getBoolean("do_tiling");
    const auto interp = params->getString("interp");

    VPUX_THROW_UNLESS(inputFmt.has_value(), "input_fmt not provided !");
    VPUX_THROW_UNLESS(outputFmt.has_value(), "output_fmt not provided !");
    VPUX_THROW_UNLESS(cscFlag.has_value(), "do_csc not provided !");
    VPUX_THROW_UNLESS(normFlag.has_value(), "do_norm not provided !");
    VPUX_THROW_UNLESS(tilingFlag.has_value(), "do_tiling not provided !");
    VPUX_THROW_UNLESS(interp.has_value(), "interp not provided !");

    result.iFmt = to_m2i_fmt(inputFmt.value());  // str to enum
    result.oFmt = to_m2i_fmt(outputFmt.value());
    result.doCsc = cscFlag.value();
    result.doNorm = normFlag.value();
    result.doTiling = tilingFlag.value();
    result.interp = to_m2i_interp(interp.value());

    // Optional params for RESIZE and NORM
    const auto* sizesVec = params->getArray("output_sizes");
    const auto* coefsVec = params->getArray("norm_coefs");
    VPUX_THROW_UNLESS(sizesVec != nullptr, "loadM2iLayer: missing sizesVec");
    VPUX_THROW_UNLESS(coefsVec != nullptr, "loadM2iLayer: missing coefsVec");

    for (size_t i = 0; i < sizesVec->size(); i++) {
        auto elem = (*sizesVec)[i].getAsInteger();
        if (elem.has_value()) {
            result.outSizes.push_back(static_cast<int>(elem.value()));
        }
    }

    for (size_t i = 0; i < coefsVec->size(); i++) {
        auto elem = (*coefsVec)[i].getAsNumber();  // double
        if (elem.has_value()) {
            result.normCoefs.push_back(static_cast<float>(elem.value()));
        }
    }

    return result;
}

nb::EltwiseLayer nb::TestCaseJsonDescriptor::loadEltwiseLayer(llvm::json::Object* jsonObj) {
    std::string layerType = "ew_op";

    nb::EltwiseLayer result;
    auto* op = jsonObj->getObject("ew_op");
    VPUX_THROW_UNLESS(op != nullptr, "loadEltwiseLayer: missing ew_op config");

    result.seSize = op->getInteger("se_size").value_or(0);

    const std::unordered_map<llvm::StringRef, vpux::VPU::PPEMode> eltwiseOptions = {{"ADD", vpux::VPU::PPEMode::ADD},
                                                                                    {"SUB", vpux::VPU::PPEMode::SUB},
                                                                                    {"MULT", vpux::VPU::PPEMode::MULT}};

    auto mode = op->getString("mode");
    VPUX_THROW_UNLESS(mode.has_value() && eltwiseOptions.find(mode.value()) != eltwiseOptions.end(),
                      "loadEltwiseLayer: failed to get valid operation type");

    result.mode = eltwiseOptions.at(mode.value().str());

    const std::unordered_map<llvm::StringRef, ICM_MODE> icmModes = {{"DEFAULT", ICM_MODE::DEFAULT},
                                                                    {"MODE_0", ICM_MODE::MODE_0},
                                                                    {"MODE_1", ICM_MODE::MODE_1},
                                                                    {"MODE_2", ICM_MODE::MODE_2}};

    auto icmMode = op->getString("idu_cmx_mux_mode");
    if (icmMode.has_value() && icmModes.find(icmMode.value()) != icmModes.end()) {
        result.iduCmxMuxMode = icmModes.at(icmMode.value().str());
    }

    return result;
}

nb::ConvLayer nb::TestCaseJsonDescriptor::loadConvLayer(llvm::json::Object* jsonObj) {
    std::string layerType = "conv_op";

    nb::ConvLayer result;

    auto* op = jsonObj->getObject("conv_op");
    VPUX_THROW_UNLESS(op != nullptr, "loadConvLayer: missing conv_op config");

    auto* strides = op->getArray("stride");
    VPUX_THROW_UNLESS(strides != nullptr, "loadConvLayer: missing strides");

    for (size_t i = 0; i < strides->size(); i++) {
        auto stride = (*strides)[i].getAsInteger();
        if (stride.has_value()) {
            result.stride.at(i) = stride.value();
        }
    }

    auto* pads = op->getArray("pad");
    VPUX_THROW_UNLESS(pads != nullptr, "loadConvLayer: missing pads");

    for (size_t i = 0; i < pads->size(); i++) {
        auto pad = (*pads)[i].getAsInteger();
        if (pad.has_value()) {
            result.pad.at(i) = pad.value();
        }
    }

    result.group = op->getInteger("group").value();
    result.dilation = op->getInteger("dilation").value();
    auto compress = op->getBoolean("compress");
    if (compress.has_value()) {
        result.compress = compress.value();
    } else {
        result.compress = false;
    }

    auto mpe_mode = op->getString("mpe_mode");
    if (mpe_mode.has_value()) {
        if (mpe_mode.value() == "CUBOID_8x16") {
            result.cube_mode = vpux::VPU::MPEMode::CUBOID_8x16;
        } else if (mpe_mode.value() == "CUBOID_4x16") {
            result.cube_mode = vpux::VPU::MPEMode::CUBOID_4x16;
        }
        // TODO: Check for the default (CUBOID_16x16) and log if it's something else.
    }

    auto act_sparsity = op->getBoolean("act_sparsity");
    if (act_sparsity.has_value()) {
        result.act_sparsity = act_sparsity.value();
    } else {
        result.act_sparsity = false;
    }

    return result;
}

nb::PoolLayer nb::TestCaseJsonDescriptor::loadPoolLayer(llvm::json::Object* jsonObj) {
    std::string layerType = "pool_op";

    nb::PoolLayer result;

    auto* op = jsonObj->getObject("pool_op");
    VPUX_THROW_UNLESS(op != nullptr, "loadPoolLayer: missing pool_op config");

    auto* kernel_shape = op->getArray("kernel_shape");
    VPUX_THROW_UNLESS(kernel_shape != nullptr, "loadPoolLayer: missing kernel_shape");

    for (size_t i = 0; i < kernel_shape->size(); i++) {
        auto kernelsize = (*kernel_shape)[i].getAsInteger();
        if (kernelsize.has_value()) {
            result.kernel_shape.at(i) = kernelsize.value();
        }
    }
    auto* strides = op->getArray("stride");
    VPUX_THROW_UNLESS(strides != nullptr, "loadPoolLayer: missing stride");

    for (size_t i = 0; i < strides->size(); i++) {
        auto stride = (*strides)[i].getAsInteger();
        if (stride.has_value()) {
            result.stride.at(i) = stride.value();
        }
    }

    auto* pads = op->getArray("pad");
    if (!pads) {
        return result;
    }
    for (size_t i = 0; i < pads->size(); i++) {
        auto pad = (*pads)[i].getAsInteger();
        if (pad.has_value()) {
            result.pad.at(i) = pad.value();
        }
    }

    return result;
}

nb::ActivationLayer nb::TestCaseJsonDescriptor::loadActivationLayer(llvm::json::Object* jsonObj) {
    nb::ActivationLayer result = {
            /*activationType=*/ActivationType::None,
            /*alpha=*/0,
            /*maximum=*/0,
            /*axis=*/0,
            /*weightsOffset=*/std::nullopt,
            /*weightsPtrStep=*/std::nullopt,
    };

    auto* act = jsonObj->getObject("activation");
    if (!act) {
        // This is fine; just return a default activation layer.
        return result;
    }

    result.activationType = to_activation_type(act->getString("name").value().str());

    auto alpha = act->getNumber("alpha");
    if (alpha.has_value()) {
        result.alpha = alpha.value();
    }

    auto maximum = act->getNumber("max");
    if (maximum.has_value()) {
        result.maximum = maximum.value();
    }

    auto axis = act->getNumber("axis");
    if (axis.has_value()) {
        result.axis = vpux::checked_cast<size_t>(axis.value());
    }

    auto weightsOffset = act->getInteger("weights_offset");
    if (weightsOffset.has_value()) {
        result.weightsOffset = weightsOffset;
    }

    auto weightsPtrStep = act->getInteger("weights_ptr_step");
    if (weightsPtrStep.has_value()) {
        result.weightsPtrStep = weightsPtrStep;
    }

    return result;
}

std::size_t nb::TestCaseJsonDescriptor::loadIterationCount(llvm::json::Object* jsonObj) {
    return jsonObj->getInteger("iteration_count").value();
}

std::size_t nb::TestCaseJsonDescriptor::loadClusterNumber(llvm::json::Object* jsonObj) {
    return jsonObj->getInteger("cluster_number").value();
}
std::size_t nb::TestCaseJsonDescriptor::loadNumClusters(llvm::json::Object* jsonObj) {
    return jsonObj->getInteger("num_clusters").value();
}

nb::SwizzlingKey nb::TestCaseJsonDescriptor::loadSwizzlingKey(llvm::json::Object* jsonObj, std::string keyType) {
    auto swizzlingKey = jsonObj->getInteger(keyType);
    if (swizzlingKey.has_value() && swizzlingKey.value() >= nb::to_underlying(SwizzlingKey::key0) &&
        swizzlingKey.value() <= nb::to_underlying(SwizzlingKey::key5))
        return static_cast<SwizzlingKey>(swizzlingKey.value());
    return SwizzlingKey::key0;
}

nb::ProfilingParams nb::TestCaseJsonDescriptor::loadProfilingParams(llvm::json::Object* jsonObj) {
    bool dpuProfilingEnabled = jsonObj->getBoolean("dpu_profiling").value_or(false);
    bool dmaProfilingEnabled = jsonObj->getBoolean("dma_profiling").value_or(false);
    bool swProfilingEnabled = jsonObj->getBoolean("sw_profiling").value_or(false);
    bool m2iProfilingEnabled = jsonObj->getBoolean("m2i_profiling").value_or(false);
    bool workpointEnabled = jsonObj->getBoolean("workpoint_profiling").value_or(false);

    return {dpuProfilingEnabled, dmaProfilingEnabled, swProfilingEnabled, m2iProfilingEnabled, workpointEnabled};
}

nb::SETableParams nb::TestCaseJsonDescriptor::loadSETableParams(llvm::json::Object* jsonObj) {
    nb::SETableParams result;

    const auto seTablePattern = jsonObj->getString("SE_table_pattern");

    VPUX_THROW_UNLESS(seTablePattern.has_value(), "loadSETableParams: no SE table pattern provided");

    const std::unordered_map<llvm::StringRef, nb::SETablePattern> supportedPatterns = {
            {"SwitchLines", nb::SETablePattern::SwitchLines},
            {"OriginalInput", nb::SETablePattern::OriginalInput}};
    const auto pattern = supportedPatterns.find(seTablePattern.value());

    VPUX_THROW_UNLESS(pattern != supportedPatterns.end(), "loadSETableParams: SE table pattern not supported");

    result.seTablePattern = pattern->second;

    const auto seOnlyEnFlag = jsonObj->getBoolean("SE_only_en");
    if (seOnlyEnFlag.has_value()) {
        result.seOnlyEn = seOnlyEnFlag.value();
    }

    return result;
};

nb::TestCaseJsonDescriptor::TestCaseJsonDescriptor(StringRef jsonString) {
    if (!jsonString.empty()) {
        parse(parse2JSON(jsonString));
    }
}

nb::TestCaseJsonDescriptor::TestCaseJsonDescriptor(llvm::json::Object jsonObject) {
    parse(std::move(jsonObject));
}

void nb::TestCaseJsonDescriptor::parse(llvm::json::Object json_obj) {
    auto architecture = json_obj.getString("architecture");
    if (!architecture) {
        throw std::runtime_error{"Failed to get architecture"};
    }

    const auto architectureSymbol = vpux::VPU::symbolizeArchKind(architecture.value());

    if (!architectureSymbol.has_value()) {
        throw std::runtime_error{"Failed to parse architecture"};
    }
    architecture_ = architectureSymbol.value();

    auto compilerBackendStr = json_obj.getString("compiler_backend");
    if (!compilerBackendStr) {
        throw std::runtime_error{"Failed to get compiler_backend"};
    }

    auto case_type = json_obj.getString("case_type");
    if (!case_type) {
        throw std::runtime_error{"Failed to get case type"};
    }

    caseType_ = nb::to_case(case_type.value());
    caseTypeStr_ = case_type.value().str();
    inLayers_ = loadInputLayer(&json_obj);
    outLayers_ = loadOutputLayer(&json_obj);
    activationLayer_ = loadActivationLayer(&json_obj);

    // Load conv json attribute values. Similar implementation for ALL HW layers (DW, group conv, Av/Max pooling and
    // eltwise needed).
    switch (caseType_) {
    case CaseType::GatherDMA:
        gatherIndices_ = loadGatherIndices(&json_obj);
        [[fallthrough]];
    case CaseType::DMAcompressAct:
    case CaseType::DMA: {
        DMAparams_ = loadDMAParams(&json_obj);
        break;
    }
    case CaseType::ZMajorConvolution:
    case CaseType::DepthWiseConv:
    case CaseType::SparseZMajorConvolution:
    case CaseType::DoubleZMajorConvolution:
    case CaseType::GenerateScaleTable: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);

        if (caseType_ == CaseType::ZMajorConvolution) {
            odu_permutation_ = to_odu_permutation(json_obj.getString("output_order").value());
            weightsSwizzlingKey_ = loadSwizzlingKey(&json_obj, "weights_swizzling_key");
            activationSwizzlingKey_ = loadSwizzlingKey(&json_obj, "activation_swizzling_key");
        }
        if (caseType_ == CaseType::SparseZMajorConvolution) {
            inSMs_ = loadInputSMs(&json_obj);
        }
        if (caseType_ == CaseType::DoubleZMajorConvolution) {
            odu_permutation_ = to_odu_permutation(json_obj.getString("output_order").value());
            activationSwizzlingKey_ = loadSwizzlingKey(&json_obj, "activation_swizzling_key");
        }
        break;
    }
    case CaseType::RaceConditionDPU: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        iterationCount_ = loadIterationCount(&json_obj);
        numClusters_ = loadNumClusters(&json_obj);
        break;
    }
    case CaseType::RaceConditionDPUDMA: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        iterationCount_ = loadIterationCount(&json_obj);
        break;
    }
    case CaseType::RaceConditionDPUDMAACT: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        iterationCount_ = loadIterationCount(&json_obj);
        activationLayer_ = loadActivationLayer(&json_obj);
        numClusters_ = loadNumClusters(&json_obj);
        break;
    }
    case CaseType::RaceConditionDPUACT: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        iterationCount_ = loadIterationCount(&json_obj);
        activationLayer_ = loadActivationLayer(&json_obj);
        break;
    }
    case CaseType::ReadAfterWriteDPUDMA:
    case CaseType::ReadAfterWriteDMADPU: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        iterationCount_ = loadIterationCount(&json_obj);
        clusterNumber_ = loadClusterNumber(&json_obj);
        break;
    }
    case CaseType::ReadAfterWriteDPUACT:
    case CaseType::ReadAfterWriteACTDPU: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        iterationCount_ = loadIterationCount(&json_obj);
        activationLayer_ = loadActivationLayer(&json_obj);
        clusterNumber_ = loadClusterNumber(&json_obj);
        break;
    }
    case CaseType::DifferentClustersDPU: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        DPUTaskParams_ = loadDPUTaskParams(&json_obj);
        break;
    }
    case CaseType::MultiClustersDPU: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        multiClusterDPUParams_ = loadMultiClusterDPUParams(&json_obj);
        odu_permutation_ = to_odu_permutation(json_obj.getString("output_order").value());
        break;
    }
    case CaseType::HaloMultiClustering: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        haloParams_ = loadHaloTaskParams(&json_obj);
        profilingParams_ = loadProfilingParams(&json_obj);
        break;
    }
    case CaseType::EltwiseDense: {
        wtLayer_ = loadWeightLayer(&json_obj);
        eltwiseLayer_ = loadEltwiseLayer(&json_obj);
        break;
    }
    case CaseType::EltwiseMultDW: {
        wtLayer_ = loadWeightLayer(&json_obj);
        break;
    }
    case CaseType::EltwiseSparse: {
        wtLayer_ = loadWeightLayer(&json_obj);
        inSMs_ = loadInputSMs(&json_obj);
        wtSMs_ = loadWeightSMs(&json_obj);
        eltwiseLayer_ = loadEltwiseLayer(&json_obj);
        break;
    }
    case CaseType::MaxPool:
        poolLayer_ = loadPoolLayer(&json_obj);
        profilingParams_ = loadProfilingParams(&json_obj);
        break;
    case CaseType::AvgPool: {
        poolLayer_ = loadPoolLayer(&json_obj);
        break;
    }
    case CaseType::ReadAfterWriteACTDMA:
    case CaseType::ReadAfterWriteDMAACT: {
        activationLayer_ = loadActivationLayer(&json_obj);
        iterationCount_ = loadIterationCount(&json_obj);
        clusterNumber_ = loadClusterNumber(&json_obj);
        break;
    }
    case CaseType::RaceConditionDMA: {
        iterationCount_ = loadIterationCount(&json_obj);
        numClusters_ = loadNumClusters(&json_obj);
        break;
    }
    case CaseType::RaceCondition: {
        if (auto underlyingOp = json_obj.getObject("operation")) {
            this->underlyingOp_ = std::make_shared<TestCaseJsonDescriptor>(*underlyingOp);
            raceConditionParams_ = loadRaceConditionParams(&json_obj);
        }
        break;
    }
    case CaseType::DualChannelDMA: {
        break;
    }
    case CaseType::M2iTask: {
        m2iLayer_ = loadM2iLayer(&json_obj);
        profilingParams_ = loadProfilingParams(&json_obj);
        break;
    }
    case CaseType::StorageElementTableDPU: {
        wtLayer_ = loadWeightLayer(&json_obj);
        convLayer_ = loadConvLayer(&json_obj);
        seTableParams_ = loadSETableParams(&json_obj);
        break;
    }
    case CaseType::ActShave: {
        profilingParams_ = loadProfilingParams(&json_obj);
        break;
    }
    default: {
        throw std::runtime_error{printToString("Unsupported case type: {0}", caseTypeStr_)};
    }
    };
}

nb::CaseType nb::TestCaseJsonDescriptor::loadCaseType(llvm::json::Object* jsonObj) {
    return to_case(jsonObj->getString("case_type").value().str());
}
