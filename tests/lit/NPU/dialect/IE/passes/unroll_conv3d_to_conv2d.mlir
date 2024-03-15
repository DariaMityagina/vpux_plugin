//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --unroll-conv3d-to-conv2d %s | FileCheck %s
// REQUIRES: arch-VPUX37XX


// CHECK-LABEL: @ConvertNceOpsTo4DConvolution3DCommonCase
func.func @ConvertNceOpsTo4DConvolution3DCommonCase(%arg0: tensor<1x1x3x56x56xf16>) -> tensor<1x32x3x28x28xf16> {
    %FILTERS = const.Declare tensor<32x1x1x3x3xf16> = dense<1.000000e+00> : tensor<32x1x1x3x3xf16>
    %RESULT = IE.Convolution(%arg0, %FILTERS) {dilations = [1, 1, 1], pads_begin = [0, 1, 1], pads_end = [0, 1, 1], strides = [1, 2, 2]} : tensor<1x1x3x56x56xf16>, tensor<32x1x1x3x3xf16> -> tensor<1x32x3x28x28xf16>

    return %RESULT : tensor<1x32x3x28x28xf16>

    // CHECK-DAG:   [[CST_WEIGHTS:%.*]] = const.Declare tensor<32x1x3x3xf16> = dense<1.000000e+00> : tensor<32x1x3x3xf16>
    // CHECK:       [[SLICE_0:%.+]] = IE.Slice {{[^:]+}} [0, 0, 0, 0, 0] [1, 1, 1, 56, 56] : tensor<1x1x3x56x56xf16> to tensor<1x1x1x56x56xf16>
    // CHECK:       [[RESHAPE_0:%.+]] = IE.Reshape([[SLICE_0]]) {shape_value = [1, 1, 56, 56]} : tensor<1x1x1x56x56xf16> -> tensor<1x1x56x56xf16>
    // CHECK:       [[CONV_0:%.+]] = IE.Convolution([[RESHAPE_0]], [[CST_WEIGHTS]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [1, 1], strides = [2, 2]} : tensor<1x1x56x56xf16>, tensor<32x1x3x3xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_1:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 1, 1, 56, 56] : tensor<1x1x3x56x56xf16> to tensor<1x1x1x56x56xf16>
    // CHECK:       [[RESHAPE_1:%.+]] = IE.Reshape([[SLICE_1]]) {shape_value = [1, 1, 56, 56]} : tensor<1x1x1x56x56xf16> -> tensor<1x1x56x56xf16>
    // CHECK:       [[CONV_1:%.+]] = IE.Convolution([[RESHAPE_1]], [[CST_WEIGHTS]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [1, 1], strides = [2, 2]} : tensor<1x1x56x56xf16>, tensor<32x1x3x3xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_2:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 1, 1, 56, 56] : tensor<1x1x3x56x56xf16> to tensor<1x1x1x56x56xf16>
    // CHECK:       [[RESHAPE_2:%.+]] = IE.Reshape([[SLICE_2]]) {shape_value = [1, 1, 56, 56]} : tensor<1x1x1x56x56xf16> -> tensor<1x1x56x56xf16>
    // CHECK:       [[CONV_2:%.+]] = IE.Convolution([[RESHAPE_2]], [[CST_WEIGHTS]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [1, 1], strides = [2, 2]} : tensor<1x1x56x56xf16>, tensor<32x1x3x3xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[RESHAPE_3:%.+]] = IE.Reshape([[CONV_0]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>
    // CHECK:       [[RESHAPE_4:%.+]] = IE.Reshape([[CONV_1]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>
    // CHECK:       [[RESHAPE_5:%.+]] = IE.Reshape([[CONV_2]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>
    // CHECK:       [[CONCAT:%.+]] = IE.Concat([[RESHAPE_3]], [[RESHAPE_4]], [[RESHAPE_5]]) {per_axis = #IE.Concat<axis = 2 : i64>} : tensor<1x32x1x784xf16>, tensor<1x32x1x784xf16>, tensor<1x32x1x784xf16> -> tensor<1x32x3x784xf16>
    // CHECK:       [[RESHAPE_6:%.+]] = IE.Reshape([[CONCAT]]) {shape_value = [1, 32, 3, 28, 28]} : tensor<1x32x3x784xf16> -> tensor<1x32x3x28x28xf16>

    // CHECK:       return [[RESHAPE_6]]

}

// -----

