//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --adjust-groupconv-shape %s | FileCheck %s
// REQUIRES: arch-VPUX30XX || arch-VPUX37XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
// CHECK-LABEL: @adjustGroupConvInput
func.func @adjustGroupConvInput(%arg0: tensor<1x2x64x512xf16, {order = #NHWC}>) -> tensor<1x2x64x512xf16, {order = #NHWC}> {
  %cst = const.Declare tensor<2x1x1x1xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<2x1x1x1xf16>, [#const.Reorder<#NHWC>]
  %bias = const.Declare tensor<1x2x1x1xf16, {order = #NHWC}> = dense<1.0> : tensor<1x2x1x1xf16>, [#const.Reorder<#NHWC>]
  %0 = IE.GroupConvolution(%arg0, %cst, %bias) {dilations = [1, 1], groups = 2 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x2x64x512xf16, {order = #NHWC}>, tensor<2x1x1x1xf16, {order = #NHWC}>, tensor<1x2x1x1xf16, {order = #NHWC}> -> tensor<1x2x64x512xf16, {order = #NHWC}>
  return %0 : tensor<1x2x64x512xf16, {order = #NHWC}>

  // CHECK-DAG:   [[CST_WEIGHTS:%.+]] = const.Declare tensor<16x1x1x1xf16, {order = #NHWC}>
  // CHECK-DAG:   [[CST_BIAS:%.+]] = const.Declare tensor<1x16x1x1xf16, {order = #NHWC}>
  // CHECK:   [[INPUT:%.+]] = IE.ShapeCast {shape = [1, 16, 64, 64]}
  // CHECK-SAME:     inputs(%arg0 : tensor<1x2x64x512xf16, {order = #NHWC}>) -> tensor<1x16x64x64xf16, {order = #NHWC}>
  // CHECK:   [[CONV_RET:%.+]] = IE.GroupConvolution([[INPUT]], [[CST_WEIGHTS]], [[CST_BIAS]]) {dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
  // CHECK:   [[RESULT:%.+]] = IE.ShapeCast {shape = [1, 2, 64, 512]}
  // CHECK-SAME:    inputs([[CONV_RET]] : tensor<1x16x64x64xf16, {order = #NHWC}>) -> tensor<1x2x64x512xf16, {order = #NHWC}>
  // CHECK:   return [[RESULT]]
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
// CHECK-LABEL: @adjustGroupConvInputFailForCSTShapeNotAlign
func.func @adjustGroupConvInputFailForCSTShapeNotAlign(%arg0: tensor<1x2x64x512xf16, {order = #NHWC}>) -> tensor<1x2x64x512xf16, {order = #NHWC}> {
  %cst = const.Declare tensor<2x1x1x1xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<2x1x1x1xf16>, [#const.Reorder<#NHWC>]
  %bias = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<1.0> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
  %0 = IE.GroupConvolution(%arg0, %cst, %bias) {dilations = [1, 1], groups = 2 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x2x64x512xf16, {order = #NHWC}>, tensor<2x1x1x1xf16, {order = #NHWC}>, tensor<1x1x1x1xf16, {order = #NHWC}> -> tensor<1x2x64x512xf16, {order = #NHWC}>
  return %0 : tensor<1x2x64x512xf16, {order = #NHWC}>

  // CHECK-DAG:   [[CST_WEIGHTS:%.+]] = const.Declare tensor<2x1x1x1xf16, {order = #NHWC}>
  // CHECK-DAG:   [[CST_BIAS:%.+]] = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}>
  // CHECK:       [[RESULT:%.+]] = IE.GroupConvolution(%arg0, [[CST_WEIGHTS]], [[CST_BIAS]]) {dilations = [1, 1], groups = 2 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
  // CHECK:       return [[RESULT]]
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
// CHECK-LABEL: @adjustGroupConvInputForDimCFromDimHW
func.func @adjustGroupConvInputForDimCFromDimHW(%arg0: tensor<1x3x64x52xf16, {order = #NHWC}>) -> tensor<1x3x64x52xf16, {order = #NHWC}> {
  %cst = const.Declare tensor<3x1x1x1xf16, {order = #NHWC}> = dense<[[[[1.0]]], [[[2.0]]], [[[3.0]]]]> : tensor<3x1x1x1xf16>, [#const.Reorder<#NHWC>]
  %bias = const.Declare tensor<1x3x1x1xf16, {order = #NHWC}> = dense<[4.0, 5.0, 6.0]> : tensor<3xf16>, [#const.Reshape<[1, 3, 1, 1]>, #const.Reorder<#NHWC>]
  %0 = IE.GroupConvolution(%arg0, %cst, %bias) {dilations = [1, 1], groups = 3 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x3x64x52xf16, {order = #NHWC}>, tensor<3x1x1x1xf16, {order = #NHWC}>, tensor<1x3x1x1xf16, {order = #NHWC}> -> tensor<1x3x64x52xf16, {order = #NHWC}>
  return %0 : tensor<1x3x64x52xf16, {order = #NHWC}>

  // CHECK-DAG:   [[CST_WEIGHTS:%.+]] = const.Declare tensor<48x1x1x1xf16, {order = #NHWC}>
  // CHECK-SAME:        #const.Reorder<#NHWC>, #const.Broadcast<0 : i64, 48 : i64>
  // CHECK-DAG:   [[CST_BIAS:%.+]] = const.Declare tensor<1x48x1x1xf16, {order = #NHWC}>
  // CHECK-SAME:        #const.Reorder<#NHWC>, #const.Broadcast<1 : i64, 48 : i64>
  // CHECK:   [[INPUT:%.+]] = IE.ShapeCast {shape = [1, 48, 16, 13]}
  // CHECK-SAME:    inputs(%arg0 : tensor<1x3x64x52xf16, {order = #NHWC}>) -> tensor<1x48x16x13xf16, {order = #NHWC}>
  // CHECK:   [[CONV_RET:%.+]] = IE.GroupConvolution([[INPUT]], [[CST_WEIGHTS]], [[CST_BIAS]]) {dilations = [1, 1], groups = 48 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
  // CHECK:   [[RESULT:%.+]] = IE.ShapeCast {shape = [1, 3, 64, 52]}
  // CHECK-SAME:    inputs(%1 : tensor<1x48x16x13xf16, {order = #NHWC}>) -> tensor<1x3x64x52xf16, {order = #NHWC}>
  // CHECK:   return [[RESULT]]
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
// CHECK-LABEL: @adjustGroupConvInputForElem
func.func @adjustGroupConvInputForElem(%arg0: tensor<1x3x64x52xf16, {order = #NHWC}>) -> tensor<1x3x64x52xf16, {order = #NHWC}> {
  %cst = const.Declare tensor<3x1x1x1xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<3x1x1x1xf16>, [#const.Reorder<#NHWC>]
  %bias = const.Declare tensor<1x3x1x1xf16, {order = #NHWC}> = dense<1.0> : tensor<3xf16>, [#const.Reshape<[1, 3, 1, 1]>, #const.Reorder<#NHWC>]
  %0 = IE.GroupConvolution(%arg0, %cst, %bias) {dilations = [1, 1], groups = 3 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x3x64x52xf16, {order = #NHWC}>, tensor<3x1x1x1xf16, {order = #NHWC}>, tensor<1x3x1x1xf16, {order = #NHWC}> -> tensor<1x3x64x52xf16, {order = #NHWC}>
  return %0 : tensor<1x3x64x52xf16, {order = #NHWC}>

  // CHECK-DAG:   [[CST_WEIGHTS:%.+]] = const.Declare tensor<16x1x1x1xf16, {order = #NHWC}>
  // CHECK-DAG:   [[CST_BIAS:%.+]] = const.Declare tensor<1x16x1x1xf16, {order = #NHWC}>
  // CHECK:   [[INPUT:%.+]] = IE.ShapeCast {shape = [1, 16, 26, 24]}
  // CHECK-SAME:    inputs(%arg0 : tensor<1x3x64x52xf16, {order = #NHWC}>) -> tensor<1x16x26x24xf16, {order = #NHWC}>
  // CHECK:   [[CONV_RET:%.+]] = IE.GroupConvolution([[INPUT]], [[CST_WEIGHTS]], [[CST_BIAS]]) {dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
  // CHECK:   [[RESULT:%.+]] = IE.ShapeCast {shape = [1, 3, 64, 52]}
  // CHECK-SAME:    inputs(%1 : tensor<1x16x26x24xf16, {order = #NHWC}>) -> tensor<1x3x64x52xf16, {order = #NHWC}>
  // CHECK:   return [[RESULT]]
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
// CHECK-LABEL: @adjustGroupConvInputForElemAndReshapeCst
func.func @adjustGroupConvInputForElemAndReshapeCst(%arg0: tensor<1x17x64x52xf16, {order = #NHWC}>) -> tensor<1x17x64x52xf16, {order = #NHWC}> {
  %cst = const.Declare tensor<17x1x1x1xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<17x1x1x1xf16>, [#const.Reorder<#NHWC>]
  %bias = const.Declare tensor<1x17x1x1xf16, {order = #NHWC}> = dense<1.0> : tensor<17xf16>, [#const.Reshape<[1, 17, 1, 1]>, #const.Reorder<#NHWC>]
  %0 = IE.GroupConvolution(%arg0, %cst, %bias) {dilations = [1, 1], groups = 17 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x17x64x52xf16, {order = #NHWC}>, tensor<17x1x1x1xf16, {order = #NHWC}>, tensor<1x17x1x1xf16, {order = #NHWC}> -> tensor<1x17x64x52xf16, {order = #NHWC}>
  return %0 : tensor<1x17x64x52xf16, {order = #NHWC}>

  // CHECK-DAG:   [[CST_WEIGHTS:%.+]] = const.Declare tensor<16x1x1x1xf16, {order = #NHWC}> = dense<1.250000e-01>
  // CHECK-SAME:    tensor<17x1x1x1xf16>, [#const.Reshape<[1, 1, 1, 1]>, #const.Reorder<#NHWC>, #const.Broadcast<0 : i64, 16 : i64>]
  // CHECK-DAG:   [[CST_BIAS:%.+]] = const.Declare tensor<1x16x1x1xf16, {order = #NHWC}> = dense<1.000000e+00>
  // CHECK-SAME:    tensor<17xf16>, [#const.Reshape<[1, 1, 1, 1]>, #const.Reorder<#NHWC>, #const.Broadcast<1 : i64, 16 : i64>]
  // CHECK:   [[INPUT:%.+]] = IE.ShapeCast {shape = [1, 16, 68, 52]}
  // CHECK-SAME:    inputs(%arg0 : tensor<1x17x64x52xf16, {order = #NHWC}>) -> tensor<1x16x68x52xf16, {order = #NHWC}>
  // CHECK:   [[CONV_RET:%.+]] = IE.GroupConvolution([[INPUT]], [[CST_WEIGHTS]], [[CST_BIAS]]) {dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
  // CHECK:   [[RESULT:%.+]] = IE.ShapeCast {shape = [1, 17, 64, 52]}
  // CHECK-SAME:    inputs(%1 : tensor<1x16x68x52xf16, {order = #NHWC}>) -> tensor<1x17x64x52xf16, {order = #NHWC}>
  // CHECK:   return [[RESULT]]
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @adjustGroupConvInputForElemAndConvertReshapeCst
// CHECK-SAME: [[INPUT:%.+]]: tensor<1x49x120x192xf16, {order = #NHWC}>
func.func @adjustGroupConvInputForElemAndConvertReshapeCst(%arg0: tensor<1x49x120x192xf16, {order = #NHWC}>) -> tensor<1x49x120x192xf16, {order = #NHWC}> {
  %cst = const.Declare tensor<49x1x1x1xf16, {order = #NHWC}> = dense<0.010416667> : tensor<1x1x1x1x1xf32>, [#const.ConvertElemType<f16>, #const.Reshape<[1, 1, 1, 1]>, #const.Broadcast<1 : i64, 49 : i64>, #const.Reshape<[49, 1, 1, 1]>, #const.Reorder<#NHWC>]

  %0 = IE.GroupConvolution(%arg0, %cst) {dilations = [1, 1], groups = 49 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x49x120x192xf16, {order = #NHWC}>, tensor<49x1x1x1xf16, {order = #NHWC}> -> tensor<1x49x120x192xf16, {order = #NHWC}>
  return %0 : tensor<1x49x120x192xf16, {order = #NHWC}>

  // CHECK-DAG:   [[CST_WEIGHTS:%.+]] = const.Declare tensor<16x1x1x1xf16, {order = #NHWC}>
  // CHECK:   [[ACTIVATION:%.+]] = IE.ShapeCast {shape = [1, 16, 280, 252]}
  // CHECK-SAME:    inputs([[INPUT]] : tensor<1x49x120x192xf16, {order = #NHWC}>) -> tensor<1x16x280x252xf16, {order = #NHWC}>
  // CHECK:   [[GROUPCONV_RET:%.+]] = IE.GroupConvolution([[ACTIVATION]], [[CST_WEIGHTS]]) {dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
  // CHECK:   [[RESULT:%.+]] = IE.ShapeCast {shape = [1, 49, 120, 192]}
  // CHECK-SAME:    inputs([[GROUPCONV_RET]] : tensor<1x16x280x252xf16, {order = #NHWC}>) -> tensor<1x49x120x192xf16, {order = #NHWC}>
  // CHECK:   return [[RESULT]]
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
// CHECK-LABEL: @adjustGroupConvInputNotAlignForElemAndReshapeCst
func.func @adjustGroupConvInputNotAlignForElemAndReshapeCst(%arg0 : tensor<1x1x289x289xf16, {order = #NHWC}>) -> (tensor<1x1x289x289xf16, {order = #NHWC}>) {
    %filter = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
    %group_conv = IE.GroupConvolution(%arg0, %filter) {
        dilations = [1, 1],
        groups = 1 : i64,
        pads_begin = [0, 0],
        pads_end = [0, 0],
        strides = [1, 1]
        } : tensor<1x1x289x289xf16, {order = #NHWC}>, tensor<1x1x1x1xf16, {order = #NHWC}> -> tensor<1x1x289x289xf16, {order = #NHWC}>

    return %group_conv : tensor<1x1x289x289xf16, {order = #NHWC}>
    // CHECK:       const.Declare
    // CHECK-SAME{{LITERAL}}:  tensor<289x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x1x1x1xf16>, [#const.Reshape<[1, 1, 1, 1]>, #const.Reorder<#NHWC>, #const.Broadcast<0 : i64, 289 : i64>]
    // CHECK:       IE.ShapeCast
    // CHECK-SAME{{LITERAL}}:  {shape = [1, 289, 17, 17]} inputs(%arg0 : tensor<1x1x289x289xf16, {order = #NHWC}>) -> tensor<1x289x17x17xf16, {order = #NHWC}>
    // CHECK:       IE.GroupConvolution
    // CHECK-SAME{{LITERAL}}:  {dilations = [1, 1], groups = 289 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
    // CHECK-SAME   tensor<1x289x17x17xf16, {order = #NHWC}>, tensor<289x1x1x1xf16, {order = #NHWC}> -> tensor<1x289x17x17xf16, {order = #NHWC}>
    // CHECK:       IE.ShapeCast
    // CHECK-SAME{{LITERAL}}:  {shape = [1, 1, 289, 289]} inputs(%1 : tensor<1x289x17x17xf16, {order = #NHWC}>) -> tensor<1x1x289x289xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @adjustGroupConvInputWithPermuteQuantizeFront
func.func @adjustGroupConvInputWithPermuteQuantizeFront(%arg0 : tensor<1x9x16x1xf16>, %arg1 : tensor<1x9x16x1xf16, {order = #NHWC}>) -> (tensor<1x9x16x1xf16>) {
    %cst = const.Declare tensor<9x1x1x1xf16, {order = #NHWC}> = dense<0.0625> : tensor<1x1x1x1x1xf32>, [#const.ConvertElemType<f16>, #const.Reshape<[1, 1, 1, 1]>, #const.Broadcast<1 : i64, 9 : i64>, #const.Reshape<[9, 1, 1, 1]>, #const.Reorder<#NHWC>]
    %0 = IE.PermuteQuantize(%arg0) {dstElemType = f16, dst_order = #NHWC, mem_perm = #NHWC, pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0]} : tensor<1x9x16x1xf16> -> tensor<1x9x16x1xf16, {order = #NHWC}>
    %1 = IE.GroupConvolution(%0, %cst) {dilations = [1, 1], groups = 9 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x9x16x1xf16, {order = #NHWC}>, tensor<9x1x1x1xf16, {order = #NHWC}> -> tensor<1x9x16x1xf16, {order = #NHWC}>
    %2 = IE.Add(%1, %arg1) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x9x16x1xf16, {order = #NHWC}>, tensor<1x9x16x1xf16, {order = #NHWC}> -> tensor<1x9x16x1xf16, {order = #NHWC}>
    %3 = IE.Reorder(%2) {dstOrder = #NCHW} : tensor<1x9x16x1xf16, {order = #NHWC}> -> tensor<1x9x16x1xf16>

    return %3 : tensor<1x9x16x1xf16>
    // CHECK:       const.Declare
    // CHECK-SAME{{LITERAL}}:  tensor<16x1x1x1xf16, {order = #NHWC}> = dense<0.0625> : tensor<1x1x1x1x1xf32>, [#const.Reshape<[1, 1, 1, 1]>, #const.ConvertElemType<f16>, #const.Reorder<#NHWC>, #const.Broadcast<0 : i64, 16 : i64>]
    // CHECK:       IE.PermuteQuantize
    // CHECK-SAME{{LITERAL}}:  {dstElemType = f16, dst_order = #NHWC, mem_perm = #NHWC, pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0]}
    // CHECK-SAME   tensor<1x9x16x1xf16> -> tensor<1x9x16x1xf16, {order = #NHWC}>
    // CHECK:       IE.ShapeCast
    // CHECK-SAME{{LITERAL}}:  {shape = [1, 16, 3, 3]} inputs(%0 : tensor<1x9x16x1xf16, {order = #NHWC}>) -> tensor<1x16x3x3xf16, {order = #NHWC}>
    // CHECK:       IE.GroupConvolution
    // CHECK-SAME{{LITERAL}}:  {dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
    // CHECK-SAME   tensor<1x16x3x3xf16, {order = #NHWC}>, tensor<16x1x1x1xf16, {order = #NHWC}> -> tensor<1x16x3x3xf16, {order = #NHWC}>
    // CHECK:       IE.ShapeCast
    // CHECK-SAME{{LITERAL}}:  {shape = [1, 9, 16, 1]} inputs(%2 : tensor<1x16x3x3xf16, {order = #NHWC}>) -> tensor<1x9x16x1xf16, {order = #NHWC}>
    // CHECK:       IE.Add
    // CHECK-SAME{{LITERAL}}:  {auto_broadcast = #IE.auto_broadcast_type<NUMPY>}
    // CHECK-SAME   tensor<1x9x16x1xf16, {order = #NHWC}>, tensor<1x9x16x1xf16, {order = #NHWC}> -> tensor<1x9x16x1xf16, {order = #NHWC}>
    // CHECK:       IE.Reorder
    // CHECK-SAME{{LITERAL}}:  {dstOrder = #NCHW} : tensor<1x9x16x1xf16, {order = #NHWC}> -> tensor<1x9x16x1xf16>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK: func.func @adjustGroupConvWithPostOp([[INPUT_DATA:%.+]]: tensor<1x8x240x320xf16, {order = #NHWC}>)
func.func @adjustGroupConvWithPostOp(%arg0: tensor<1x8x240x320xf16, {order = #NHWC}>) -> tensor<1x8x240x320xf16, {order = #NHWC}> {
    %FILTER = const.Declare tensor<8x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x1x1x1xf16>, [#const.Broadcast<0 : i64, 8 : i64>, #const.Reorder<#NHWC>]
    %BIAS = const.Declare tensor<1x8x1x1xf16> = dense<
                [[[[0.788085938]], [[1.11230469]], [[2.08007813]], [[0.470214844]], [[0.528808594]], [[0.282714844]], [[0.441162109]], [[0.197021484]]]]>
            : tensor<1x8x1x1xf32>, [#const.ConvertElemType<f16>]
    %GROUP_CONV = IE.GroupConvolution(%arg0, %FILTER, %BIAS) {
                      dilations = [1, 1],
                      groups = 8 : i64,
                      pads_begin = [0, 0],
                      pads_end = [0, 0],
                      post_op = #IE.PostOp<name = "IE.ReLU", attrs = {}>, strides = [1, 1]}
                    : tensor<1x8x240x320xf16, {order = #NHWC}>, tensor<8x1x1x1xf16, {order = #NHWC}>, tensor<1x8x1x1xf16> -> tensor<1x8x240x320xf16, {order = #NHWC}>
    return %GROUP_CONV : tensor<1x8x240x320xf16, {order = #NHWC}>

  // CHECK-DAG:   [[CST_FILTER:%.+]] = const.Declare tensor<16x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x1x1x1xf16>, [#const.Reshape<[1, 1, 1, 1]>, #const.Reorder<#NHWC>, #const.Broadcast<0 : i64, 16 : i64>]
  // CHECK-DAG:   [[CST_BIAS:%.+]] = const.Declare tensor<1x16x1x1xf16> = dense<
  // CHECK-SAME(LITERAL):        [[[[0.788085938]], [[1.11230469]], [[2.08007813]], [[0.470214844]], [[0.528808594]], [[0.282714844]], [[0.441162109]], [[0.197021484]]]]>
  // CHECK-SAME:                 : tensor<1x8x1x1xf32>, [#const.ConvertElemType<f16>, #const.Broadcast<1 : i64, 16 : i64>, #const.Reshape<[1, 16, 1, 1]>]
  // CHECK:       [[INPUT:%.+]] = IE.ShapeCast {shape = [1, 16, 200, 192]}
  // CHECK-SAME:        inputs([[INPUT_DATA]] : tensor<1x8x240x320xf16, {order = #NHWC}>) -> tensor<1x16x200x192xf16, {order = #NHWC}>
  // CHECK:       [[GROUP_CONV:%.+]] = IE.GroupConvolution([[INPUT]], [[CST_FILTER]], [[CST_BIAS]]) {
  // CHECK-SAME:        dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0],
  // CHECK-SAME:        post_op = #IE.PostOp<name = "IE.ReLU", attrs = {}>, strides = [1, 1]}
  // CHECK:       [[RESULT:%.+]] = IE.ShapeCast {shape = [1, 8, 240, 320]}
  // CHECK-SAME:        inputs([[GROUP_CONV]] : tensor<1x16x200x192xf16, {order = #NHWC}>) -> tensor<1x8x240x320xf16, {order = #NHWC}>
  // CHECK:       return [[RESULT]]
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NHCW = affine_map<(d0, d1, d2, d3) -> (d0, d2, d1, d3)>

// CHECK: func.func @sliceGroupConvWithReorderOp([[INPUT_DATA:%.+]]: tensor<1x3x144x478xf16, {order = #NHCW}>)
func.func @sliceGroupConvWithReorderOp(%arg0: tensor<1x3x144x478xf16, {order = #NHCW}>) -> tensor<1x3x144x478xf16> {
    %FILTER = const.Declare tensor<3x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x3x1x1x1xf16>, [#const.Reshape<[1, 3, 1, 1]>, #const.Reshape<[3, 1, 1, 1]>, #const.Reorder<#NHWC>]
    %BIAS = const.Declare tensor<1x3x1x1xf16> = dense<[[[[0.788085938]], [[1.11230469]], [[2.08007813]]]]> : tensor<1x3x1x1xf32>, [#const.ConvertElemType<f16>]
    %0 = IE.Reorder(%arg0) {dstOrder = #NHWC} : tensor<1x3x144x478xf16, {order = #NHCW}> -> tensor<1x3x144x478xf16, {order = #NHWC}>
    %1 = IE.GroupConvolution(%0, %FILTER, %BIAS) {
                      dilations = [1, 1],
                      groups = 3 : i64,
                      pads_begin = [0, 0],
                      pads_end = [0, 0],
                      strides = [1, 1]}
                    : tensor<1x3x144x478xf16, {order = #NHWC}>, tensor<3x1x1x1xf16, {order = #NHWC}>, tensor<1x3x1x1xf16> -> tensor<1x3x144x478xf16, {order = #NHWC}>
    %2 = IE.Reorder(%1) {dstOrder = #NCHW} :  tensor<1x3x144x478xf16, {order = #NHWC}> -> tensor<1x3x144x478xf16>
    return %2 : tensor<1x3x144x478xf16>

    // CHECK-DAG:    [[CST:%.+]] = const.Declare
    // CHECK-SAME(LITERAL):    tensor<16x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x3x1x1x1xf16>, [#const.Reshape<[1, 1, 1, 1]>, #const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [1, 1, 1, 1]>, #const.Broadcast<0 : i64, 16 : i64>]
    // CHECK-DAG:    [[CST_0:%.+]] = const.Declare
    // CHECK-SAME(LITERAL):    tensor<1x16x1x1xf16> = dense<[[[[0.788085938]], [[1.11230469]], [[2.08007813]]]]> : tensor<1x3x1x1xf32>, [#const.ConvertElemType<f16>, #const.SubView<[0, 0, 0, 0], [1, 1, 1, 1]>, #const.Broadcast<1 : i64, 16 : i64>, #const.Reshape<[1, 16, 1, 1]>]
    // CHECK-DAG:    [[CST_1:%.+]] = const.Declare
    // CHECK-SAME(LITERAL):    tensor<16x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x3x1x1x1xf16>, [#const.Reshape<[1, 1, 1, 1]>, #const.Reorder<#NHWC>, #const.SubView<[1, 0, 0, 0], [1, 1, 1, 1]>, #const.Broadcast<0 : i64, 16 : i64>]
    // CHECK-DAG:    [[CST_2:%.+]] = const.Declare
    // CHECK-SAME(LITERAL):    tensor<1x16x1x1xf16> = dense<[[[[0.788085938]], [[1.11230469]], [[2.08007813]]]]> : tensor<1x3x1x1xf32>, [#const.ConvertElemType<f16>, #const.SubView<[0, 1, 0, 0], [1, 1, 1, 1]>, #const.Broadcast<1 : i64, 16 : i64>, #const.Reshape<[1, 16, 1, 1]>]
    // CHECK-DAG:    [[CST_3:%.+]] = const.Declare
    // CHECK-SAME(LITERAL):    tensor<16x1x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x3x1x1x1xf16>, [#const.Reshape<[1, 1, 1, 1]>, #const.Reorder<#NHWC>, #const.SubView<[2, 0, 0, 0], [1, 1, 1, 1]>, #const.Broadcast<0 : i64, 16 : i64>]
    // CHECK-DAG:    [[CST_4:%.+]] = const.Declare
    // CHECK-SAME(LITERAL):    tensor<1x16x1x1xf16> = dense<[[[[0.788085938]], [[1.11230469]], [[2.08007813]]]]> : tensor<1x3x1x1xf32>, [#const.ConvertElemType<f16>, #const.SubView<[0, 2, 0, 0], [1, 1, 1, 1]>, #const.Broadcast<1 : i64, 16 : i64>, #const.Reshape<[1, 16, 1, 1]>]
    // CHECK:        [[SLICE_0:%.+]] = IE.Slice [[INPUT_DATA]]
    // CHECK-SAME:       [0, 0, 0, 0] [1, 1, 144, 478] : tensor<1x3x144x478xf16, {order = #NHCW}> to tensor<1x1x144x478xf16, {order = #NHCW}>
    // CHECK:        [[PERMUTE_CAST_0:%.+]] = IE.PermuteCast([[SLICE_0]])
    // CHECK-SAME:       {dst_order = #NHWC, mem_perm = #NCWH} : tensor<1x1x144x478xf16, {order = #NHCW}> -> tensor<1x1x144x478xf16, {order = #NHWC}>
    // CHECK:        [[SHAPE_CAST_0:%.+]] = IE.ShapeCast {shape = [1, 16, 239, 18]}
    // CHECK-SAME:       inputs([[PERMUTE_CAST_0]] : tensor<1x1x144x478xf16, {order = #NHWC}>) -> tensor<1x16x239x18xf16, {order = #NHWC}>
    // CHECK:        [[GROUP_CONV_0:%.+]] = IE.GroupConvolution([[SHAPE_CAST_0]], [[CST]], [[CST_0]]) {
    // CHECK-SAME:       dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
    // CHECK-SAME:       tensor<1x16x239x18xf16, {order = #NHWC}>, tensor<16x1x1x1xf16, {order = #NHWC}>, tensor<1x16x1x1xf16> -> tensor<1x16x239x18xf16, {order = #NHWC}>
    // CHECK:        [[SHAPE_CAST_3:%.+]] = IE.ShapeCast
    // CHECK-SAME:       {shape = [1, 1, 144, 478]} inputs([[GROUP_CONV_0]] : tensor<1x16x239x18xf16, {order = #NHWC}>) -> tensor<1x1x144x478xf16, {order = #NHWC}>
    // CHECK:        [[SLICE_1:%.+]] = IE.Slice [[INPUT_DATA]]
    // CHECK-SAME:       [0, 1, 0, 0] [1, 1, 144, 478] : tensor<1x3x144x478xf16, {order = #NHCW}> to tensor<1x1x144x478xf16, {order = #NHCW}>
    // CHECK:        [[PERMUTE_CAST_1:%.+]] = IE.PermuteCast([[SLICE_1]])
    // CHECK-SAME:       {dst_order = #NHWC, mem_perm = #NCWH} : tensor<1x1x144x478xf16, {order = #NHCW}> -> tensor<1x1x144x478xf16, {order = #NHWC}>
    // CHECK:        [[SHAPE_CAST_1:%.+]] = IE.ShapeCast
    // CHECK-SAME:       {shape = [1, 16, 239, 18]} inputs([[PERMUTE_CAST_1]] : tensor<1x1x144x478xf16, {order = #NHWC}>) -> tensor<1x16x239x18xf16, {order = #NHWC}>
    // CHECK:        [[GROUP_CONV_1:%.+]] = IE.GroupConvolution([[SHAPE_CAST_1]], [[CST_1]], [[CST_2]]) {
    // CHECK-SAME:       dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
    // CHECK-SAME:       tensor<1x16x239x18xf16, {order = #NHWC}>, tensor<16x1x1x1xf16, {order = #NHWC}>, tensor<1x16x1x1xf16> -> tensor<1x16x239x18xf16, {order = #NHWC}>
    // CHECK:        [[SHAPE_CAST_4:%.+]] = IE.ShapeCast
    // CHECK-SAME:       {shape = [1, 1, 144, 478]} inputs([[GROUP_CONV_1]] : tensor<1x16x239x18xf16, {order = #NHWC}>) -> tensor<1x1x144x478xf16, {order = #NHWC}>
    // CHECK:        [[SLICE_2:%.+]] = IE.Slice [[INPUT_DATA]]
    // CHECK-SAME:       [0, 2, 0, 0] [1, 1, 144, 478] : tensor<1x3x144x478xf16, {order = #NHCW}> to tensor<1x1x144x478xf16, {order = #NHCW}>
    // CHECK:        [[PERMUTE_CAST_2:%.+]] = IE.PermuteCast([[SLICE_2]])
    // CHECK-SAME:       {dst_order = #NHWC, mem_perm = #NCWH} : tensor<1x1x144x478xf16, {order = #NHCW}> -> tensor<1x1x144x478xf16, {order = #NHWC}>
    // CHECK:        [[SHAPE_CAST_2:%.+]] = IE.ShapeCast
    // CHECK-SAME:       {shape = [1, 16, 239, 18]} inputs([[PERMUTE_CAST_2]] : tensor<1x1x144x478xf16, {order = #NHWC}>) -> tensor<1x16x239x18xf16, {order = #NHWC}>
    // CHECK:        [[GROUP_CONV_2:%.+]] = IE.GroupConvolution([[SHAPE_CAST_2]], [[CST_3]], [[CST_4]]) {
    // CHECK-SAME:       dilations = [1, 1], groups = 16 : i64, pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]}
    // CHECK-SAME:       tensor<1x16x239x18xf16, {order = #NHWC}>, tensor<16x1x1x1xf16, {order = #NHWC}>, tensor<1x16x1x1xf16> -> tensor<1x16x239x18xf16, {order = #NHWC}>
    // CHECK:        [[SHAPE_CAST_5:%.+]] = IE.ShapeCast
    // CHECK-SAME:       {shape = [1, 1, 144, 478]} inputs([[GROUP_CONV_2]] : tensor<1x16x239x18xf16, {order = #NHWC}>) -> tensor<1x1x144x478xf16, {order = #NHWC}>
    // CHECK:        [[CONCAT:%.+]] = IE.Concat([[SHAPE_CAST_3]], [[SHAPE_CAST_4]], [[SHAPE_CAST_5]])
    // CHECK-SAME:       {per_axis = #IE.Concat<axis = 1 : i64>} : tensor<1x1x144x478xf16, {order = #NHWC}>, tensor<1x1x144x478xf16, {order = #NHWC}>, tensor<1x1x144x478xf16, {order = #NHWC}> -> tensor<1x3x144x478xf16, {order = #NHWC}>
    // CHECK:        [[RESULT:%.+]] = IE.Reorder([[CONCAT]]) {dstOrder = #NCHW} : tensor<1x3x144x478xf16, {order = #NHWC}> -> tensor<1x3x144x478xf16>

    // CHECK:        return [[RESULT]] : tensor<1x3x144x478xf16>
}
