//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --canonicalize %s | FileCheck %s
// REQUIRES: arch-VPUX30XX || arch-VPUX37XX

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

// CHECK-LABEL:   @FoldMemPermute
func.func @FoldMemPermute(%arg0: tensor<1x16x2x3xf32>) -> tensor<1x16x2x3xf32> {
    %0 = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NCHW} :
        tensor<1x16x2x3xf32> -> tensor<1x16x2x3xf32>
    return %0 : tensor<1x16x2x3xf32>

    // CHECK-NOT: IE.MemPermute
    // CHECK:     return %arg0 : tensor<1x16x2x3xf32>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>
#NCWH = affine_map<(d0, d1, d2, d3) -> (d0, d1, d3, d2)>
#NWHC = affine_map<(d0, d1, d2, d3) -> (d0, d3, d2, d1)>

// CHECK-LABEL:   @FuseMemPermutes
func.func @FuseMemPermutes(%arg0: tensor<1x16x2x3xf32>, %arg1: tensor<1x16x2x3xf32, {order = #NHWC}>) ->
        (tensor<1x3x2x16xf32>, tensor<1x3x16x2xf32>) {
    %0 = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x16x2x3xf32> -> tensor<1x3x16x2xf32>
    %1 = IE.MemPermute(%0) {dst_order = #NCHW, mem_perm = #NCWH} :
        tensor<1x3x16x2xf32> -> tensor<1x3x2x16xf32>

    %2 = IE.MemPermute(%arg1) {dst_order = #NHWC, mem_perm = #NWCH} :
        tensor<1x16x2x3xf32, {order = #NHWC}> -> tensor<1x3x16x2xf32, {order = #NHWC}>
    %3 = IE.MemPermute(%2) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x3x16x2xf32, {order = #NHWC}> -> tensor<1x3x16x2xf32>

    return %1, %3 : tensor<1x3x2x16xf32>, tensor<1x3x16x2xf32>

    // CHECK-NOT: IE.MemPermute
    // CHECK-NOT: IE.MemPermute
    // CHECK:     %[[VAL_0:.*]] = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWHC} : tensor<1x16x2x3xf32> -> tensor<1x3x2x16xf32>
    // CHECK:     %[[VAL_1:.*]] = IE.MemPermute(%arg1) {dst_order = #NCHW, mem_perm = #NHWC} : tensor<1x16x2x3xf32, {order = #NHWC}> -> tensor<1x3x16x2xf32>
    // CHECK:     return %[[VAL_0]], %[[VAL_1]] : tensor<1x3x2x16xf32>, tensor<1x3x16x2xf32>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>

// CHECK-LABEL:   @ConvertToPermuteCast
func.func @ConvertToPermuteCast(
        %arg0: tensor<1x100x1x1xf32>,
        %arg1: tensor<1x100x1x1xf32, {order = #NHWC}>,
        %arg2: tensor<1x1x256x32xf32, {order = #NHWC}>,
        %arg3: tensor<1x512x2x1xf32, {order = #NHWC}>) ->
            (tensor<1x1x100x1xf32>, tensor<1x1x1x100xf32>, tensor<1x1x256x32xf32>, tensor<1x2x1x512xf32>) {
    %0 = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x100x1x1xf32> -> tensor<1x1x100x1xf32>

    %1 = IE.MemPermute(%arg1) {dst_order = #NCHW, mem_perm = #NCHW} :
        tensor<1x100x1x1xf32, {order = #NHWC}> -> tensor<1x1x1x100xf32>

    %2 = IE.MemPermute(%arg2) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x1x256x32xf32, {order = #NHWC}> -> tensor<1x1x256x32xf32>

    %3 = IE.MemPermute(%arg3) {dst_order = #NCHW, mem_perm = #NCHW} :
        tensor<1x512x2x1xf32, {order = #NHWC}> -> tensor<1x2x1x512xf32>

    return %0, %1, %2, %3 : tensor<1x1x100x1xf32>, tensor<1x1x1x100xf32>, tensor<1x1x256x32xf32>, tensor<1x2x1x512xf32>

    //CHECK: [[VAR0:%.+]] = IE.PermuteCast(%arg0) {dst_order = #NCHW, mem_perm = #NWCH}
    //CHECK: [[VAR1:%.+]] = IE.PermuteCast(%arg1) {dst_order = #NCHW, mem_perm = #NCHW}
    //CHECK: [[VAR2:%.+]] = IE.PermuteCast(%arg2) {dst_order = #NCHW, mem_perm = #NWCH}
    //CHECK: [[VAR3:%.+]] = IE.PermuteCast(%arg3) {dst_order = #NCHW, mem_perm = #NCHW}
    //CHECK: return [[VAR0]], [[VAR1]], [[VAR2]], [[VAR3]] : tensor<1x1x100x1xf32>, tensor<1x1x1x100xf32>, tensor<1x1x256x32xf32>, tensor<1x2x1x512xf32>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>

// CHECK-LABEL:   @FusePermCastAndMemPerm
func.func @FusePermCastAndMemPerm(%arg0: tensor<1x1000x1x1xf32, {order = #NHWC}>) ->
            tensor<1x1x1000x1xf32> {
    %0 = IE.PermuteCast(%arg0) {dst_order = #NHWC, mem_perm = #NWCH} :
            tensor<1x1000x1x1xf32, {order = #NHWC}> -> tensor<1x1x1000x1xf32, {order = #NHWC}>
    %1 = IE.MemPermute(%0) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x1x1000x1xf32, {order = #NHWC}> -> tensor<1x1x1000x1xf32>

    return %1 : tensor<1x1x1000x1xf32>

    // CHECK:     %[[VAL_0:.*]] = IE.PermuteCast(%arg0) {dst_order = #NCHW, mem_perm = #NHWC} : tensor<1x1000x1x1xf32, {order = #NHWC}> -> tensor<1x1x1000x1xf32>
    // CHECK:     return %[[VAL_0]] : tensor<1x1x1000x1xf32>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>
#NCWH = affine_map<(d0, d1, d2, d3) -> (d0, d1, d3, d2)>

// CHECK-LABEL:   @NotFuseMemPermute
func.func @NotFuseMemPermute(%arg0: tensor<1x8x4x64xf16>) -> (tensor<1x64x8x4xf16>, tensor<1x64x4x8xf16>, tensor<1x4x64x8xf16, {order = #NHWC}>) {
    %0 = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x8x4x64xf16> -> tensor<1x64x8x4xf16>
    %1 = IE.MemPermute(%0) {dst_order = #NCHW, mem_perm = #NCWH} :
        tensor<1x64x8x4xf16> -> tensor<1x64x4x8xf16>
    %2 = IE.PermuteCast(%0) {dst_order = #NHWC, mem_perm = #NCHW} :
        tensor<1x64x8x4xf16> -> tensor<1x4x64x8xf16, {order = #NHWC}>

    return %0, %1, %2 : tensor<1x64x8x4xf16>, tensor<1x64x4x8xf16>, tensor<1x4x64x8xf16, {order = #NHWC}>

    // CHECK:     %[[VAL_0:.*]] = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWCH} : tensor<1x8x4x64xf16> -> tensor<1x64x8x4xf16>
    // CHECK:     %[[VAL_1:.*]] = IE.MemPermute(%0) {dst_order = #NCHW, mem_perm = #NCWH} : tensor<1x64x8x4xf16> -> tensor<1x64x4x8xf16>
    // CHECK:     %[[VAL_2:.*]] = IE.PermuteCast(%0) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x64x8x4xf16> -> tensor<1x4x64x8xf16, {order = #NHWC}>
    // CHECK:     return %[[VAL_0]], %[[VAL_1]], %[[VAL_2]]  : tensor<1x64x8x4xf16>, tensor<1x64x4x8xf16>, tensor<1x4x64x8xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>
#NCWH = affine_map<(d0, d1, d2, d3) -> (d0, d1, d3, d2)>

// CHECK-LABEL:   @FuseMemPermuteForAllUserMemPerm
func.func @FuseMemPermuteForAllUserMemPerm(%arg0: tensor<1x8x4x64xf16>) -> tensor<1x64x8x4xf16> {
    %0 = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x8x4x64xf16> -> tensor<1x64x8x4xf16>
    %1 = IE.MemPermute(%0) {dst_order = #NCHW, mem_perm = #NCWH} :
        tensor<1x64x8x4xf16> -> tensor<1x64x4x8xf16>
    %2 = IE.MemPermute(%0) {dst_order = #NHWC, mem_perm = #NCHW} :
        tensor<1x64x8x4xf16> -> tensor<1x4x64x8xf16, {order = #NHWC}>

    return %0 : tensor<1x64x8x4xf16>

    // CHECK:     %[[VAL_0:.*]] = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWCH} : tensor<1x8x4x64xf16> -> tensor<1x64x8x4xf16>
    // CHECK-NOT: IE.MemPermute
    // CHECK-NOT: IE.MemPermute
    // CHECK:     return %[[VAL_0]] : tensor<1x64x8x4xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>
#NCWH = affine_map<(d0, d1, d2, d3) -> (d0, d1, d3, d2)>

// CHECK-LABEL:   @FuseFP16PermuteQuantizeAndPermute
func.func @FuseFP16PermuteQuantizeAndPermute(%arg0: tensor<1x3x13x26xf16>) -> tensor<1x3x169x2xf16> {
    %0 = IE.PermuteQuantize(%arg0) {dstElemType = f16, dst_order = #NHWC, mem_perm = #NHWC, pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0]} : tensor<1x3x13x26xf16> -> tensor<1x3x13x26xf16, {order = #NHWC}>
    %1 = IE.MemPermute(%0) {dst_order = #NCHW, mem_perm = #NWCH} : tensor<1x3x13x26xf16, {order = #NHWC}> -> tensor<1x3x13x26xf16>
    %2 = IE.Reshape(%1) {shape_value = [1, 3, 169, 2]} : tensor<1x3x13x26xf16> -> tensor<1x3x169x2xf16>
    %3 = IE.Add(%2, %2) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x3x169x2xf16>, tensor<1x3x169x2xf16> -> tensor<1x3x169x2xf16>

    return %3 : tensor<1x3x169x2xf16>

    // CHECK-NOT: IE.PermuteQuantize
    // CHECK-NOT: IE.MemPermute
    // CHECK:     %[[VAL_0:.*]] = IE.Reshape(%arg0) {shape_value = [1, 3, 169, 2]} : tensor<1x3x13x26xf16> -> tensor<1x3x169x2xf16>
    // CHECK:     %[[VAL_1:.*]] = IE.Add(%[[VAL_0]], %[[VAL_0]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x3x169x2xf16>, tensor<1x3x169x2xf16> -> tensor<1x3x169x2xf16>

    // CHECK:     return %[[VAL_1]] : tensor<1x3x169x2xf16>
}

// -----

!qElemType0 = !quant.uniform<u8:f16, 0.0033655795396543018>

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>
#NCWH = affine_map<(d0, d1, d2, d3) -> (d0, d1, d3, d2)>

// CHECK-LABEL:   @NotFuseU8PermuteQuantizeAndPermute
func.func @NotFuseU8PermuteQuantizeAndPermute(%arg0: tensor<1x3x13x26xf16>) -> tensor<1x3x169x2xf16> {
    %0 = IE.PermuteQuantize(%arg0) {dstElemType = !qElemType0, dst_order = #NHWC, mem_perm = #NHWC, pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0]} : tensor<1x3x13x26xf16> -> tensor<1x3x13x26x!qElemType0, {order = #NHWC}>
    %1 = IE.MemPermute(%0) {dst_order = #NCHW, mem_perm = #NWCH} : tensor<1x3x13x26x!qElemType0, {order = #NHWC}> -> tensor<1x3x13x26x!qElemType0>
    %2 = IE.Reshape(%1) {shape_value = [1, 3, 169, 2]} : tensor<1x3x13x26x!qElemType0> -> tensor<1x3x169x2x!qElemType0>
    %3 = IE.Add(%2, %2) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x3x169x2x!qElemType0>, tensor<1x3x169x2x!qElemType0> -> tensor<1x3x169x2xf16>

    return %3 : tensor<1x3x169x2xf16>

    // CHECK:     %[[VAL_0:.*]] = IE.PermuteQuantize(%arg0) {dstElemType = !qElemType, dst_order = #NHWC, mem_perm = #NHWC, pads_begin = [0, 0, 0, 0], pads_end = [0, 0, 0, 0]} : tensor<1x3x13x26xf16> -> tensor<1x3x13x26x!qElemType, {order = #NHWC}>
    // CHECK:     %[[VAL_1:.*]] = IE.MemPermute(%[[VAL_0]]) {dst_order = #NCHW, mem_perm = #NWCH} : tensor<1x3x13x26x!qElemType, {order = #NHWC}> -> tensor<1x3x13x26x!qElemType>
    // CHECK:     %[[VAL_3:.*]] = IE.Reshape(%[[VAL_1]]) {shape_value = [1, 3, 169, 2]} : tensor<1x3x13x26x!qElemType> -> tensor<1x3x169x2x!qElemType>
    // CHECK:     %[[VAL_4:.*]] = IE.Add(%[[VAL_3]], %[[VAL_3]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x3x169x2x!qElemType>, tensor<1x3x169x2x!qElemType> -> tensor<1x3x169x2xf16>

    // CHECK:     return %[[VAL_4]] : tensor<1x3x169x2xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL:   @FuseMemPermThroughConcat
func.func @FuseMemPermThroughConcat(%arg0: tensor<1x16x2x3xf32>, %arg1: tensor<1x16x2x3xf32>) ->
            tensor<1x2x6x16xf32> {
    %0 = IE.MemPermute(%arg0) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x16x2x3xf32> -> tensor<1x3x16x2xf32>
    %1 = IE.MemPermute(%arg1) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x16x2x3xf32> -> tensor<1x3x16x2xf32>

    %2 = IE.Concat(%0, %1) {
        per_axis = {axis = 1}
    } : tensor<1x3x16x2xf32>, tensor<1x3x16x2xf32> -> tensor<1x6x16x2xf32>

    %3 = IE.MemPermute(%2) {dst_order = #NCHW, mem_perm = #NWCH} :
        tensor<1x6x16x2xf32> -> tensor<1x2x6x16xf32>

    return %3 : tensor<1x2x6x16xf32>

    // CHECK-NOT:     IE.MemPermute

    // CHECK:     %[[VAL_0:.*]] = IE.Concat(%arg0, %arg1)
    // CHECK-SAME{LITERAL}:     {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 3]]}
    // CHECK-SAME:     tensor<1x16x2x3xf32>, tensor<1x16x2x3xf32> -> tensor<1x16x2x6xf32>

    // CHECK:     %[[VAL_1:.*]] = IE.MemPermute(%[[VAL_0:.*]]) {dst_order = #NCHW, mem_perm = #NHWC} : tensor<1x16x2x6xf32> -> tensor<1x2x6x16xf32>
    // CHECK:     return %[[VAL_1:.*]] : tensor<1x2x6x16xf32>
}