// CHECK-LABEL: @ConvertNceOpsTo4DConvolution3DCommonCaseNoPad
func.func @ConvertNceOpsTo4DConvolution3DCommonCaseNoPad(%arg0: tensor<1x32x5x28x28xf16>) -> tensor<1x32x3x27x27xf16> {
    %FILTERS = const.Declare tensor<32x32x3x2x2xf16> = dense<1.000000e+00> : tensor<32x32x3x2x2xf16>
    %RESULT = IE.Convolution(%arg0, %FILTERS) {dilations = [1, 1, 1], pads_begin = [0, 0, 0], pads_end = [0, 0, 0], strides = [1, 1, 1]} : tensor<1x32x5x28x28xf16>, tensor<32x32x3x2x2xf16> -> tensor<1x32x3x27x27xf16>

    return %RESULT : tensor<1x32x3x27x27xf16>

    // CHECK-DAG:   [[CST_WEIGHTS_0:%.*]] = const.Declare tensor<32x32x2x2xf16> = dense<1.000000e+00> : tensor<32x32x2x2xf16>
    // CHECK-DAG:   [[CST_WEIGHTS_1:%.*]] = const.Declare tensor<32x32x2x2xf16> = dense<1.000000e+00> : tensor<32x32x2x2xf16>
    // CHECK-DAG:   [[CST_WEIGHTS_2:%.*]] = const.Declare tensor<32x32x2x2xf16> = dense<1.000000e+00> : tensor<32x32x2x2xf16>

    // CHECK:       [[SLICE_0:%.+]] = IE.Slice {{[^:]+}} [0, 0, 0, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_0:%.+]] = IE.Reshape([[SLICE_0]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_0:%.+]] = IE.Convolution([[RESHAPE_0]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[SLICE_1:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_1:%.+]] = IE.Reshape([[SLICE_1]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_1:%.+]] = IE.Convolution([[RESHAPE_1]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[SLICE_2:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_2:%.+]] = IE.Reshape([[SLICE_2]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_2:%.+]] = IE.Convolution([[RESHAPE_2]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[ADD_1:%.+]] = IE.Add([[CONV_0]], [[CONV_1]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x27x27xf16>, tensor<1x32x27x27xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[ADD_2:%.+]] = IE.Add([[ADD_1]], [[CONV_2]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x27x27xf16>, tensor<1x32x27x27xf16> -> tensor<1x32x27x27xf16>

    // CHECK:       [[SLICE_3:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_3:%.+]] = IE.Reshape([[SLICE_3]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_3:%.+]] = IE.Convolution([[RESHAPE_3]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[SLICE_4:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_4:%.+]] = IE.Reshape([[SLICE_4]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_4:%.+]] = IE.Convolution([[RESHAPE_4]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[SLICE_5:%.+]] = IE.Slice {{[^:]+}} [0, 0, 3, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_5:%.+]] = IE.Reshape([[SLICE_5]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_5:%.+]] = IE.Convolution([[RESHAPE_5]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[ADD_3:%.+]] = IE.Add([[CONV_3]], [[CONV_4]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x27x27xf16>, tensor<1x32x27x27xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[ADD_4:%.+]] = IE.Add([[ADD_3]], [[CONV_5]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x27x27xf16>, tensor<1x32x27x27xf16> -> tensor<1x32x27x27xf16>

    // CHECK:       [[SLICE_6:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_6:%.+]] = IE.Reshape([[SLICE_6]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_6:%.+]] = IE.Convolution([[RESHAPE_6]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[SLICE_7:%.+]] = IE.Slice {{[^:]+}} [0, 0, 3, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_7:%.+]] = IE.Reshape([[SLICE_7]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_7:%.+]] = IE.Convolution([[RESHAPE_7]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[SLICE_8:%.+]] = IE.Slice {{[^:]+}} [0, 0, 4, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_8:%.+]] = IE.Reshape([[SLICE_8]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_8:%.+]] = IE.Convolution([[RESHAPE_8]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[ADD_5:%.+]] = IE.Add([[CONV_6]], [[CONV_7]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x27x27xf16>, tensor<1x32x27x27xf16> -> tensor<1x32x27x27xf16>
    // CHECK:       [[ADD_6:%.+]] = IE.Add([[ADD_5]], [[CONV_8]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x27x27xf16>, tensor<1x32x27x27xf16> -> tensor<1x32x27x27xf16>

    // CHECK:       [[RESHAPE_9:%.+]] = IE.Reshape([[ADD_2]]) {shape_value = [1, 32, 1, 729]} : tensor<1x32x27x27xf16> -> tensor<1x32x1x729xf16>
    // CHECK:       [[RESHAPE_10:%.+]] = IE.Reshape([[ADD_4]]) {shape_value = [1, 32, 1, 729]} : tensor<1x32x27x27xf16> -> tensor<1x32x1x729xf16>
    // CHECK:       [[RESHAPE_11:%.+]] = IE.Reshape([[ADD_6]]) {shape_value = [1, 32, 1, 729]} : tensor<1x32x27x27xf16> -> tensor<1x32x1x729xf16>
    // CHECK:       [[CONCAT:%.+]] = IE.Concat([[RESHAPE_9]], [[RESHAPE_10]], [[RESHAPE_11]]) {per_axis = #IE.Concat<axis = 2 : i64>} : tensor<1x32x1x729xf16>, tensor<1x32x1x729xf16>, tensor<1x32x1x729xf16> -> tensor<1x32x3x729xf16>
    // CHECK:       [[RESHAPE_12:%.+]] = IE.Reshape([[CONCAT]]) {shape_value = [1, 32, 3, 27, 27]} : tensor<1x32x3x729xf16> -> tensor<1x32x3x27x27xf16>

    // CHECK:       return [[RESHAPE_12]]
}


