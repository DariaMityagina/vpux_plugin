//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --debatcher %s | FileCheck %s
// REQUIRES: arch-NPU40XX

// CHECK-LABEL: @SingleInputSingleOutputBatched
func.func @SingleInputSingleOutputBatched(%arg: tensor<3x3x62x62xf32>) -> tensor<3x48x60x60xf32> {
    %cst = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
    %0 = IE.Convolution(%arg, %cst) {
        dilations = [1, 1],
        pads_begin = [0, 0],
        pads_end = [0, 0],
        strides = [1, 1]
    } : tensor<3x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<3x48x60x60xf32>
    %1 = IE.SoftMax(%0) {axisInd = 3 : i64} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
    return %1 : tensor<3x48x60x60xf32>

    // CHECK-DAG: [[VAL0:%0]] = builtin.unrealized_conversion_cast %arg0 : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
    // CHECK: [[VAL1:%1]] = IE.Convolution([[VAL0]], %cst) {
    // CHECK-SAME:              dilations = [1, 1],
    // CHECK-SAME:              pads_begin = [0, 0],
    // CHECK-SAME:              pads_end = [0, 0],
    // CHECK-SAME:              strides = [1, 1]
    // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL2:%2]] = IE.SoftMax([[VAL1]]) {axisInd = 3 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL3:%3]] = builtin.unrealized_conversion_cast [[VAL2]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
    // CHECK: return [[VAL3]] : tensor<3x48x60x60xf32>
}

// -----

// CHECK-LABEL: @SingleInputSingleOutputReshapeAttributeBatched
func.func @SingleInputSingleOutputReshapeAttributeBatched(%arg: tensor<3x3x62x62xf32>) -> tensor<3x48x60x60xf32> {
    %cst = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
    %0 = IE.Convolution(%arg, %cst) {
        dilations = [1, 1],
        pads_begin = [0, 0],
        pads_end = [0, 0],
        strides = [1, 1]
    } : tensor<3x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<3x48x60x60xf32>
    %1 = IE.Reshape(%0) {shape_value = [3, 48, 3600, 1]} : tensor<3x48x60x60xf32> -> tensor<3x48x3600x1xf32>
    %2 = IE.Reshape(%1) {shape_value = [3, 48, 60, 60]} : tensor<3x48x3600x1xf32> -> tensor<3x48x60x60xf32>
    %3 = IE.SoftMax(%2) {axisInd = 3 : i64} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
    return %3 : tensor<3x48x60x60xf32>

    // CHECK-DAG: [[VAL0:%0]] = builtin.unrealized_conversion_cast %arg0 : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
    // CHECK: [[VAL1:%1]] = IE.Convolution([[VAL0]], %cst) {
    // CHECK-SAME:              dilations = [1, 1],
    // CHECK-SAME:              pads_begin = [0, 0],
    // CHECK-SAME:              pads_end = [0, 0],
    // CHECK-SAME:              strides = [1, 1]
    // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL2:%2]] = IE.Reshape([[VAL1]]) {shape_value = [1, 48, 3600, 1]} : tensor<1x48x60x60xf32> -> tensor<1x48x3600x1xf32>
    // CHECK: [[VAL3:%3]] = IE.Reshape([[VAL2]]) {shape_value = [1, 48, 60, 60]} : tensor<1x48x3600x1xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL4:%4]] = IE.SoftMax([[VAL3]]) {axisInd = 3 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL5:%5]] = builtin.unrealized_conversion_cast [[VAL4]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
    // CHECK: return [[VAL5]] : tensor<3x48x60x60xf32>
}

// -----

