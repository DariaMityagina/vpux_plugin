//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --adjust-input-data-for-explicit-se-table %s | FileCheck %s
// REQUIRES: arch-VPUX30XX || arch-VPUX37XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

func.func @SparseConvSETable(%arg0: memref<1x48x10x10xf16, #NHWC, [@CMX_NN, 0]>, %arg1: memref<1x48x3x3xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x48x3x3xf16, #NHWC, [@CMX_NN, 0]> {
  %cst_weights = const.Declare memref<48x48x1x1xf16, #NHWC> = dense<1.0> : tensor<48x48x1x1xf16, {order = #NHWC}>
  %cst_weights_table = const.Declare memref<48x1x1x4xsi32> = dense<1> : tensor<48x1x1x4xsi32>
  %cst_input_sm = const.Declare memref<1x48x12x21xi1, #NHWC> = dense<1> : tensor<1x48x12x21xi1, {order = #NHWC}>
  %cst_input_se = const.Declare memref<1x3x12x21xi32, #NHWC> = dense<1> : tensor<1x3x12x21xi32, {order = #NHWC}>

  %barrier = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

  %input = VPURT.DeclareBuffer "CMX_NN" [0] <0> -> memref<1x48x6x10xf16, #NHWC, [@CMX_NN, 0]>
  %input_sm = VPURT.DeclareBuffer "CMX_NN" [0] <0> -> memref<1x48x12x21xi1, #NHWC, [@CMX_NN, 0]>
  %input_se = VPURT.DeclareBuffer "CMX_NN" [0] <0> -> memref<1x3x12x21xi32, #NHWC, [@CMX_NN, 0]>
  %output = VPURT.DeclareBuffer "CMX_NN" [0] <0> -> memref<1x48x3x3xf16, #NHWC, [@CMX_NN, 0]>
  %parent_input = VPURT.DeclareBuffer "CMX_NN" <0> -> !VPUIP.DistributedBuffer<1x48x10x10xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
  %parent_input_sm = VPURT.DeclareBuffer "CMX_NN" <0> -> !VPUIP.DistributedBuffer<1x48x21x21xi1, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
  %parent_input_se = VPURT.DeclareBuffer "CMX_NN" <0> -> !VPUIP.DistributedBuffer<1x3x21x21xi32, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 1, 1, 1]}>
  %parent_output = VPURT.DeclareBuffer "CMX_NN" <0> -> !VPUIP.DistributedBuffer<1x48x20x20xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
  %weights = VPURT.DeclareBuffer "CMX_NN" [0] <0> -> memref<48x48x1x1xf16, #NHWC, [@CMX_NN, 0]>
  %weights_table = VPURT.DeclareBuffer "CMX_NN" [0] <0> -> memref<48x1x1x4xsi32, [@CMX_NN, 0]>

  VPURT.Task updates(%barrier : !VPURT.Barrier) attributes {cycleBegin = 0 : i64, cycleEnd = 100 : i64, isTrailingSWLayer = false} {
    %out = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_weights : memref<48x48x1x1xf16, #NHWC>) outputs(%weights : memref<48x48x1x1xf16, #NHWC, [@CMX_NN, 0]>) -> memref<48x48x1x1xf16, #NHWC, [@CMX_NN, 0]>
  }
  VPURT.Task updates(%barrier : !VPURT.Barrier) attributes {cycleBegin = 100 : i64, cycleEnd = 200 : i64, isTrailingSWLayer = false} {
    %out = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_weights_table : memref<48x1x1x4xsi32>) outputs(%weights_table : memref<48x1x1x4xsi32, [@CMX_NN, 0]>) -> memref<48x1x1x4xsi32, [@CMX_NN, 0]>
  }
  VPURT.Task updates(%barrier : !VPURT.Barrier) attributes {cycleBegin = 200 : i64, cycleEnd = 300 : i64, isTrailingSWLayer = false} {
    %out = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_input_sm : memref<1x48x12x21xi1, #NHWC>) outputs(%input_sm : memref<1x48x12x21xi1, #NHWC, [@CMX_NN, 0]>) -> memref<1x48x12x21xi1, #NHWC, [@CMX_NN, 0]>
  }
  VPURT.Task updates(%barrier : !VPURT.Barrier) attributes {cycleBegin = 300 : i64, cycleEnd = 400 : i64, isTrailingSWLayer = false} {
    %out = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_input_se : memref<1x3x12x21xi32, #NHWC>) outputs(%input_se : memref<1x3x12x21xi32, #NHWC, [@CMX_NN, 0]>) -> memref<1x3x12x21xi32, #NHWC, [@CMX_NN, 0]>
  }

  VPURT.Task waits(%barrier : !VPURT.Barrier) attributes {cycleBegin = 400 : i64, cycleEnd = 500 : i64, isTrailingSWLayer = false} {
    %out = VPUIP.NCEClusterTask {input_se_size = 16 : i64, kernel_padding = {bottom = 0 : i64, left = 0 : i64, right = 0 : i64, top = 0 : i64}, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = "CONV"}
            input(%input : memref<1x48x6x10xf16, #NHWC, [@CMX_NN, 0]>)
            input_sparsity_map(%input_sm : memref<1x48x12x21xi1, #NHWC, [@CMX_NN, 0]>)
            input_storage_element_table(%input_se : memref<1x3x12x21xi32, #NHWC, [@CMX_NN, 0]>)
            weights(%weights : memref<48x48x1x1xf16, #NHWC, [@CMX_NN, 0]>)
            weight_table(%weights_table : memref<48x1x1x4xsi32, [@CMX_NN, 0]>)
            parent_input(%parent_input : !VPUIP.DistributedBuffer<1x48x10x10xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
            parent_input_sparsity_map(%parent_input_sm : !VPUIP.DistributedBuffer<1x48x21x21xi1, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
            parent_input_storage_element_table(%parent_input_se : !VPUIP.DistributedBuffer<1x3x21x21xi32, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 1, 1, 1]}>)
            parent_output(%parent_output : !VPUIP.DistributedBuffer<1x48x20x20xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
            outputs(%output : memref<1x48x3x3xf16, #NHWC, [@CMX_NN, 0]>)
    -> memref<1x48x3x3xf16, #NHWC, [@CMX_NN, 0]> variants : {
      DPUTask {cluster_id = 0 : i64, mpe_mode = "CUBOID_16x16", outEnd = [15, 2, 63], outStart = [0, 0, 0], pad = {bottom = 0 : i64, left = 0 : i64, right = 0 : i64, top = 0 : i64}}
    } PPE : {
      PPETask "NOOP" {clamp_high = 2147483647 : i64, clamp_low = -2147483648 : i64, fp_prelu_alpha = 1.000000e+00 : f64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64}
    }
  }

  return %arg1 : memref<1x48x3x3xf16, #NHWC, [@CMX_NN, 0]>

  // CHECK:       VPUIP.NCEClusterTask
  // CHECK-NOT:      input({{%.+}} : memref<1x48x6x10xf16, #NHWC, [@CMX_NN, 0]>)
  // CHECK:          input({{%.+}} : memref<1x48x12x21xf16, #NHWC, [@CMX_NN, 0]>)
  // CHECK-NOT:      parent_input({{%.+}} : !VPUIP.DistributedBuffer<1x48x10x10xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
  // CHECK:          parent_input({{%.+}} : !VPUIP.DistributedBuffer<1x48x21x21xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
}