// -----

// CHECK-LABEL: @ConvertNceOpsTo4DConvolution3DOnlyDepth
func.func @ConvertNceOpsTo4DConvolution3DOnlyDepth(%arg0: tensor<1x32x5x28x28xf16>) -> tensor<1x32x5x28x28xf16> {
    %FILTERS = const.Declare tensor<32x32x3x2x2xf16> = dense<1.000000e+00> : tensor<32x32x3x2x2xf16>
    %RESULT = IE.Convolution(%arg0, %FILTERS) {dilations = [1, 1, 1], pads_begin = [1, 1, 1], pads_end = [1, 0, 0], strides = [1, 1, 1]} : tensor<1x32x5x28x28xf16>, tensor<32x32x3x2x2xf16> -> tensor<1x32x5x28x28xf16>

    return %RESULT : tensor<1x32x5x28x28xf16>

    // CHECK-DAG:   [[CST_WEIGHTS_0:%.*]] = const.Declare tensor<32x32x2x2xf16> = dense<1.000000e+00> : tensor<32x32x2x2xf16>
    // CHECK-DAG:   [[CST_WEIGHTS_1:%.*]] = const.Declare tensor<32x32x2x2xf16> = dense<1.000000e+00> : tensor<32x32x2x2xf16>
    // CHECK-DAG:   [[CST_WEIGHTS_2:%.*]] = const.Declare tensor<32x32x2x2xf16> = dense<1.000000e+00> : tensor<32x32x2x2xf16>

    // CHECK:       [[SLICE_0:%.+]] = IE.Slice {{[^:]+}} [0, 0, 0, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_0:%.+]] = IE.Reshape([[SLICE_0]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_0:%.+]] = IE.Convolution([[RESHAPE_0]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_1:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_1:%.+]] = IE.Reshape([[SLICE_1]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_1:%.+]] = IE.Convolution([[RESHAPE_1]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_0:%.+]] = IE.Add([[CONV_0]], [[CONV_1]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>

    // CHECK:       [[SLICE_2:%.+]] = IE.Slice {{[^:]+}} [0, 0, 0, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_2:%.+]] = IE.Reshape([[SLICE_2]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_2:%.+]] = IE.Convolution([[RESHAPE_2]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_3:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_3:%.+]] = IE.Reshape([[SLICE_3]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_3:%.+]] = IE.Convolution([[RESHAPE_3]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_4:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_4:%.+]] = IE.Reshape([[SLICE_4]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_4:%.+]] = IE.Convolution([[RESHAPE_4]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_1:%.+]] = IE.Add([[CONV_2]], [[CONV_3]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_2:%.+]] = IE.Add([[ADD_1]], [[CONV_4]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>

    // CHECK:       [[SLICE_5:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_5:%.+]] = IE.Reshape([[SLICE_5]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_5:%.+]] = IE.Convolution([[RESHAPE_5]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_6:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_6:%.+]] = IE.Reshape([[SLICE_6]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_6:%.+]] = IE.Convolution([[RESHAPE_6]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_7:%.+]] = IE.Slice {{[^:]+}} [0, 0, 3, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_7:%.+]] = IE.Reshape([[SLICE_7]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_7:%.+]] = IE.Convolution([[RESHAPE_7]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_3:%.+]] = IE.Add([[CONV_5]], [[CONV_6]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_4:%.+]] = IE.Add([[ADD_3]], [[CONV_7]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>

    // CHECK:       [[SLICE_8:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_8:%.+]] = IE.Reshape([[SLICE_8]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_8:%.+]] = IE.Convolution([[RESHAPE_8]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_9:%.+]] = IE.Slice {{[^:]+}} [0, 0, 3, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_9:%.+]] = IE.Reshape([[SLICE_9]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_9:%.+]] = IE.Convolution([[RESHAPE_9]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_10:%.+]] = IE.Slice {{[^:]+}} [0, 0, 4, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_10:%.+]] = IE.Reshape([[SLICE_10]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_10:%.+]] = IE.Convolution([[RESHAPE_10]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_5:%.+]] = IE.Add([[CONV_8]], [[CONV_9]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_6:%.+]] = IE.Add([[ADD_5]], [[CONV_10]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>

    // CHECK:       [[SLICE_11:%.+]] = IE.Slice {{[^:]+}} [0, 0, 3, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_11:%.+]] = IE.Reshape([[SLICE_11]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_11:%.+]] = IE.Convolution([[RESHAPE_11]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[SLICE_12:%.+]] = IE.Slice {{[^:]+}} [0, 0, 4, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_12:%.+]] = IE.Reshape([[SLICE_12]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_12:%.+]] = IE.Convolution([[RESHAPE_12]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [0, 0], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x2x2xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[ADD_7:%.+]] = IE.Add([[CONV_11]], [[CONV_12]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x28xf16>, tensor<1x32x28x28xf16> -> tensor<1x32x28x28xf16>

    // CHECK:       [[RESHAPE_13:%.+]] = IE.Reshape([[ADD_0]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>
    // CHECK:       [[RESHAPE_14:%.+]] = IE.Reshape([[ADD_2]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>
    // CHECK:       [[RESHAPE_15:%.+]] = IE.Reshape([[ADD_4]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>
    // CHECK:       [[RESHAPE_16:%.+]] = IE.Reshape([[ADD_6]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>
    // CHECK:       [[RESHAPE_17:%.+]] = IE.Reshape([[ADD_7]]) {shape_value = [1, 32, 1, 784]} : tensor<1x32x28x28xf16> -> tensor<1x32x1x784xf16>

    // CHECK:       [[CONCAT:%.+]] = IE.Concat([[RESHAPE_13]], [[RESHAPE_14]], [[RESHAPE_15]], [[RESHAPE_16]], [[RESHAPE_17]]) {per_axis = #IE.Concat<axis = 2 : i64>} : tensor<1x32x1x784xf16>, tensor<1x32x1x784xf16>, tensor<1x32x1x784xf16>, tensor<1x32x1x784xf16>, tensor<1x32x1x784xf16> -> tensor<1x32x5x784xf16>
    // CHECK:       [[RESHAPE_18:%.+]] = IE.Reshape([[CONCAT]]) {shape_value = [1, 32, 5, 28, 28]} : tensor<1x32x5x784xf16> -> tensor<1x32x5x28x28xf16>

    // CHECK:       return [[RESHAPE_18]]

}

