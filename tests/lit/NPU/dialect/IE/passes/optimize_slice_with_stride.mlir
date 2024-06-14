//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --optimize-slice-with-stride %s | FileCheck %s
// REQUIRES: arch-VPUX30XX || arch-VPUX37XX || arch-VPUX40XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @ConvertSliceToConvFromConvert
func.func @ConvertSliceToConvFromConvert(%arg0: tensor<1x3x1088x1920xf32, {order = #NHWC}>)
    -> tensor<1x1x1088x1920xf16, {order = #NHWC}> {
    %CONVERT = IE.Convert(%arg0) {dstElemType = f16} : tensor<1x3x1088x1920xf32, {order = #NHWC}> -> tensor<1x3x1088x1920xf16, {order = #NHWC}>
    %SLICE = IE.Slice %CONVERT [0, 1, 0, 0] [1, 1, 1088, 1920] : tensor<1x3x1088x1920xf16, {order = #NHWC}> to tensor<1x1x1088x1920xf16, {order = #NHWC}>

    return %SLICE : tensor<1x1x1088x1920xf16, {order = #NHWC}>

    // CHECK:   [[WEIGHTS:%.*]] = const.Declare tensor<16x48x1x1xf16, {order = #NHWC}> = dense<"0x
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C{{([0]{181})}}
    // CHECK-SAME:      0000003C0000"> : tensor<16x48x1x1xf16>, [#const.Reorder<#NHWC>]
    // CHECK:   [[CONVERT_INPUT:%.*]] = IE.Convert(%arg0) {dstElemType = f16} : tensor<1x3x1088x1920xf32, {order = #NHWC}> -> tensor<1x3x1088x1920xf16, {order = #NHWC}>
    // CHECK:   [[RESHAPE_INPUT:%.*]] = IE.ShapeCast {shape = [1, 48, 1088, 120]} inputs([[CONVERT_INPUT]] : tensor<1x3x1088x1920xf16, {order = #NHWC}>) -> tensor<1x48x1088x120xf16, {order = #NHWC}>
    // CHECK:   [[CONV:%.*]] = IE.Convolution([[RESHAPE_INPUT]], [[WEIGHTS]]) {
    // CHECK-SAME:      dilations = [1, 1],
    // CHECK-SAME:      pads_begin = [0, 0],
    // CHECK-SAME:      pads_end = [0, 0],
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:  } : tensor<1x48x1088x120xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<16x48x1x1xf16, {order = #NHWC}>
    // CHECK-SAME:           -> tensor<1x16x1088x120xf16, {order = #NHWC}>
    // CHECK:   [[RESHAPE_OUTPUT:%.*]] = IE.ShapeCast {shape = [1, 1, 1088, 1920]} inputs([[CONV]] : tensor<1x16x1088x120xf16, {order = #NHWC}>) -> tensor<1x1x1088x1920xf16, {order = #NHWC}>

    // CHECK:   return [[RESHAPE_OUTPUT]] : tensor<1x1x1088x1920xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

// CHECK-LABEL: @ConvertSliceToConvFromPermuteCast
func.func @ConvertSliceToConvFromPermuteCast(%arg0: tensor<1x1088x1920x3xf16>)
    -> tensor<1x1x1088x1920xf16, {order = #NHWC}> {
    %PERMUTECAST = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x1088x1920x3xf16> -> tensor<1x3x1088x1920xf16, {order = #NHWC}>
    %SLICE = IE.Slice %PERMUTECAST [0, 3, 0, 0] [1, 1, 1088, 1920] : tensor<1x3x1088x1920xf16, {order = #NHWC}> to tensor<1x1x1088x1920xf16, {order = #NHWC}>

    return %SLICE : tensor<1x1x1088x1920xf16, {order = #NHWC}>

    // CHECK:   [[WEIGHTS:%.*]] = const.Declare tensor<16x48x1x1xf16, {order = #NHWC}> = dense<"0x
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK-SAME:      0000003C{{([0]{196})}}
    // CHECK:   [[PERMUTECAST_INPUT:%.*]]  = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x1088x1920x3xf16> -> tensor<1x3x1088x1920xf16, {order = #NHWC}>
    // CHECK:   [[RESHAPE_INPUT:%.*]] = IE.ShapeCast {shape = [1, 48, 1088, 120]} inputs([[PERMUTECAST_INPUT]] : tensor<1x3x1088x1920xf16, {order = #NHWC}>) -> tensor<1x48x1088x120xf16, {order = #NHWC}>
    // CHECK:   [[CONV:%.*]] = IE.Convolution([[RESHAPE_INPUT]], [[WEIGHTS]]) {
    // CHECK-SAME:      dilations = [1, 1],
    // CHECK-SAME:      pads_begin = [0, 0],
    // CHECK-SAME:      pads_end = [0, 0],
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:  } : tensor<1x48x1088x120xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<16x48x1x1xf16, {order = #NHWC}>
    // CHECK-SAME:           -> tensor<1x16x1088x120xf16, {order = #NHWC}>
    // CHECK:   [[RESHAPE_OUTPUT:%.*]] = IE.ShapeCast {shape = [1, 1, 1088, 1920]} inputs(%2 : tensor<1x16x1088x120xf16, {order = #NHWC}>) -> tensor<1x1x1088x1920xf16, {order = #NHWC}>
    // CHECK:   return [[RESHAPE_OUTPUT]] : tensor<1x1x1088x1920xf16, {order = #NHWC}>
}

// -----

// CHECK-LABEL: @SkipSliceNCHW
func.func @SkipSliceNCHW(%arg0: tensor<1x3x1088x1920xf16>) -> tensor<1x1x1088x1920xf16> {
    %SLICE = IE.Slice %arg0 [0, 3, 0, 0] [1, 1, 1088, 1920] : tensor<1x3x1088x1920xf16> to tensor<1x1x1088x1920xf16>
    return %SLICE : tensor<1x1x1088x1920xf16>

    // CHECK:   [[SLICE:%.*]] = IE.Slice %arg0 [0, 3, 0, 0] [1, 1, 1088, 1920] : tensor<1x3x1088x1920xf16> to tensor<1x1x1088x1920xf16>
    // CHECK:   return [[SLICE]] : tensor<1x1x1088x1920xf16>

}

// -----

// CHECK-LABEL: @SkipSliceOnHeight
func.func @SkipSliceOnHeight(%arg0: tensor<1x3x1088x1920xf16>) -> tensor<1x3x100x1920xf16> {
    %SLICE = IE.Slice %arg0 [0, 0, 3, 0] [1, 3, 100, 1920] : tensor<1x3x1088x1920xf16> to tensor<1x3x100x1920xf16>
    return %SLICE : tensor<1x3x100x1920xf16>

    // CHECK:   [[SLICE:%.*]] = IE.Slice %arg0 [0, 0, 3, 0] [1, 3, 100, 1920] : tensor<1x3x1088x1920xf16> to tensor<1x3x100x1920xf16>
    // CHECK:   return [[SLICE]] : tensor<1x3x100x1920xf16>

}

// -----

// CHECK-LABEL: @SkipSliceOnWidth
func.func @SkipSliceOnWidth(%arg0: tensor<1x3x1088x1920xf16>) -> tensor<1x3x1088x100xf16> {
    %SLICE = IE.Slice %arg0 [0, 0, 0, 3] [1, 3, 1088, 100] : tensor<1x3x1088x1920xf16> to tensor<1x3x1088x100xf16>
    return %SLICE : tensor<1x3x1088x100xf16>

    // CHECK:   [[SLICE:%.*]] = IE.Slice %arg0 [0, 0, 0, 3] [1, 3, 1088, 100] : tensor<1x3x1088x1920xf16> to tensor<1x3x1088x100xf16>
    // CHECK:   return [[SLICE]] : tensor<1x3x1088x100xf16>

}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

!qElemType = !quant.uniform<u8:f16, 2.000000e+00>

// CHECK-LABEL: @SkipConvertSliceToConvFromPermuteCastWithQuantizedType
func.func @SkipConvertSliceToConvFromPermuteCastWithQuantizedType(%arg0: tensor<1x1088x1920x3x!qElemType>)
    -> tensor<1x1x1088x1920x!qElemType, {order = #NHWC}> {
    %PERMUTECAST = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x1088x1920x3x!qElemType> -> tensor<1x3x1088x1920x!qElemType, {order = #NHWC}>
    %SLICE = IE.Slice %PERMUTECAST [0, 3, 0, 0] [1, 1, 1088, 1920] : tensor<1x3x1088x1920x!qElemType, {order = #NHWC}> to tensor<1x1x1088x1920x!qElemType, {order = #NHWC}>

    return %SLICE : tensor<1x1x1088x1920x!qElemType, {order = #NHWC}>

    // CHECK:   [[PERMUTECAST:%.*]] = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x1088x1920x3x!qElemType> -> tensor<1x3x1088x1920x!qElemType, {order = #NHWC}>
    // CHECK:   [[SLICE:%.*]] = IE.Slice [[PERMUTECAST]] [0, 3, 0, 0] [1, 1, 1088, 1920] : tensor<1x3x1088x1920x!qElemType, {order = #NHWC}> to tensor<1x1x1088x1920x!qElemType, {order = #NHWC}>
    // CHECK:   return [[SLICE]] : tensor<1x1x1088x1920x!qElemType, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

// CHECK-LABEL: @NotConvertSliceIfChannelExpandBig
func.func @NotConvertSliceIfChannelExpandBig(%arg0: tensor<1x1088x1920x16xf16>)
    -> tensor<1x9x1088x1920xf16, {order = #NHWC}> {
    %PERMUTECAST = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x1088x1920x16xf16> -> tensor<1x16x1088x1920xf16, {order = #NHWC}>
    %SLICE = IE.Slice %PERMUTECAST [0, 3, 0, 0] [1, 9, 1088, 1920] : tensor<1x16x1088x1920xf16, {order = #NHWC}> to tensor<1x9x1088x1920xf16, {order = #NHWC}>

    return %SLICE : tensor<1x9x1088x1920xf16, {order = #NHWC}>

    // CHECK:   [[PERMUTECAST_INPUT:%.*]] = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x1088x1920x16xf16> -> tensor<1x16x1088x1920xf16, {order = #NHWC}>
    // CHECK:   [[SLICE:%.*]] = IE.Slice [[PERMUTECAST_INPUT]] [0, 3, 0, 0] [1, 9, 1088, 1920] : tensor<1x16x1088x1920xf16, {order = #NHWC}> to tensor<1x9x1088x1920xf16, {order = #NHWC}>

    // CHECK:   return [[SLICE]] : tensor<1x9x1088x1920xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotConvertIfSliceNotFromDDR
func.func @NotConvertIfSliceNotFromDDR(%arg0: tensor<1x4x1088x1920xf16, {order = #NHWC}>, %arg1: tensor<1x4x1088x1920xf16, {order = #NHWC}>)
        -> tensor<1x3x1088x1920xf16, {order = #NHWC}> {
    %0 = IE.Slice %arg0 [0, 1, 0, 0] [1, 3, 1088, 1920] : tensor<1x4x1088x1920xf16, {order = #NHWC}> to tensor<1x3x1088x1920xf16, {order = #NHWC}>

    return %0 : tensor<1x3x1088x1920xf16, {order = #NHWC}>

    // CHECK:   [[SLICE:%.*]] = IE.Slice %arg0 [0, 1, 0, 0] [1, 3, 1088, 1920] : tensor<1x4x1088x1920xf16, {order = #NHWC}> to tensor<1x3x1088x1920xf16, {order = #NHWC}>
    // CHECK:   return [[SLICE]] : tensor<1x3x1088x1920xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

// CHECK-LABEL: @NotConvertIfFitCmx
func.func @NotConvertIfFitCmx(%arg0: tensor<1x16x16x3xf16>)
    -> tensor<1x1x16x16xf16, {order = #NHWC}> {
    %PERMUTECAST = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x16x16x3xf16> -> tensor<1x3x16x16xf16, {order = #NHWC}>
    %SLICE = IE.Slice %PERMUTECAST [0, 3, 0, 0] [1, 1, 16, 16] : tensor<1x3x16x16xf16, {order = #NHWC}> to tensor<1x1x16x16xf16, {order = #NHWC}>

    return %SLICE : tensor<1x1x16x16xf16, {order = #NHWC}>

    // CHECK:   [[PERMUTECAST:%.*]] = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x16x16x3xf16> -> tensor<1x3x16x16xf16, {order = #NHWC}>
    // CHECK:   [[SLICE:%.*]] = IE.Slice [[PERMUTECAST]] [0, 3, 0, 0] [1, 1, 16, 16] : tensor<1x3x16x16xf16, {order = #NHWC}> to tensor<1x1x16x16xf16, {order = #NHWC}>

    // CHECK:   return [[SLICE]] : tensor<1x1x16x16xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @OptimizeSliceConcat
func.func @OptimizeSliceConcat(%arg0: tensor<1x1024x32x32xf16, {order = #NHWC}>) -> tensor<1x512x32x32xf16, {order = #NHWC}> {
    %WEIGHTS = const.Declare tensor<512x1024x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<512x1024x3x3xf16>, [#const.Reorder<#NHWC>]
    %CST_0 = const.Declare tensor<1x1x32x32xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<1x1x32x32xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>]
    %WEIGHTS2 = const.Declare tensor<512x512x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<512x512x3x3xf16>, [#const.Reorder<#NHWC>]
    %CONV = IE.Convolution(%arg0, %WEIGHTS) {
        dilations = [1, 1],
        pads_begin = [1, 1], pads_end = [1, 1],
        strides = [1, 1]
    } : tensor<1x1024x32x32xf16, {order = #NHWC}>, tensor<512x1024x3x3xf16, {order = #NHWC}> 
        -> tensor<1x512x32x32xf16, {order = #NHWC}>
    %SLICE = IE.Slice %CONV [0, 0, 0, 0] [1, 511, 32, 32] : tensor<1x512x32x32xf16, {order = #NHWC}> to tensor<1x511x32x32xf16, {order = #NHWC}>
    %CONCAT = IE.Concat(%SLICE, %CST_0) {static_offsets = [[0, 0, 0, 0], [0, 511, 0, 0]]} : tensor<1x511x32x32xf16, {order = #NHWC}>, tensor<1x1x32x32xf16, {order = #NHWC}>
        -> tensor<1x512x32x32xf16, {order = #NHWC}>
    %CONV_OUT = IE.Convolution(%CONCAT, %WEIGHTS2) {
        dilations = [1, 1],
        pads_begin = [1, 1], pads_end = [1, 1],
        strides = [1, 1]} : tensor<1x512x32x32xf16, {order = #NHWC}>, tensor<512x512x3x3xf16, {order = #NHWC}>
        -> tensor<1x512x32x32xf16, {order = #NHWC}>

    return %CONV_OUT : tensor<1x512x32x32xf16, {order = #NHWC}>

    // CHECK-DAG:   [[WEIGHTS:%.*]] = const.Declare tensor<512x1024x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> :
    // CHECK-SAME:          tensor<512x1024x3x3xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [511, 1024, 3, 3]>, #const.PadWithZero<[0, 0, 0, 0], [1, 0, 0, 0]>]
    // CHECK-DAG:   [[CST_0:%.*]] = const.Declare tensor<1x512x32x32xf16, {order = #NHWC}> = dense<1.250000e-01> :
    // CHECK-SAME:          tensor<1x1x32x32xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>, #const.PadWithZero<[0, 511, 0, 0], [0, 0, 0, 0]>]
    // CHECK-DAG:   [[WEIGHTS2:%.*]] = const.Declare tensor<512x512x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<512x512x3x3xf16>, [#const.Reorder<#NHWC>]
    // CHECK:   [[CONV_IN:%.*]] = IE.Convolution(%arg0, [[WEIGHTS]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [1, 1], strides = [1, 1]} :
    // CHECK-SAME:      tensor<1x1024x32x32xf16, {order = #NHWC}>, tensor<512x1024x3x3xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>
    // CHECK:   [[ADD:%.*]] = IE.Add([[CONV_IN]], [[CST_0]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} :
    // CHECK-SAME:      tensor<1x512x32x32xf16, {order = #NHWC}>, tensor<1x512x32x32xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>
    // CHECK:   [[CONV_OUT:%.*]] = IE.Convolution([[ADD]], [[WEIGHTS2]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [1, 1], strides = [1, 1]} :
    // CHECK-SAME:      tensor<1x512x32x32xf16, {order = #NHWC}>, tensor<512x512x3x3xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>

    // CHECK:   return [[CONV_OUT]] : tensor<1x512x32x32xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotOptimizeSliceConcatIfNotLowestDim
func.func @NotOptimizeSliceConcatIfNotLowestDim(%arg0: tensor<1x1024x32x32xf16, {order = #NHWC}>) -> tensor<1x512x32x32xf16, {order = #NHWC}> {
    %WEIGHTS = const.Declare tensor<512x1024x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<512x1024x3x3xf16>, [#const.Reorder<#NHWC>]
    %CST_0 = const.Declare tensor<1x512x32x2xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<1x512x32x2xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>]
    %WEIGHTS2 = const.Declare tensor<512x512x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<512x512x3x3xf16>, [#const.Reorder<#NHWC>]
    %CONV = IE.Convolution(%arg0, %WEIGHTS) {
        dilations = [1, 1],
        pads_begin = [1, 1], pads_end = [1, 1],
        strides = [1, 1]
    } : tensor<1x1024x32x32xf16, {order = #NHWC}>, tensor<512x1024x3x3xf16, {order = #NHWC}> 
        -> tensor<1x512x32x32xf16, {order = #NHWC}>
    %SLICE = IE.Slice %CONV [0, 0, 0, 0] [1, 512, 32, 30] : tensor<1x512x32x32xf16, {order = #NHWC}> to tensor<1x512x32x30xf16, {order = #NHWC}>
    %CONCAT = IE.Concat(%SLICE, %CST_0) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 30]]} : tensor<1x512x32x30xf16, {order = #NHWC}>, tensor<1x512x32x2xf16, {order = #NHWC}>
        -> tensor<1x512x32x32xf16, {order = #NHWC}>
    %CONV_OUT = IE.Convolution(%CONCAT, %WEIGHTS2) {
        dilations = [1, 1],
        pads_begin = [1, 1], pads_end = [1, 1],
        strides = [1, 1]} : tensor<1x512x32x32xf16, {order = #NHWC}>, tensor<512x512x3x3xf16, {order = #NHWC}>
        -> tensor<1x512x32x32xf16, {order = #NHWC}>

    return %CONV_OUT : tensor<1x512x32x32xf16, {order = #NHWC}>

    // CHECK-DAG:   [[WEIGHTS:%.*]] = const.Declare tensor<512x1024x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<512x1024x3x3xf16>, [#const.Reorder<#NHWC>]
    // CHECK-DAG:   [[CST_0:%.*]] = const.Declare tensor<1x512x32x2xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<1x512x32x2xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>]
    // CHECK-DAG:   [[WEIGHTS2:%.*]] = const.Declare tensor<512x512x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<512x512x3x3xf16>, [#const.Reorder<#NHWC>]
    // CHECK:   [[CONV_IN:%.*]] = IE.Convolution(%arg0, [[WEIGHTS]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [1, 1], strides = [1, 1]} :
    // CHECK-SAME:      tensor<1x1024x32x32xf16, {order = #NHWC}>, tensor<512x1024x3x3xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>
    // CHECK-NOT:   IE.Add
    // CHECK:       [[SLICE:%.*]] = IE.Slice [[CONV_IN]] [0, 0, 0, 0] [1, 512, 32, 30] : tensor<1x512x32x32xf16, {order = #NHWC}> to tensor<1x512x32x30xf16, {order = #NHWC}>
    // CHECK:       [[CONCAT:%.*]] = IE.Concat([[SLICE]], [[CST_0]]) {static_offsets = {{\[\[}}0, 0, 0, 0], [0, 0, 0, 30]]} :
    // CHECK-SAME:      tensor<1x512x32x30xf16, {order = #NHWC}>, tensor<1x512x32x2xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>
    // CHECK:       [[CONV_OUT:%.*]] = IE.Convolution([[CONCAT]], [[WEIGHTS2]]) {dilations = [1, 1], pads_begin = [1, 1], pads_end = [1, 1], strides = [1, 1]} :
    // CHECK-SAME:      tensor<1x512x32x32xf16, {order = #NHWC}>, tensor<512x512x3x3xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>

    // CHECK:   return [[CONV_OUT]] : tensor<1x512x32x32xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotOptimizeSliceConcatIfSliceInputNotConv
func.func @NotOptimizeSliceConcatIfSliceInputNotConv(%arg0: tensor<1x512x32x32xf16, {order = #NHWC}>) -> tensor<1x512x32x32xf16, {order = #NHWC}> {
    %ADD_WEIGHTS = const.Declare tensor<1x512x32x32xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<1x512x32x32xf16>, [#const.Reorder<#NHWC>]
    %CST_0 = const.Declare tensor<1x512x32x2xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<1x512x32x2xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>]
    %ADD = IE.Add(%arg0, %ADD_WEIGHTS) {
        auto_broadcast = #IE.auto_broadcast_type<NUMPY>
    } : tensor<1x512x32x32xf16, {order = #NHWC}>, tensor<1x512x32x32xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>
    %SLICE = IE.Slice %ADD [0, 0, 0, 0] [1, 512, 32, 30] : tensor<1x512x32x32xf16, {order = #NHWC}> to tensor<1x512x32x30xf16, {order = #NHWC}>
    %CONCAT = IE.Concat(%SLICE, %CST_0) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 30]]} : tensor<1x512x32x30xf16, {order = #NHWC}>, tensor<1x512x32x2xf16, {order = #NHWC}>
        -> tensor<1x512x32x32xf16, {order = #NHWC}>

    return %CONCAT : tensor<1x512x32x32xf16, {order = #NHWC}>

    // CHECK-DAG:   [[ADD_WEIGHTS:%.*]] = const.Declare tensor<1x512x32x32xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<1x512x32x32xf16>, [#const.Reorder<#NHWC>]
    // CHECK-DAG:   [[CST_0:%.*]] = const.Declare tensor<1x512x32x2xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<1x512x32x2xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>]
    // CHECK:   [[ADD_IN:%.*]] = IE.Add(%arg0, [[ADD_WEIGHTS]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} :
    // CHECK-SAME:      tensor<1x512x32x32xf16, {order = #NHWC}>, tensor<1x512x32x32xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>
    // CHECK:   [[SLICE:%.*]] = IE.Slice %0 [0, 0, 0, 0] [1, 512, 32, 30] : tensor<1x512x32x32xf16, {order = #NHWC}> to tensor<1x512x32x30xf16, {order = #NHWC}>
    // CHECK-NOT:   IE.Add
    // CHECK:   [[CONCAT:%.*]] = IE.Concat([[SLICE]], [[CST_0]]) {static_offsets = {{\[\[}}0, 0, 0, 0], [0, 0, 0, 30]]} :
    // CHECK-SAME:      tensor<1x512x32x30xf16, {order = #NHWC}>, tensor<1x512x32x2xf16, {order = #NHWC}> -> tensor<1x512x32x32xf16, {order = #NHWC}>

    // CHECK:   return [[CONCAT]] : tensor<1x512x32x32xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @FuseSliceIntoPreviousConv
func.func @FuseSliceIntoPreviousConv(%arg0: tensor<1x32x256x256xf16, {order = #NHWC}>) -> tensor<1x8x256x256xf16, {order = #NHWC}> {
    %WEIGHTS = const.Declare tensor<32x32x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<32x32x3x3xf16>, [#const.Reorder<#NHWC>]
    %BIAS = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<1.0e-01> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
    %CONV = IE.Convolution(%arg0, %WEIGHTS, %BIAS) {
        dilations = [1, 1],
        pads_begin = [1, 1], pads_end = [1, 1],
        strides = [1, 1]
    } : tensor<1x32x256x256xf16, {order = #NHWC}>, tensor<32x32x3x3xf16, {order = #NHWC}>, tensor<1x1x1x1xf16, {order = #NHWC}>
        -> tensor<1x32x256x256xf16, {order = #NHWC}>
    %SLICE = IE.Slice %CONV [0, 0, 0, 0] [1, 8, 256, 256] : tensor<1x32x256x256xf16, {order = #NHWC}> to tensor<1x8x256x256xf16, {order = #NHWC}>

    return %SLICE : tensor<1x8x256x256xf16, {order = #NHWC}>

    // CHECK-DAG:   [[WEIGHTS:%.*]] = const.Declare tensor<8x32x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<32x32x3x3xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [8, 32, 3, 3]>]
    // CHECK-DAG:   [[BIAS:%.*]] = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<9.997550e-02> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
    // CHECK-DAG:   [[CONV:%.*]] = IE.Convolution(%arg0, [[WEIGHTS]], [[BIAS]]) {
    // CHECK-SAME:      dilations = [1, 1],
    // CHECK-SAME:      pads_begin = [1, 1], pads_end = [1, 1],
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      } : tensor<1x32x256x256xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<8x32x3x3xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<1x1x1x1xf16, {order = #NHWC}>
    // CHECK-SAME:          -> tensor<1x8x256x256xf16, {order = #NHWC}>

    // CHECK:   return [[CONV]] : tensor<1x8x256x256xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @FuseSliceIntoPreviousConvWithOffset
func.func @FuseSliceIntoPreviousConvWithOffset(%arg0: tensor<1x32x256x256xf16, {order = #NHWC}>) -> tensor<1x8x256x256xf16, {order = #NHWC}> {
    %WEIGHTS = const.Declare tensor<32x32x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<32x32x3x3xf16>, [#const.Reorder<#NHWC>]
    %BIAS = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<1.0e-01> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
    %CONV = IE.Convolution(%arg0, %WEIGHTS, %BIAS) {
        dilations = [1, 1],
        pads_begin = [1, 1], pads_end = [1, 1],
        strides = [1, 1]
    } : tensor<1x32x256x256xf16, {order = #NHWC}>, tensor<32x32x3x3xf16, {order = #NHWC}>, tensor<1x1x1x1xf16, {order = #NHWC}>
        -> tensor<1x32x256x256xf16, {order = #NHWC}>
    %SLICE = IE.Slice %CONV [0, 1, 0, 0] [1, 8, 256, 256] : tensor<1x32x256x256xf16, {order = #NHWC}> to tensor<1x8x256x256xf16, {order = #NHWC}>

    return %SLICE : tensor<1x8x256x256xf16, {order = #NHWC}>

    // CHECK-DAG:   [[WEIGHTS:%.*]] = const.Declare tensor<8x32x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<32x32x3x3xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 1, 0, 0], [8, 32, 3, 3]>]
    // CHECK-DAG:   [[BIAS:%.*]] = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<9.997550e-02> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
    // CHECK-DAG:   [[CONV:%.*]] = IE.Convolution(%arg0, [[WEIGHTS]], [[BIAS]]) {
    // CHECK-SAME:      dilations = [1, 1],
    // CHECK-SAME:      pads_begin = [1, 1], pads_end = [1, 1],
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      } : tensor<1x32x256x256xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<8x32x3x3xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<1x1x1x1xf16, {order = #NHWC}>
    // CHECK-SAME:          -> tensor<1x8x256x256xf16, {order = #NHWC}>

    // CHECK:   return [[CONV]] : tensor<1x8x256x256xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotFuseSliceIntoPreviousConvDueTONotEfficient
func.func @NotFuseSliceIntoPreviousConvDueTONotEfficient(%arg0: tensor<1x32x64x64xf16, {order = #NHWC}>) -> tensor<1x8x64x64xf16, {order = #NHWC}> {
    %WEIGHTS = const.Declare tensor<32x32x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<32x32x3x3xf16>, [#const.Reorder<#NHWC>]
    %BIAS = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<1.0e-01> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
    %CONV = IE.Convolution(%arg0, %WEIGHTS, %BIAS) {
        dilations = [1, 1],
        pads_begin = [1, 1], pads_end = [1, 1],
        strides = [1, 1]
    } : tensor<1x32x64x64xf16, {order = #NHWC}>, tensor<32x32x3x3xf16, {order = #NHWC}>, tensor<1x1x1x1xf16, {order = #NHWC}>
        -> tensor<1x32x64x64xf16, {order = #NHWC}>
    %SLICE = IE.Slice %CONV [0, 1, 0, 0] [1, 8, 64, 64] : tensor<1x32x64x64xf16, {order = #NHWC}> to tensor<1x8x64x64xf16, {order = #NHWC}>

    return %SLICE : tensor<1x8x64x64xf16, {order = #NHWC}>

    // CHECK-DAG:   [[WEIGHTS:%.*]] = const.Declare tensor<32x32x3x3xf16, {order = #NHWC}> = dense<1.250000e-01> : tensor<32x32x3x3xf16>, [#const.Reorder<#NHWC>]
    // CHECK-DAG:   [[BIAS:%.*]] = const.Declare tensor<1x1x1x1xf16, {order = #NHWC}> = dense<9.997550e-02> : tensor<1x1x1x1xf16>, [#const.Reorder<#NHWC>]
    // CHECK-DAG:   [[CONV:%.*]] = IE.Convolution(%arg0, [[WEIGHTS]], [[BIAS]]) {
    // CHECK-SAME:      dilations = [1, 1],
    // CHECK-SAME:      pads_begin = [1, 1], pads_end = [1, 1],
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      } : tensor<1x32x64x64xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<32x32x3x3xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<1x1x1x1xf16, {order = #NHWC}>
    // CHECK-SAME:          -> tensor<1x32x64x64xf16, {order = #NHWC}>
    // CHECK-DAG:   [[SLICE:%.*]] = IE.Slice [[CONV]] [0, 1, 0, 0] [1, 8, 64, 64] : tensor<1x32x64x64xf16, {order = #NHWC}> to tensor<1x8x64x64xf16, {order = #NHWC}>

    // CHECK:   return [[SLICE]] : tensor<1x8x64x64xf16, {order = #NHWC}>
}