// CHECK-LABEL: @SingleInputSingleOutputFirstReshapeAttributeBatched
func.func @SingleInputSingleOutputFirstReshapeAttributeBatched(%arg: tensor<3x3x62x62xf32>) -> tensor<3x3x62x62xf32> {
    %0 = IE.Reshape(%arg) {shape_value = [3, 3, 3844, 1]} : tensor<3x3x62x62xf32> -> tensor<3x3x3844x1xf32>
    %1 = IE.Reshape(%0) {shape_value = [3, 3, 62, 62]} : tensor<3x3x3844x1xf32> -> tensor<3x3x62x62xf32>
    %2 = IE.SoftMax(%1) {axisInd = 3 : i64} : tensor<3x3x62x62xf32> -> tensor<3x3x62x62xf32>
    return %2 : tensor<3x3x62x62xf32>

    // CHECK-DAG: [[VAL0:%0]] = builtin.unrealized_conversion_cast %arg0 : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
    // CHECK: [[VAL1:%1]] = IE.Reshape([[VAL0]]) {shape_value = [1, 3, 3844, 1]} : tensor<1x3x62x62xf32> -> tensor<1x3x3844x1xf32>
    // CHECK: [[VAL2:%2]] = IE.Reshape([[VAL1]]) {shape_value = [1, 3, 62, 62]} : tensor<1x3x3844x1xf32> -> tensor<1x3x62x62xf32>
    // CHECK: [[VAL3:%3]] = IE.SoftMax([[VAL2]]) {axisInd = 3 : i64} : tensor<1x3x62x62xf32> -> tensor<1x3x62x62xf32>
    // CHECK: [[VAL4:%4]] = builtin.unrealized_conversion_cast [[VAL3]] : tensor<1x3x62x62xf32> to tensor<3x3x62x62xf32>
    // CHECK: return [[VAL4]] : tensor<3x3x62x62xf32>
}

// -----

// CHECK-LABEL: @SingleInputSingleOutputAffineReshapeAttributeBatched
func.func @SingleInputSingleOutputAffineReshapeAttributeBatched(%arg: tensor<3x3x62x62xf32>) -> tensor<3x48x60x60xf32> {
    %cst = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
    %0 = IE.Convolution(%arg, %cst) {
        dilations = [1, 1],
        pads_begin = [0, 0],
        pads_end = [0, 0],
        strides = [1, 1]
    } : tensor<3x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<3x48x60x60xf32>
    %1 = VPU.AffineReshape(%0) {dim_mapping = [[0], [0], [0], [1]], shape_value = [8640, 60]} :
        tensor<3x48x60x60xf32> -> tensor<8640x60xf32>
    %2 = VPU.AffineReshape(%1) {dim_mapping = [[0, 1], [2, 3]], shape_value = [3, 48, 60, 60]} :
        tensor<8640x60xf32> -> tensor<3x48x60x60xf32>
    %3 = IE.SoftMax(%2) {axisInd = 3 : i64} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
    return %3 : tensor<3x48x60x60xf32>

    // CHECK-DAG: [[VAL0:%0]] = builtin.unrealized_conversion_cast %arg0 : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
    // CHECK: [[VAL1:%1]] = IE.Convolution([[VAL0]], %cst) {
    // CHECK-SAME:              dilations = [1, 1],
    // CHECK-SAME:              pads_begin = [0, 0],
    // CHECK-SAME:              pads_end = [0, 0],
    // CHECK-SAME:              strides = [1, 1]
    // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL2:%2]] = VPU.AffineReshape([[VAL1]])
    // CHECK-SAME{LITERAL}:    {dim_mapping = [[0], [0], [0], [1]], shape_value = [2880, 60]} :
    // CHECK-SAME:    tensor<1x48x60x60xf32> -> tensor<2880x60xf32>
    // CHECK: [[VAL3:%3]] = VPU.AffineReshape([[VAL2]])
    // CHECK-SAME{LITERAL}:    {dim_mapping = [[0, 1], [2, 3]], shape_value = [1, 48, 60, 60]} :
    // CHECK-SAME:    tensor<2880x60xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL4:%4]] = IE.SoftMax([[VAL3]]) {axisInd = 3 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL5:%5]] = builtin.unrealized_conversion_cast [[VAL4]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
    // CHECK: return [[VAL5]] : tensor<3x48x60x60xf32>
}

// -----