// -----

// CHECK-LABEL: @ConvertNceOpsTo4DConvolution3DWithStride
func.func @ConvertNceOpsTo4DConvolution3DWithStride(%arg0: tensor<1x32x5x28x28xf16>) -> tensor<1x32x3x28x29xf16> {
    %FILTERS = const.Declare tensor<32x32x3x1x1xf16> = dense<1.000000e+00> : tensor<32x32x3x1x1xf16>
    %RESULT = IE.Convolution(%arg0, %FILTERS) {dilations = [1, 1, 1], pads_begin = [1, 0, 0], pads_end = [1, 0, 1], strides = [2, 1, 1]} : tensor<1x32x5x28x28xf16>, tensor<32x32x3x1x1xf16> -> tensor<1x32x3x28x29xf16>

    return %RESULT : tensor<1x32x3x28x29xf16>

    // CHECK-DAG:   [[CST_WEIGHTS_0:%.*]] = const.Declare tensor<32x32x1x1xf16> = dense<1.000000e+00> : tensor<32x32x1x1xf16>
    // CHECK-DAG:   [[CST_WEIGHTS_1:%.*]] = const.Declare tensor<32x32x1x1xf16> = dense<1.000000e+00> : tensor<32x32x1x1xf16>
    // CHECK-DAG:   [[CST_WEIGHTS_2:%.*]] = const.Declare tensor<32x32x1x1xf16> = dense<1.000000e+00> : tensor<32x32x1x1xf16>

    // CHECK:       [[SLICE_0:%.+]] = IE.Slice {{[^:]+}} [0, 0, 0, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_0:%.+]] = IE.Reshape([[SLICE_0]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_0:%.+]] = IE.Convolution([[RESHAPE_0]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 1], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x1x1xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[SLICE_1:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_1:%.+]] = IE.Reshape([[SLICE_1]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_1:%.+]] = IE.Convolution([[RESHAPE_1]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 1], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x1x1xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[ADD_0:%.+]] = IE.Add([[CONV_0]], [[CONV_1]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x29xf16>, tensor<1x32x28x29xf16> -> tensor<1x32x28x29xf16>

    // CHECK:       [[SLICE_2:%.+]] = IE.Slice {{[^:]+}} [0, 0, 1, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_2:%.+]] = IE.Reshape([[SLICE_2]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_2:%.+]] = IE.Convolution([[RESHAPE_2]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 1], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x1x1xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[SLICE_3:%.+]] = IE.Slice {{[^:]+}} [0, 0, 2, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_3:%.+]] = IE.Reshape([[SLICE_3]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_3:%.+]] = IE.Convolution([[RESHAPE_3]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 1], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x1x1xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[SLICE_4:%.+]] = IE.Slice {{[^:]+}} [0, 0, 3, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_4:%.+]] = IE.Reshape([[SLICE_4]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_4:%.+]] = IE.Convolution([[RESHAPE_4]], [[CST_WEIGHTS_2]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 1], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x1x1xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[ADD_1:%.+]] = IE.Add([[CONV_2]], [[CONV_3]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x29xf16>, tensor<1x32x28x29xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[ADD_2:%.+]] = IE.Add([[ADD_1]], [[CONV_4]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x29xf16>, tensor<1x32x28x29xf16> -> tensor<1x32x28x29xf16>

    // CHECK:       [[SLICE_5:%.+]] = IE.Slice {{[^:]+}} [0, 0, 3, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_5:%.+]] = IE.Reshape([[SLICE_5]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_5:%.+]] = IE.Convolution([[RESHAPE_5]], [[CST_WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 1], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x1x1xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[SLICE_6:%.+]] = IE.Slice {{[^:]+}} [0, 0, 4, 0, 0] [1, 32, 1, 28, 28] : tensor<1x32x5x28x28xf16> to tensor<1x32x1x28x28xf16>
    // CHECK:       [[RESHAPE_6:%.+]] = IE.Reshape([[SLICE_6]]) {shape_value = [1, 32, 28, 28]} : tensor<1x32x1x28x28xf16> -> tensor<1x32x28x28xf16>
    // CHECK:       [[CONV_6:%.+]] = IE.Convolution([[RESHAPE_6]], [[CST_WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 1], strides = [1, 1]} : tensor<1x32x28x28xf16>, tensor<32x32x1x1xf16> -> tensor<1x32x28x29xf16>
    // CHECK:       [[ADD_3:%.+]] = IE.Add([[CONV_5]], [[CONV_6]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x32x28x29xf16>, tensor<1x32x28x29xf16> -> tensor<1x32x28x29xf16>

    // CHECK:       [[RESHAPE_7:%.+]] = IE.Reshape([[ADD_0]]) {shape_value = [1, 32, 1, 812]} : tensor<1x32x28x29xf16> -> tensor<1x32x1x812xf16>
    // CHECK:       [[RESHAPE_8:%.+]] = IE.Reshape([[ADD_2]]) {shape_value = [1, 32, 1, 812]} : tensor<1x32x28x29xf16> -> tensor<1x32x1x812xf16>
    // CHECK:       [[RESHAPE_9:%.+]] = IE.Reshape([[ADD_3]]) {shape_value = [1, 32, 1, 812]} : tensor<1x32x28x29xf16> -> tensor<1x32x1x812xf16>
    // CHECK:       [[CONCAT:%.+]] = IE.Concat([[RESHAPE_7]], [[RESHAPE_8]], [[RESHAPE_9]]) {per_axis = #IE.Concat<axis = 2 : i64>} : tensor<1x32x1x812xf16>, tensor<1x32x1x812xf16>, tensor<1x32x1x812xf16> -> tensor<1x32x3x812xf16>
    // CHECK:       [[RESHAPE_10:%.+]] = IE.Reshape([[CONCAT]]) {shape_value = [1, 32, 3, 28, 29]} : tensor<1x32x3x812xf16> -> tensor<1x32x3x28x29xf16>

    // CHECK:       return [[RESHAPE_10]]
}

