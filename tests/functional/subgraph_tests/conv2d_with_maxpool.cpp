//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include <vpu_ov2_layer_test.hpp>

#include <ov_models/builders.hpp>
#include <ov_models/utils/ov_helpers.hpp>
#include <shared_test_classes/base/layer_test_utils.hpp>

namespace ov::test {

struct ScheduleSubGraphTestParams {
    ov::Shape _in_dims;
    ov::Shape _w_dims;
    std::vector<uint64_t> _strides;
    std::vector<int64_t> _pads_begin;
    std::vector<int64_t> _pads_end;
};

class ScheduleSubGraphTest_NPU3700 :
        public VpuOv2LayerTest,
        public testing::WithParamInterface<ScheduleSubGraphTestParams> {
    void SetUp() override {
        const auto test_params = GetParam();
        const ov::Shape inputShape = test_params._in_dims;
        const ov::Shape weightsShape = test_params._w_dims;

        init_input_shapes(static_shapes_to_test_representation({inputShape}));

        const ov::ParameterVector params = {
                std::make_shared<ov::op::v0::Parameter>(ov::element::f32, inputDynamicShapes.front())};

        const size_t dataLevels = 256;
        const std::vector<float> dataLow = {0.0f};
        const std::vector<float> dataHigh = {255.0f};
        const auto dataFq = ngraph::builder::makeFakeQuantize(params[0], ov::element::f32, dataLevels, {}, dataLow,
                                                              dataHigh, dataLow, dataHigh);

        std::vector<uint64_t> poolStridesVec = {1, 1};
        std::vector<uint64_t> poolKernelVec = {1, 1};
        const ov::Strides poolStrides = poolStridesVec;
        const ov::Shape padsBegin = {0, 0};
        const ov::Shape padsEnd = {0, 0};
        const ov::Shape poolKernel = poolKernelVec;
        const auto pool = std::make_shared<ov::op::v1::MaxPool>(dataFq, poolStrides, padsBegin, padsEnd, poolKernel);

        std::vector<float> weights(weightsShape[0] * weightsShape[1] * weightsShape[2] * weightsShape[3]);
        for (std::size_t i = 0; i < weights.size(); i++) {
            weights.at(i) = i / 6;
        }
        auto weightsFP32 =
                std::make_shared<ov::op::v0::Constant>(ov::element::Type_t::f32, weightsShape, weights.data());

        const size_t weightsLevels = 255;

        const auto weightsInLow = ngraph::builder::makeConstant<float>(ov::element::f32, {1}, {0.0f}, false);
        const auto weightsInHigh = ngraph::builder::makeConstant<float>(ov::element::f32, {1}, {255.0f}, false);

        std::vector<float> perChannelLow(weightsShape[0]);
        std::vector<float> perChannelHigh(weightsShape[0]);

        for (size_t i = 0; i < weightsShape[0]; ++i) {
            perChannelLow[i] = 0.0f;
            perChannelHigh[i] = 255.0f;
        }

        const auto weightsOutLow = ngraph::builder::makeConstant<float>(ov::element::f32, {weightsShape[0], 1, 1, 1},
                                                                        perChannelLow, false);
        const auto weightsOutHigh = ngraph::builder::makeConstant<float>(ov::element::f32, {weightsShape[0], 1, 1, 1},
                                                                         perChannelHigh, false);

        const auto weightsFq = std::make_shared<ov::op::v0::FakeQuantize>(weightsFP32, weightsInLow, weightsInHigh,
                                                                          weightsOutLow, weightsOutHigh, weightsLevels);

        const ov::Strides strides = test_params._strides;
        const ov::CoordinateDiff pads_begin = test_params._pads_begin;
        const ov::CoordinateDiff pads_end = test_params._pads_end;
        const ov::Strides dilations = {1, 1};
        const auto conv =
                std::make_shared<ov::op::v1::Convolution>(pool, weightsFq, strides, pads_begin, pads_end, dilations);

        const std::vector<float> outLow = {0.0f};
        const std::vector<float> outHigh = {255.0f};
        const auto result = ngraph::builder::makeFakeQuantize(conv, ov::element::f32, dataLevels, {}, outLow, outHigh,
                                                              outLow, outHigh);

        const ov::ResultVector results{std::make_shared<ov::op::v0::Result>(result)};
        function = std::make_shared<ov::Model>(results, params, "ScheduleSubGraphTest");
        rel_threshold = 0.1f;
    }
};

TEST_P(ScheduleSubGraphTest_NPU3700, HW) {
    setDefaultHardwareMode();
    run(VPUXPlatform::VPU3700);
}

INSTANTIATE_TEST_CASE_P(smoke, ScheduleSubGraphTest_NPU3700,
                        ::testing::Values(ScheduleSubGraphTestParams{
                                {1, 16, 16, 16},  // in dims
                                {16, 16, 1, 1},   // weights dims
                                {1, 1},           // strides
                                {0, 0},           // pads_begin
                                {0, 0},           // pads_end
                        }));

}  // namespace ov::test