// CHECK-LABEL: @SingleInputSingleOutputFirstInterpolateAttributeNonBatched
// CHECK-SAME:     ([[ARG0:%.+]]: tensor<3x3x62x62xf32>)
func.func @SingleInputSingleOutputFirstInterpolateAttributeNonBatched(%arg0: tensor<3x3x62x62xf32>) -> tensor<3x3x124x124xf32> {
    %0 = IE.Interpolate(%arg0) {attr = #IE.Interpolate<mode = <NEAREST>, shape_calc_mode = <SIZES>, coord_mode = <ASYMMETRIC>, nearest_mode = <FLOOR>, antialias = false, pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0], cube_coeff = -7.500000e-01 : f64>, axes_attr = [2, 3], operandSegmentSizes = array<i32: 1, 0, 0, 0>, scales_attr = [1.000000e+00, 1.000000e+00], sizes_attr = [124, 124]} : tensor<3x3x62x62xf32> -> tensor<3x3x124x124xf32>
    return %0 : tensor<3x3x124x124xf32>

    // CHECK-DAG: [[VAL0:%.+]] = builtin.unrealized_conversion_cast [[ARG0]] : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
    // CHECK: [[VAL1:%.+]] = IE.Interpolate([[VAL0]]) {
    // CHECK-SAME:              attr = #IE.Interpolate<mode = <NEAREST>, shape_calc_mode = <SIZES>,
    // CHECK-SAME:              coord_mode = <ASYMMETRIC>, nearest_mode = <FLOOR>, antialias = false,
    // CHECK-SAME:              pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0],
    // CHECK-SAME:              cube_coeff = -7.500000e-01 : f64>, axes_attr = [2, 3],
    // CHECK-SAME:              operandSegmentSizes = array<i32: 1, 0, 0, 0>,
    // CHECK-SAME:              scales_attr = [1.000000e+00, 1.000000e+00],
    // CHECK-SAME:              sizes_attr = [124, 124]} : tensor<1x3x62x62xf32> -> tensor<1x3x124x124xf32>
    // CHECK: [[VAL2:%.+]] = builtin.unrealized_conversion_cast [[VAL1]] : tensor<1x3x124x124xf32> to tensor<3x3x124x124xf32>
    // CHECK: return [[VAL2]] : tensor<3x3x124x124xf32>
}

// -----

// CHECK-LABEL: @SingleInputSingleOutputFirstInterpolateAttributeBatched
// CHECK-SAME:     ([[ARG0:%.+]]: tensor<3x3x62x62xf32>)
func.func @SingleInputSingleOutputFirstInterpolateAttributeBatched(%arg0: tensor<3x3x62x62xf32>) -> tensor<3x3x124x124xf32> {
    %0 = IE.Interpolate(%arg0) {attr = #IE.Interpolate<mode = <NEAREST>, shape_calc_mode = <SIZES>, coord_mode = <ASYMMETRIC>, nearest_mode = <FLOOR>, antialias = false, pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0], cube_coeff = -7.500000e-01 : f64>, axes_attr = [0, 1, 2, 3], operandSegmentSizes = array<i32: 1, 0, 0, 0>, scales_attr = [1.000000e+00, 1.000000e+00], sizes_attr = [3, 3, 124, 124]} : tensor<3x3x62x62xf32> -> tensor<3x3x124x124xf32>
    return %0 : tensor<3x3x124x124xf32>

    // CHECK-DAG: [[VAL0:%.+]] = builtin.unrealized_conversion_cast [[ARG0]] : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
    // CHECK: [[VAL1:%.+]] = IE.Interpolate([[VAL0]]) {
    // CHECK-SAME:              attr = #IE.Interpolate<mode = <NEAREST>, shape_calc_mode = <SIZES>,
    // CHECK-SAME:              coord_mode = <ASYMMETRIC>, nearest_mode = <FLOOR>, antialias = false,
    // CHECK-SAME:              pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0],
    // CHECK-SAME:              cube_coeff = -7.500000e-01 : f64>, axes_attr = [0, 1, 2, 3],
    // CHECK-SAME:              operandSegmentSizes = array<i32: 1, 0, 0, 0>,
    // CHECK-SAME:              scales_attr = [1.000000e+00, 1.000000e+00],
    // CHECK-SAME:              sizes_attr = [1, 3, 124, 124]} : tensor<1x3x62x62xf32> -> tensor<1x3x124x124xf32>
    // CHECK: [[VAL2:%.+]] = builtin.unrealized_conversion_cast [[VAL1]] : tensor<1x3x124x124xf32> to tensor<3x3x124x124xf32>
    // CHECK: return [[VAL2]] : tensor<3x3x124x124xf32>
}

// -----
// CHECK-LABEL: @SingleInputSingleOutputNonBatched
func.func @SingleInputSingleOutputNonBatched(%arg0: tensor<1x3x62x62xf32>) -> tensor<1x48x60x60xf32> {
    %cst = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
    %0 = IE.Convolution(%arg0, %cst) {
        dilations = [1, 1],
        pads_begin = [0, 0],
        pads_end = [0, 0],
        strides = [1, 1]
    } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
    %1 = IE.SoftMax(%0) {axisInd = 3 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
    return %1 : tensor<1x48x60x60xf32>

    // CHECK: [[VAL1:%0]] = IE.Convolution(%arg0, %cst) {
    // CHECK-SAME:              dilations = [1, 1],
    // CHECK-SAME:              pads_begin = [0, 0],
    // CHECK-SAME:              pads_end = [0, 0],
    // CHECK-SAME:              strides = [1, 1]
    // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL2:%1]] = IE.SoftMax([[VAL1]]) {axisInd = 3 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
    // CHECK: return [[VAL2]] : tensor<1x48x60x60xf32>
}

// -----

// CHECK-LABEL: @SingleInputSingleOutputDoNotDebatchConstantOperands
func.func @SingleInputSingleOutputDoNotDebatchConstantOperands(%arg: tensor<3x3x62x62xf32>) -> tensor<3x48x60x60xf32> {
    %cst0 = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
    %cst1 = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
    %1 = IE.Multiply(%cst0, %cst1) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<48x3x3x3xf32>, tensor<48x3x3x3xf32> -> tensor<48x3x3x3xf32>
    %2 = IE.Multiply(%cst0, %1) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<48x3x3x3xf32>, tensor<48x3x3x3xf32> -> tensor<48x3x3x3xf32>
    %3 = IE.Convolution(%arg, %2) {
        dilations = [1, 1],
        pads_begin = [0, 0],
        pads_end = [0, 0],
        strides = [1, 1]
    } : tensor<3x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<3x48x60x60xf32>
    %4 = IE.SoftMax(%3) {axisInd = 3 : i64} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
    return %4 : tensor<3x48x60x60xf32>

    // CHECK-DAG: [[VAL0:%0]] = builtin.unrealized_conversion_cast %arg0 : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
    // CHECK: [[VAL1:%.+]] = IE.Multiply(%cst, %cst_0) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<48x3x3x3xf32>, tensor<48x3x3x3xf32> -> tensor<48x3x3x3xf32>
    // CHECK: [[VAL11:%.+]] = IE.Multiply(%cst, [[VAL1]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<48x3x3x3xf32>, tensor<48x3x3x3xf32> -> tensor<48x3x3x3xf32>
    // CHECK: [[VAL2:%.+]] = IE.Convolution([[VAL0]], [[VAL11]]) {
    // CHECK-SAME:              dilations = [1, 1],
    // CHECK-SAME:              pads_begin = [0, 0],
    // CHECK-SAME:              pads_end = [0, 0],
    // CHECK-SAME:              strides = [1, 1]
    // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL3:%.+]] = IE.SoftMax([[VAL2]]) {axisInd = 3 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
    // CHECK: [[VAL4:%.+]] = builtin.unrealized_conversion_cast [[VAL3]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
    // CHECK: return [[VAL4]] : tensor<3x48x60x60xf32>
}

// -----

// CHECK-LABEL: @MultipleInputSingleOutputBatched
func.func @MultipleInputSingleOutputBatched(%arg0: tensor<3x3x62x62xf32>, %arg1: tensor<3x48x60x60xf32>) -> tensor<3x48x60x60xf32> {
        %cst = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
        %0 = IE.Convolution(%arg0, %cst) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1]
        } : tensor<3x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<3x48x60x60xf32>
        %1 = IE.SoftMax(%0) {axisInd = 1} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        %2 = IE.Add(%1, %arg1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY> } : tensor<3x48x60x60xf32>, tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        %3 = IE.SoftMax(%2) {axisInd = 1} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        return %3: tensor<3x48x60x60xf32>

        // CHECK-DAG: [[VAL0:%.+]] = builtin.unrealized_conversion_cast %arg0 : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
        // CHECK-DAG: [[VAL1:%.+]] = builtin.unrealized_conversion_cast %arg1 : tensor<3x48x60x60xf32> to tensor<1x48x60x60xf32>
        // CHECK: [[VAL2:%.+]] = IE.Convolution([[VAL0]], %cst) {
        // CHECK-SAME:              dilations = [1, 1],
        // CHECK-SAME:              pads_begin = [0, 0],
        // CHECK-SAME:              pads_end = [0, 0],
        // CHECK-SAME:              strides = [1, 1]
        // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL3:%.+]] = IE.SoftMax([[VAL2]]) {axisInd = 1 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL4:%.+]] = IE.Add([[VAL3]], [[VAL1]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x48x60x60xf32>, tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL5:%.+]] = IE.SoftMax([[VAL4]]) {axisInd = 1 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL6:%.+]] = builtin.unrealized_conversion_cast [[VAL5]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
        // CHECK: return [[VAL6]] : tensor<3x48x60x60xf32>

}

// -----

// CHECK-LABEL: @MultipleInputMultipleOutputBatched
func.func @MultipleInputMultipleOutputBatched(%arg0: tensor<3x3x62x62xf32>, %arg1: tensor<3x48x60x60xf32>) -> (tensor<3x48x60x60xf32>, tensor<3x48x60x60xf32>) {
        %cst = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
        %0 = IE.Convolution(%arg0, %cst) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1]
        } : tensor<3x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<3x48x60x60xf32>
        %1 = IE.SoftMax(%0) {axisInd = 1} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        %2 = IE.Add(%1, %arg1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY> } : tensor<3x48x60x60xf32>, tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        %3 = IE.SoftMax(%2) {axisInd = 1} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        return %3, %1: tensor<3x48x60x60xf32>, tensor<3x48x60x60xf32>

        // CHECK-DAG: [[VAL0:%.+]] = builtin.unrealized_conversion_cast %arg0 : tensor<3x3x62x62xf32> to tensor<1x3x62x62xf32>
        // CHECK-DAG: [[VAL1:%.+]] = builtin.unrealized_conversion_cast %arg1 : tensor<3x48x60x60xf32> to tensor<1x48x60x60xf32>
        // CHECK: [[VAL2:%.+]] = IE.Convolution([[VAL0]], %cst) {
        // CHECK-SAME:              dilations = [1, 1],
        // CHECK-SAME:              pads_begin = [0, 0],
        // CHECK-SAME:              pads_end = [0, 0],
        // CHECK-SAME:              strides = [1, 1]
        // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL3:%.+]] = IE.SoftMax([[VAL2]]) {axisInd = 1 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL4:%.+]] = IE.Add([[VAL3]], [[VAL1]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x48x60x60xf32>, tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL5:%.+]] = IE.SoftMax([[VAL4]]) {axisInd = 1 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL6:%.+]] = builtin.unrealized_conversion_cast [[VAL5]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
        // CHECK: [[VAL7:%.+]] = builtin.unrealized_conversion_cast [[VAL3]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
        // CHECK: return [[VAL6]], [[VAL7]] : tensor<3x48x60x60xf32>, tensor<3x48x60x60xf32>
}