// -----

// CHECK-LABEL: @ConvertNceOpsTo4DConvolution5DAggregateHW
func.func @ConvertNceOpsTo4DConvolution5DAggregateHW(%arg0: tensor<1x1x16x16x64xf16>) -> tensor<1x1x16x16x64xf16> {
    %FILTERS = const.Declare tensor<1x1x2x1x1xf16> = dense<1.000000e+00> : tensor<1x1x2x1x1xf16>
    %RESULT = IE.Convolution(%arg0, %FILTERS) {dilations = [1,1,1], pads_begin = [1,0,0], pads_end = [0,0,0], strides = [1,1,1]} : tensor<1x1x16x16x64xf16>, tensor<1x1x2x1x1xf16> -> tensor<1x1x16x16x64xf16>
    return %RESULT : tensor<1x1x16x16x64xf16>
    // CHECK:       %[[RESHAPE:.*]] = IE.Reshape(%arg0) {shape_value = [1, 1, 16, 1024]} : tensor<1x1x16x16x64xf16> -> tensor<1x1x16x1024xf16>
    // CHECK:       %[[CST:.*]] = const.Declare tensor<1x1x2x1xf16> = dense<1.000000e+00> : tensor<1x1x2x1x1xf16>, [#const.Reshape<[1, 1, 2, 1]>]
    // CHECK:       %[[VAL0:.*]] = IE.Convolution
    // CHECK-SAME:      dilations = [1, 1]
    // CHECK-SAME:      pads_begin = [1, 0]
    // CHECK-SAME:      pads_end = [0, 0]
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      tensor<1x1x16x1024xf16>, tensor<1x1x2x1xf16> -> tensor<1x1x16x1024xf16>
    // CHECK:       %[[RESULT:.*]] = IE.Reshape(%[[VAL0]]) {shape_value = [1, 1, 16, 16, 64]} : tensor<1x1x16x1024xf16> -> tensor<1x1x16x16x64xf16>
    // CHECK:       return %[[RESULT]]
}

