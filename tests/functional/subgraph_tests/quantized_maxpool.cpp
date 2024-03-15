// Copyright (C) Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include <vpu_ov2_layer_test.hpp>

#include <ov_models/builders.hpp>
#include <ov_models/utils/ov_helpers.hpp>
#include <shared_test_classes/base/layer_test_utils.hpp>

namespace ov::test {

class QuantizedMaxPoolSubGraphTest_NPU3700 : public VpuOv2LayerTest {
    void SetUp() override {
        const ov::Shape inputShape{1, 16, 32, 32};
        init_input_shapes(static_shapes_to_test_representation({inputShape}));

        ov::ParameterVector params{
                std::make_shared<ov::op::v0::Parameter>(ov::element::f16, inputDynamicShapes.front())};

        const size_t dataLevels = 256;
        const std::vector<float> dataLow = {0.0f};
        const std::vector<float> dataHigh = {100.0f};
        const auto dataFq = ngraph::builder::makeFakeQuantize(params[0], ov::element::f32, dataLevels, {}, dataLow,
                                                              dataHigh, dataLow, dataHigh);

        const ov::Strides strides = {2, 2};
        const std::vector<size_t> pads_begin = {0, 0};
        const std::vector<size_t> pads_end = {0, 0};
        const ov::Strides dilations = {1, 1};
        const std::vector<size_t> kernelSize = {2, 2};
        const ov::op::PadType padType = ov::op::PadType::AUTO;
        const ov::op::RoundingType roundingType = ov::op::RoundingType::FLOOR;

        const auto pooling =
                ngraph::builder::makePooling(dataFq, strides, pads_begin, pads_end, kernelSize, roundingType, padType,
                                             false, ngraph::helpers::PoolingTypes::MAX);

        const std::vector<float> outDataLow = {0.0f};
        const std::vector<float> outDataHigh = {100.0f};
        const auto outDataFq = ngraph::builder::makeFakeQuantize(pooling, ov::element::f32, dataLevels, {}, outDataLow,
                                                                 outDataHigh, outDataLow, outDataHigh);

        const ov::ResultVector results{std::make_shared<ov::op::v0::Result>(outDataFq)};
        function = std::make_shared<ov::Model>(results, params, "QuantizedMaxPool");
        rel_threshold = 0.1f;
    }
};

TEST_F(QuantizedMaxPoolSubGraphTest_NPU3700, SW) {
    setReferenceSoftwareMode();
    run(VPUXPlatform::VPU3700);
}

TEST_F(QuantizedMaxPoolSubGraphTest_NPU3700, HW) {
    setDefaultHardwareMode();
    run(VPUXPlatform::VPU3700);
}

}  // namespace ov::test
