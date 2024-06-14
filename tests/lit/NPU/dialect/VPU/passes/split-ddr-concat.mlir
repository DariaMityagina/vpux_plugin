//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --split-ddr-concat %s | FileCheck %s
// REQUIRES: arch-VPUX40XX

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @PartialCMXConcat
func.func @PartialCMXConcat(
            %input1: tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}>,
            %filter: tensor<64x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
            %weightsTable: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN}>,
            %concatInput0 : tensor<1x64x10x512xf16, {order = #NHWC}>,
            %concatInput1 : tensor<1x64x10x512xf16, {order = #NHWC}>)
           -> tensor<1x64x32x512xf16, {order = #NHWC}> {

    %slice1  = VPU.Slice %input1 [0, 0, 0, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice2  = VPU.Slice %input1 [0, 0, 1, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice3  = VPU.Slice %input1 [0, 0, 2, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice4  = VPU.Slice %input1 [0, 0, 3, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice5  = VPU.Slice %input1 [0, 0, 4, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice6  = VPU.Slice %input1 [0, 0, 5, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice7  = VPU.Slice %input1 [0, 0, 6, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice8  = VPU.Slice %input1 [0, 0, 7, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice9  = VPU.Slice %input1 [0, 0, 8, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice10 = VPU.Slice %input1 [0, 0, 9, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice11 = VPU.Slice %input1 [0, 0, 10, 0] [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %slice12 = VPU.Slice %input1 [0, 0, 11, 0] [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>

    %dw1 =  VPU.NCE.DepthConvolution(%slice1, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw2 =  VPU.NCE.DepthConvolution(%slice2, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw3 =  VPU.NCE.DepthConvolution(%slice3, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw4 =  VPU.NCE.DepthConvolution(%slice4, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw5 =  VPU.NCE.DepthConvolution(%slice5, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw6 =  VPU.NCE.DepthConvolution(%slice6, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw7 =  VPU.NCE.DepthConvolution(%slice7, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw8 =  VPU.NCE.DepthConvolution(%slice8, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw9 =  VPU.NCE.DepthConvolution(%slice9, %filter, %weightsTable)  {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw10 = VPU.NCE.DepthConvolution(%slice10, %filter, %weightsTable) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw11 = VPU.NCE.DepthConvolution(%slice11, %filter, %weightsTable) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %dw12 = VPU.NCE.DepthConvolution(%slice12, %filter, %weightsTable) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>

    %copy1  = VPU.Copy(%dw1)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy2  = VPU.Copy(%dw2)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy3  = VPU.Copy(%dw3)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy4  = VPU.Copy(%dw4)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy5  = VPU.Copy(%dw5)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy6  = VPU.Copy(%dw6)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy7  = VPU.Copy(%dw7)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy8  = VPU.Copy(%dw8)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy9  = VPU.Copy(%dw9)  : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy10 = VPU.Copy(%dw10) : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy11 = VPU.Copy(%dw11) : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>
    %copy12 = VPU.Copy(%dw12) : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x1x512xf16, {order = #NHWC}>

    %concat = VPU.Concat(%concatInput0, %copy1, %copy2, %copy3, %copy4, %copy5, %copy6, %copy7, %copy8, %copy9, %copy10, %copy11, %copy12, %concatInput1) {per_axis = #IE.Concat<axis = 2 : i64>} :
        tensor<1x64x10x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>,
        tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>,
        tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x1x512xf16, {order = #NHWC}>,
        tensor<1x64x1x512xf16, {order = #NHWC}>, tensor<1x64x10x512xf16, {order = #NHWC}> -> tensor<1x64x32x512xf16, {order = #NHWC}>

    return %concat : tensor<1x64x32x512xf16, {order = #NHWC}>

    // CHECK: [[SLICE0:%.+]]  = VPU.Slice %arg0 [0, 0, 0, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE1:%.+]]  = VPU.Slice %arg0 [0, 0, 1, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE2:%.+]]  = VPU.Slice %arg0 [0, 0, 2, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE3:%.+]]  = VPU.Slice %arg0 [0, 0, 3, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE4:%.+]]  = VPU.Slice %arg0 [0, 0, 4, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE5:%.+]]  = VPU.Slice %arg0 [0, 0, 5, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE6:%.+]]  = VPU.Slice %arg0 [0, 0, 6, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE7:%.+]]  = VPU.Slice %arg0 [0, 0, 7, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE8:%.+]]  = VPU.Slice %arg0 [0, 0, 8, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE9:%.+]]  = VPU.Slice %arg0 [0, 0, 9, 0]  [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE10:%.+]] = VPU.Slice %arg0 [0, 0, 10, 0] [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[SLICE11:%.+]] = VPU.Slice %arg0 [0, 0, 11, 0] [1, 64, 2, 512] : tensor<1x64x512x512xf16, {mem_space = @CMX_NN, order = #NHWC}> to tensor<1x64x2x512xf16, {mem_space = @CMX_NN, order = #NHWC}>

    // CHECK: [[DWCONV0:%.+]]  = VPU.NCE.DepthConvolution([[SLICE0]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV1:%.+]]  = VPU.NCE.DepthConvolution([[SLICE1]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV2:%.+]]  = VPU.NCE.DepthConvolution([[SLICE2]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV3:%.+]]  = VPU.NCE.DepthConvolution([[SLICE3]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV4:%.+]]  = VPU.NCE.DepthConvolution([[SLICE4]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV5:%.+]]  = VPU.NCE.DepthConvolution([[SLICE5]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV6:%.+]]  = VPU.NCE.DepthConvolution([[SLICE6]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV7:%.+]]  = VPU.NCE.DepthConvolution([[SLICE7]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV8:%.+]]  = VPU.NCE.DepthConvolution([[SLICE8]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV9:%.+]]  = VPU.NCE.DepthConvolution([[SLICE9]],  %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV10:%.+]] = VPU.NCE.DepthConvolution([[SLICE10]], %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DWCONV11:%.+]] = VPU.NCE.DepthConvolution([[SLICE11]], %arg1, %arg2) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>, rawFilterShape = [64, 1, 2, 1], strides = [1, 1]} -> tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>

    // CHECK: [[CMXCONCAT0:%.+]] = VPU.Concat([[DWCONV0]], [[DWCONV1]], [[DWCONV2]], [[DWCONV3]], [[DWCONV4]], [[DWCONV5]], [[DWCONV6]]) {per_axis = #IE.Concat<axis = 2 : i64>} : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x7x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DDRCOPY0:%.+]]   = VPU.Copy([[CMXCONCAT0]]) : tensor<1x64x7x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x7x512xf16, {order = #NHWC}>
    // CHECK: [[CMXCONCAT1:%.+]] = VPU.Concat([[DWCONV7]], [[DWCONV8]], [[DWCONV9]], [[DWCONV10]], [[DWCONV11]]) {per_axis = #IE.Concat<axis = 2 : i64>} : tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x64x1x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x5x512xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK: [[DDRCOPY1:%.+]]   = VPU.Copy([[CMXCONCAT1]]) : tensor<1x64x5x512xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x5x512xf16, {order = #NHWC}>
    // CHECK: [[DDRCONCAT:%.+]]  = VPU.Concat(%arg3, [[DDRCOPY0]], [[DDRCOPY1]], %arg4) {per_axis = #IE.Concat<axis = 2 : i64>} : tensor<1x64x10x512xf16, {order = #NHWC}>, tensor<1x64x7x512xf16, {order = #NHWC}>, tensor<1x64x5x512xf16, {order = #NHWC}>, tensor<1x64x10x512xf16, {order = #NHWC}> -> tensor<1x64x32x512xf16, {order = #NHWC}>
    // CHECK: return [[DDRCONCAT]] : tensor<1x64x32x512xf16, {order = #NHWC}>
}