// -----

// CHECK-LABEL: @ConvertNceOpsTo4DConvolution5DAggregateDH
func.func @ConvertNceOpsTo4DConvolution5DAggregateDH(%arg0: tensor<1x16x16x16x16xf16>) -> tensor<1x16x16x16x16xf16> {
    %FILTERS = const.Declare tensor<16x16x1x1x1xf16> = dense<1.000000e+00> : tensor<16x16x1x1x1xf16>
    %RESULT = IE.Convolution(%arg0, %FILTERS) {dilations = [1,1,1], pads_begin = [0,0,0], pads_end = [0,0,0], strides = [1,1,1]} : tensor<1x16x16x16x16xf16>, tensor<16x16x1x1x1xf16> -> tensor<1x16x16x16x16xf16>
    return %RESULT : tensor<1x16x16x16x16xf16>
    // CHECK:       %[[RESHAPE:.*]] = IE.Reshape(%arg0) {shape_value = [1, 16, 256, 16]} : tensor<1x16x16x16x16xf16> -> tensor<1x16x256x16xf16>
    // CHECK:       %[[CST:.*]] = const.Declare tensor<16x16x1x1xf16> = dense<1.000000e+00> : tensor<16x16x1x1x1xf16>, [#const.Reshape<[16, 16, 1, 1]>]
    // CHECK:       %[[VAL0:.*]] = IE.Convolution
    // CHECK-SAME:      dilations = [1, 1]
    // CHECK-SAME:      pads_begin = [0, 0]
    // CHECK-SAME:      pads_end = [0, 0]
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      tensor<1x16x256x16xf16>, tensor<16x16x1x1xf16> -> tensor<1x16x256x16xf16>
    // CHECK:       %[[RESULT:.*]] = IE.Reshape(%[[VAL0]]) {shape_value = [1, 16, 16, 16, 16]} : tensor<1x16x256x16xf16> -> tensor<1x16x16x16x16xf16>
    // CHECK:       return %[[RESULT]]
}