// -----

// CHECK-LABEL: @MultipleInputMultipleOutputMixed
func.func @MultipleInputMultipleOutputMixed(%arg0: tensor<1x3x62x62xf32>, %arg1: tensor<3x48x60x60xf32>) -> (tensor<3x48x60x60xf32>, tensor<1x48x60x60xf32>) {
        %cst = const.Declare tensor<48x3x3x3xf32> = dense<1.0> : tensor<48x3x3x3xf32>
        %0 = IE.Convolution(%arg0, %cst) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1]
        } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
        %1 = IE.SoftMax(%0) {axisInd = 1} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        %2 = IE.Add(%arg1, %arg1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY> } : tensor<3x48x60x60xf32>, tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        %3 = IE.SoftMax(%2) {axisInd = 1} : tensor<3x48x60x60xf32> -> tensor<3x48x60x60xf32>
        return %3, %1: tensor<3x48x60x60xf32>, tensor<1x48x60x60xf32>

        // CHECK-DAG: [[VAL1:%.+]] = builtin.unrealized_conversion_cast %arg1 : tensor<3x48x60x60xf32> to tensor<1x48x60x60xf32>
        // CHECK: [[VAL2:%.+]] = IE.Convolution(%arg0, %cst) {
        // CHECK-SAME:              dilations = [1, 1],
        // CHECK-SAME:              pads_begin = [0, 0],
        // CHECK-SAME:              pads_end = [0, 0],
        // CHECK-SAME:              strides = [1, 1]
        // CHECK-SAME:              } : tensor<1x3x62x62xf32>, tensor<48x3x3x3xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL3:%.+]] = IE.SoftMax([[VAL2]]) {axisInd = 1 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL4:%.+]] = IE.Add([[VAL1]], [[VAL1]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x48x60x60xf32>, tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL5:%.+]] = IE.SoftMax([[VAL4]]) {axisInd = 1 : i64} : tensor<1x48x60x60xf32> -> tensor<1x48x60x60xf32>
        // CHECK: [[VAL6:%.+]] = builtin.unrealized_conversion_cast [[VAL5]] : tensor<1x48x60x60xf32> to tensor<3x48x60x60xf32>
        // CHECK: return [[VAL6]], [[VAL3]] : tensor<3x48x60x60xf32>, tensor<1x48x60x60xf32>
}
