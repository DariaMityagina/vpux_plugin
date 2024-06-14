//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//


// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --convert-VPUIP-to-VPUMI40XX %s | FileCheck %s
// REQUIRES: arch-VPUX40XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
module @mainModule {

  IE.CNNNetwork entryPoint : @multiple_clusters_dpu_soh_f16_f16_f16 inputsInfo : {
    DataInfo "input_0" : tensor<1x32x32x32xf16>
  } outputsInfo : {
    DataInfo "output_0" : tensor<1x64x16x32xf16>
    DataInfo "output_1" : tensor<1x64x16x32xf16>
  }

func.func private @multiple_clusters_dpu_soh_f16_f16_f16(%arg0: memref<1x32x32x32xf16, #NHWC, @DDR>, %arg1: memref<1x64x16x32xf16, #NHWC, @DDR>, %arg2: memref<1x64x16x32xf16, #NHWC, @DDR>) -> (memref<1x64x16x32xf16, #NHWC, @DDR>, memref<1x64x16x32xf16, #NHWC, @DDR>) {
  %0 = VPURT.ConfigureBarrier<0> -> !VPURT.Barrier
  %1 = VPURT.ConfigureBarrier<1> -> !VPURT.Barrier

  %cst = const.Declare memref<64x32x1x1xf16, #NHWC, @DDR> = dense<1.000000e+00> : tensor<64x32x1x1xf16>, [#const.Reorder<#NHWC>]
  %cst_0 = const.Declare memref<64x1x1x4xsi32, #NHWC, @DDR> = dense<1> : tensor<64x1x1x4xsi32>, [#const.Reorder<#NHWC>]

  %2 = VPURT.DeclareBuffer <NetworkInput> [0] <0> -> memref<1x32x16x32xf16, #NHWC, [@DDR, 0]>
  %3 = VPURT.DeclareBuffer <NetworkInput> [0] <32768> -> memref<1x32x16x32xf16, #NHWC, [@DDR, 0]>
  %4 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <0> -> !VPUIP.DistributedBuffer<64x32x1x1xf16, {order = #NHWC, strides = [32, 1, 32, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
  %5 = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<64x32x1x1xf16, #NHWC, [@CMX_NN, 0]>
  %6 = VPURT.DeclareBuffer <CMX_NN> [1] <0> -> memref<64x32x1x1xf16, #NHWC, [@CMX_NN, 1]>
  %7 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <4096> -> !VPUIP.DistributedBuffer<1x64x32x32xf16, {order = #NHWC, strides = [65536, 1, 2048, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>
  %8 = VPURT.DeclareBuffer <CMX_NN> [0] <4096> -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]>
  %9 = VPURT.DeclareBuffer <CMX_NN> [1] <4096> -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 1]>
  %10 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <69632> -> !VPUIP.DistributedBuffer<1x32x32x32xf16, {order = #NHWC, strides = [32768, 1, 1024, 32]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 1, 1], uniform_distributed_segments}>
  %11 = VPURT.DeclareBuffer <CMX_NN> [0] <69632> -> memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 0]>
  %12 = VPURT.DeclareBuffer <CMX_NN> [1] <69632> -> memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 1]>
  %13 = VPURT.DeclareBuffer <CMX_NN> [0] <102400> -> memref<64x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>
  %14 = VPURT.DeclareBuffer <CMX_NN> [1] <102400> -> memref<64x1x1x4xsi32, #NHWC, [@CMX_NN, 1]>
  %15 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <102400> -> !VPUIP.DistributedBuffer<64x1x1x4xsi32, {order = #NHWC, strides = [4, 1, 4, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>

  VPURT.Task updates(%0 : !VPURT.Barrier) {
    %18 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst : memref<64x32x1x1xf16, #NHWC, @DDR>) outputs(%4 : !VPUIP.DistributedBuffer<64x32x1x1xf16, {order = #NHWC, strides = [32, 1, 32, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>) -> !VPUIP.DistributedBuffer<64x32x1x1xf16, {order = #NHWC, strides = [32, 1, 32, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
  }
  VPURT.Task updates(%0 : !VPURT.Barrier) {
    %18 = VPUIP.NNDMA {port = 0 : i64} inputs(%2 : memref<1x32x16x32xf16, #NHWC, [@DDR, 0]>) outputs(%11 : memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 0]>
  }
  VPURT.Task updates(%0 : !VPURT.Barrier) {
    %18 = VPUIP.NNDMA {port = 0 : i64} inputs(%3 : memref<1x32x16x32xf16, #NHWC, [@DDR, 0]>) outputs(%12 : memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 1]>) -> memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 1]>
  }
  VPURT.Task updates(%0 : !VPURT.Barrier) {
    %18 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_0 : memref<64x1x1x4xsi32, #NHWC, @DDR>) outputs(%15 : !VPUIP.DistributedBuffer<64x1x1x4xsi32, {order = #NHWC, strides = [4, 1, 4, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>) -> !VPUIP.DistributedBuffer<64x1x1x4xsi32, {order = #NHWC, strides = [4, 1, 4, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
  }
  VPURT.Task waits(%0 : !VPURT.Barrier) updates(%1 : !VPURT.Barrier) {
    %18 = VPUIP.NCEClusterTask {is_segmented, kernel_padding = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = #VPUIP.nce_task_type<CONV>} input(%11 : memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 0]>) weights(%5 : memref<64x32x1x1xf16, #NHWC, [@CMX_NN, 0]>) weight_table(%13 : memref<64x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>) parent_input(%10 : !VPUIP.DistributedBuffer<1x32x32x32xf16, {order = #NHWC, strides = [32768, 1, 1024, 32]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 1, 1], uniform_distributed_segments}>) parent_output(%7 : !VPUIP.DistributedBuffer<1x64x32x32xf16, {order = #NHWC, strides = [65536, 1, 2048, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>) outputs(%8 : memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]> variants : {
      DPUTask {inStart = [0, 0, 0], inEnd = [15, 15, 15], outEnd = [31, 15, 63], mpe_mode = #VPU.mpe_mode<CUBOID_16x16>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, outStart = [0, 0, 0]}
    } PPE : {
    }
  }
  VPURT.Task waits(%0 : !VPURT.Barrier) updates(%1 : !VPURT.Barrier) {
    %18 = VPUIP.NCEClusterTask {is_segmented, kernel_padding = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = #VPUIP.nce_task_type<CONV>} input(%12 : memref<1x32x16x32xf16, #NHWC, [@CMX_NN, 1]>) weights(%6 : memref<64x32x1x1xf16, #NHWC, [@CMX_NN, 1]>) weight_table(%14 : memref<64x1x1x4xsi32, #NHWC, [@CMX_NN, 1]>) parent_input(%10 : !VPUIP.DistributedBuffer<1x32x32x32xf16, {order = #NHWC, strides = [32768, 1, 1024, 32]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 1, 1], uniform_distributed_segments}>) parent_output(%7 : !VPUIP.DistributedBuffer<1x64x32x32xf16, {order = #NHWC, strides = [65536, 1, 2048, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>) outputs(%9 : memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 1]>) -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 1]> variants : {
      DPUTask {inStart = [0, 0, 0], inEnd = [15, 15, 15], outEnd = [31, 31, 63], mpe_mode = #VPU.mpe_mode<CUBOID_16x16>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, outStart = [0, 16, 0]}
    } PPE : {
    }
  }
  %16 = VPURT.DeclareBuffer <CMX_NN> [0] <4096> -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]>
  VPURT.Task waits(%1 : !VPURT.Barrier) {
    %18 = VPUIP.NNDMA {port = 0 : i64} inputs(%16 : memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]>) outputs(%arg1 : memref<1x64x16x32xf16, #NHWC, @DDR>) -> memref<1x64x16x32xf16, #NHWC, @DDR>
  }
  %17 = VPURT.DeclareBuffer <CMX_NN> [1] <4096> -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 1]>
  VPURT.Task waits(%1 : !VPURT.Barrier) {
    %18 = VPUIP.NNDMA {port = 0 : i64} inputs(%17 : memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 1]>) outputs(%arg2 : memref<1x64x16x32xf16, #NHWC, @DDR>) -> memref<1x64x16x32xf16, #NHWC, @DDR>
  }
  return %arg1, %arg2 : memref<1x64x16x32xf16, #NHWC, @DDR>, memref<1x64x16x32xf16, #NHWC, @DDR>
}
}

//CHECK-LABEL: @multiple_clusters_dpu_soh_f16_f16_f16
//CHECK: %[[CST:.*]] = const.Declare [[TYPE_CST:.*]] = dense
//CHECK-NEXT: %[[CST_0:.*]] = const.Declare [[TYPE_CST0:.*]] = dense
//CHECK-NEXT: %[[VAL2:.*]] = VPURT.DeclareBuffer <NetworkInput> [0] <0> -> [[TYPE2:.*]]
//CHECK-NEXT: %[[VAL3:.*]] = VPURT.DeclareBuffer <NetworkInput> [0] <32768> -> [[TYPE3:.*]]
//CHECK-NEXT: %[[VAL4:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <0> -> !VPUIP.DistributedBuffer<64x32x1x1xf16, {order = #NHWC, strides = [32, 1, 32, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
//CHECK-NEXT: %[[VAL5:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> [[TYPE5:.*]]
//CHECK-NEXT: %[[VAL6:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <0> -> [[TYPE6:.*]]
//CHECK-NEXT: %[[VAL7:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <4096> -> [[TYPE7:.*]]
//CHECK-NEXT: %[[VAL8:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <4096> -> [[TYPE8:.*]]
//CHECK-NEXT: %[[VAL9:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <4096> -> [[TYPE9:.*]]
//CHECK-NEXT: %[[VAL10:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <69632> -> [[TYPE10:.*]]
//CHECK-NEXT: %[[VAL11:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <69632> -> [[TYPE11:.*]]
//CHECK-NEXT: %[[VAL12:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <69632> -> [[TYPE12:.*]]
//CHECK-NEXT: %[[VAL13:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <102400> -> [[TYPE13:.*]]
//CHECK-NEXT: %[[VAL14:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <102400> -> [[TYPE14:.*]]
//CHECK-NEXT: %[[VAL15:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <102400> -> [[TYPE15:.*]]
//CHECK-NEXT: %[[VAL16:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> [[TYPE16:.*]]
//CHECK-NEXT: %[[VAL17:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <0> -> [[TYPE17:.*]]
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[CST]] : [[TYPE_CST]]) outputs(%[[VAL16]], %[[VAL17]] : [[TYPE16]], [[TYPE17]])
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[VAL2]] : [[TYPE2]]) outputs(%[[VAL11]] : [[TYPE11]])
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[VAL3]] : [[TYPE3]]) outputs(%[[VAL12]] : [[TYPE12]])
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: %[[VAL21:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <102400> -> [[TYPE21:.*]]
//CHECK-NEXT: %[[VAL22:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <102400> -> [[TYPE22:.*]]
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[CST_0]] : [[TYPE_CST0]]) outputs(%[[VAL21]], %[[VAL22]] : [[TYPE21]], [[TYPE22]])
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.DPUInvariant
                //CHECK-DAG: input(%[[VAL11]] : [[TYPE11]])
                //CHECK-DAG: weights(%[[VAL5]] : [[TYPE5]])
                //CHECK-DAG: weight_table(%[[VAL13]] : [[TYPE13]])
                //CHECK-DAG: outputs(%[[VAL8]] : [[TYPE8]])
//CHECK-NOT: DPUTask
//CHECK: VPUMI40XX.DPUVariant
//CHECK-NEXT: VPUMI40XX.DPUInvariant
                //CHECK-DAG: input(%[[VAL12]] : [[TYPE12]])
                //CHECK-DAG: weights(%[[VAL6]] : [[TYPE6]])
                //CHECK-DAG: weight_table(%[[VAL14]] : [[TYPE14]])
                //CHECK-DAG: outputs(%[[VAL9]] : [[TYPE9]])
//CHECK-NOT: DPUTask
//CHECK: VPUMI40XX.DPUVariant

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
module @mainModule {
  IE.CNNNetwork entryPoint : @multiple_clusters_dpu_sok_f16_f16_f16 inputsInfo : {
    DataInfo "input_0" : tensor<1x32x16x16xf16>
  } outputsInfo : {
    DataInfo "output_0" : tensor<1x64x16x16xf16>
    DataInfo "output_1" : tensor<1x64x16x16xf16>
  }

  func.func private @multiple_clusters_dpu_sok_f16_f16_f16(%arg0: memref<1x32x16x16xf16, #NHWC, @DDR>, %arg1: memref<1x64x16x16xf16, #NHWC, @DDR>, %arg2: memref<1x64x16x16xf16, #NHWC, @DDR>) -> (memref<1x64x16x16xf16, #NHWC, @DDR>, memref<1x64x16x16xf16, #NHWC, @DDR>) {
    %0 = VPURT.ConfigureBarrier<0> -> !VPURT.Barrier
    %12 = VPURT.ConfigureBarrier<1> -> !VPURT.Barrier

    %cst = const.Declare memref<32x32x1x1xf16, #NHWC, @DDR> = dense<1.0> : tensor<64x32x1x1xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [32, 32, 1, 1]>]
    %cst_0 = const.Declare memref<32x32x1x1xf16, #NHWC, @DDR> = dense<1.0> : tensor<64x32x1x1xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [32, 32, 1, 1]>]
    %cst_1 = const.Declare memref<32x1x1x4xsi32, #NHWC, @DDR> = dense<1> : tensor<32x1x1x4xsi32>, [#const.Reorder<#NHWC>]
    %cst_2 = const.Declare memref<32x1x1x4xsi32, #NHWC, @DDR> = dense<1> : tensor<32x1x1x4xsi32>, [#const.Reorder<#NHWC>]

    %1 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <0> -> !VPUIP.DistributedBuffer<64x32x1x1xf16, {order = #NHWC, strides = [32, 1, 32, 32]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [2, 1, 1, 1], num_clusters = 2 : i64, alignment = [16, 1, 1, 1], uniform_distributed_segments}>
    %2 = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 0]>
    %3 = VPURT.DeclareBuffer <CMX_NN> [1] <0> -> memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 1]>
    %4 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <2048> -> !VPUIP.DistributedBuffer<1x64x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1], uniform_distributed_segments}>
    %5 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <2048> -> !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
    %6 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <2048> -> !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
    %7 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <34816> -> !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [8192, 1, 512, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
    %8 = VPURT.DeclareBuffer <CMX_NN> [0] <34816> -> memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>
    %9 = VPURT.DeclareBuffer <CMX_NN> [1] <34816> -> memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 1]>
    %10 = VPURT.DeclareBuffer <CMX_NN> [0] <51200> -> memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>
    %11 = VPURT.DeclareBuffer <CMX_NN> [1] <51200> -> memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 1]>
    %13 = VPURT.DeclareBuffer <CMX_NN> [0] <2048> -> memref<1x64x16x16xf16, #NHWC, [@CMX_NN, 0]>
    %14 = VPURT.DeclareBuffer <CMX_NN> [1] <2048> -> memref<1x64x16x16xf16, #NHWC, [@CMX_NN, 1]>

    VPURT.Task updates(%0 : !VPURT.Barrier) {
      %15 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst : memref<32x32x1x1xf16, #NHWC, @DDR>) outputs(%2 : memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 0]>) -> memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 0]>
    }
    VPURT.Task updates(%0 : !VPURT.Barrier) {
      %15 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_0 : memref<32x32x1x1xf16, #NHWC, @DDR>) outputs(%3 : memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 1]>) -> memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 1]>
    }
    VPURT.Task updates(%0 : !VPURT.Barrier) {
      %15 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_1 : memref<32x1x1x4xsi32, #NHWC, @DDR>) outputs(%10 : memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>) -> memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>
    }
    VPURT.Task updates(%0 : !VPURT.Barrier) {
      %15 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_2 : memref<32x1x1x4xsi32, #NHWC, @DDR>) outputs(%11 : memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 1]>) -> memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 1]>
    }
    VPURT.Task updates(%0 : !VPURT.Barrier) {
      %15 = VPUIP.NNDMA {port = 0 : i64} inputs(%arg0 : memref<1x32x16x16xf16, #NHWC, @DDR>) outputs(%7 : !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [8192, 1, 512, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>) -> !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [8192, 1, 512, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>
    }
    VPURT.Task waits(%0 : !VPURT.Barrier) updates(%12 : !VPURT.Barrier) {
      %15 = VPUIP.NCEClusterTask {kernel_padding = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = #VPUIP.nce_task_type<CONV>} input(%8 : memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>) weights(%2 : memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 0]>) weight_table(%10 : memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>) parent_input(%7 : !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [8192, 1, 512, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>) parent_output(%4 : !VPUIP.DistributedBuffer<1x64x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1], uniform_distributed_segments}>) outputs(%5 : !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>) -> !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}> variants : {
        DPUTask {inStart = [0, 0, 0], inEnd = [15, 15, 15], outEnd = [15, 15, 31], mpe_mode = #VPU.mpe_mode<CUBOID_16x16>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, outStart = [0, 0, 0]}
      } PPE : {
      }
    }
    VPURT.Task waits(%0 : !VPURT.Barrier) updates(%12 : !VPURT.Barrier) {
      %15 = VPUIP.NCEClusterTask {kernel_padding = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = #VPUIP.nce_task_type<CONV>} input(%9 : memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 1]>) weights(%3 : memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 1]>) weight_table(%11 : memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 1]>) parent_input(%7 : !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [8192, 1, 512, 32]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>) parent_output(%4 : !VPUIP.DistributedBuffer<1x64x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1], uniform_distributed_segments}>) outputs(%6 : !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}>) -> !VPUIP.DistributedBuffer<1x32x16x16xf16, {order = #NHWC, strides = [16384, 1, 1024, 64]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, uniform_distributed_segments}> variants : {
        DPUTask {inStart = [0, 0, 0], inEnd = [15, 15, 15], outEnd = [15, 15, 63], mpe_mode = #VPU.mpe_mode<CUBOID_16x16>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, outStart = [0, 0, 32]}
      } PPE : {
      }
    }
    VPURT.Task waits(%12 : !VPURT.Barrier) {
      %15 = VPUIP.NNDMA {port = 0 : i64} inputs(%13 : memref<1x64x16x16xf16, #NHWC, [@CMX_NN, 0]>) outputs(%arg1 : memref<1x64x16x16xf16, #NHWC, @DDR>) -> memref<1x64x16x16xf16, #NHWC, @DDR>
    }
    VPURT.Task waits(%12 : !VPURT.Barrier) {
      %15 = VPUIP.NNDMA {port = 0 : i64} inputs(%14 : memref<1x64x16x16xf16, #NHWC, [@CMX_NN, 1]>) outputs(%arg2 : memref<1x64x16x16xf16, #NHWC, @DDR>) -> memref<1x64x16x16xf16, #NHWC, @DDR>
    }
    return %arg1, %arg2 : memref<1x64x16x16xf16, #NHWC, @DDR>, memref<1x64x16x16xf16, #NHWC, @DDR>
  }
}

//CHECK-LABEL: @multiple_clusters_dpu_sok_f16_f16_f16

//CHECK: %[[VALCST:.*]] = const.Declare [[TYPECST:.*]] = dense
//CHECK-NEXT: %[[VALCST0:.*]] = const.Declare [[TYPECST0:.*]] = dense
//CHECK-NEXT: %[[VALCST1:.*]] = const.Declare [[TYPECST1:.*]] = dense
//CHECK-NEXT: %[[VALCST2:.*]] = const.Declare [[TYPECST2:.*]] = dense
//CHECK-NEXT: %[[VAL1:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <0> -> [[TYPE1:.*]]
//CHECK-NEXT: %[[VAL2:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> [[TYPE2:.*]]
//CHECK-NEXT: %[[VAL3:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <0> -> [[TYPE3:.*]]
//CHECK-NEXT: %[[VAL4:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <2048> -> [[TYPE4:.*]]
//CHECK-NEXT: %[[VAL5:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <2048> -> [[TYPE5:.*]]
//CHECK-NEXT: %[[VAL6:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <2048> -> [[TYPE6:.*]]
//CHECK-NEXT: %[[VAL7:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <34816> -> [[TYPE7:.*]]
//CHECK-NEXT: %[[VAL8:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <34816> -> [[TYPE8:.*]]
//CHECK-NEXT: %[[VAL9:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <34816> -> [[TYPE9:.*]]
//CHECK-NEXT: %[[VAL10:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <51200> -> [[TYPE10:.*]]
//CHECK-NEXT: %[[VAL11:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <51200> -> [[TYPE11:.*]]
//CHECK-NEXT: %[[VAL13:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <2048> -> [[TYPE13:.*]]
//CHECK-NEXT: %[[VAL14:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <2048> -> [[TYPE14:.*]]

//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[VALCST]] : [[TYPECST]]) outputs(%[[VAL2]] : [[TYPE2]])
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[VALCST0]] : [[TYPECST0]]) outputs(%[[VAL3]] : [[TYPE3]])
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[VALCST1]] : [[TYPECST1]]) outputs(%[[VAL10]] : [[TYPE10]])
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%[[VALCST2]] : [[TYPECST2]]) outputs(%[[VAL11]] : [[TYPE11]])
//CHECK-NEXT: %[[VAL19:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <34816> -> [[TYPE19:.*]]
//CHECK-NEXT: %[[VAL20:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <34816> -> [[TYPE20:.*]]
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.NNDMA{{.*}}inputs(%arg0 : memref<1x32x16x16xf16, #NHWC, @DDR>) outputs(%[[VAL19]], %[[VAL20]] : [[TYPE19]], [[TYPE20]])

//CHECK-NEXT: %[[VAL22:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <2048> -> [[TYPE22:.*]]
//CHECK-NEXT: %[[VAL23:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <2048> -> [[TYPE23:.*]]
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.DPUInvariant
                //CHECK-DAG: input(%[[VAL8]] : [[TYPE8]])
                //CHECK-DAG: weights(%[[VAL2]] : [[TYPE2]])
                //CHECK-DAG: weight_table(%[[VAL10]] : [[TYPE10]])
                //CHECK-DAG: outputs(%[[VAL22]], %[[VAL23]] : [[TYPE22]], [[TYPE23]])
//CHECK-NOT: DPUTask
//CHECK: VPUMI40XX.DPUVariant

//CHECK-NEXT: %[[VAL26:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <2048> -> [[TYPE26:.*]]
//CHECK-NEXT: %[[VAL27:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <2048> -> [[TYPE27:.*]]
//CHECK-NOT: VPURT.Task
//CHECK-NEXT: VPUMI40XX.DPUInvariant
                //CHECK-DAG: input(%[[VAL9]] : [[TYPE9]])
                //CHECK-DAG: weights(%[[VAL3]] : [[TYPE3]])
                //CHECK-DAG: weight_table(%[[VAL11]] : [[TYPE11]])
                //CHECK-DAG: outputs(%[[VAL26]], %[[VAL27]] : [[TYPE26]], [[TYPE27]])
//CHECK-NOT: DPUTask
//CHECK: VPUMI40XX.DPUVariant

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
module @mainModule {
  func.func private @sparse_conv(%arg0: memref<1x128x32x32xf16, #NHWC, @DDR>, %arg1: memref<1x32x32x32xf16, #NHWC, @DDR>) -> memref<1x32x32x32xf16, #NHWC, @DDR> {

    %cst = const.Declare memref<512x1x1x1xui8, #NHWC, @DDR> = dense<1.0> : tensor<32x128x1x1xf16>, [#const.Reorder<#NHWC>, #const.Sparsify<true, dense<1> : tensor<32xi64>>]
    %cst_0 = const.Declare memref<32x1x1x128xi1, @DDR> = dense<1.0> : tensor<32x128x1x1xf16>, [#const.Reorder<#NHWC>, #const.GetSparsityMap]
    %cst_1 = const.Declare memref<32x1x1x4xsi32, #NHWC, @DDR> = dense<1> : tensor<32x1x1x4xsi32>, [#const.Reorder<#NHWC>]

    %0 = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<512x1x1x1xui8, #NHWC, [@CMX_NN, 0]>
    %1 = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<32x1x1x1xf16, #NHWC, [@CMX_NN, 0]>
    %2 = VPURT.DeclareBuffer <CMX_NN> [0] <73728> -> memref<1x128x32x32xf16, #NHWC, [@CMX_NN, 0]>
    %3 = VPURT.DeclareBuffer <CMX_NN> [0] <335872> -> memref<32x1x1x128xi1, [@CMX_NN, 0]>
    %4 = VPURT.DeclareBuffer <CMX_NN> [0] <8192> -> memref<1x32x32x32xf16, #NHWC, [@CMX_NN, 0]>
    %5 = VPURT.DeclareBuffer <CMX_NN> [0] <336384> -> memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>
    %6 = VPURT.ConfigureBarrier<0> -> !VPURT.Barrier
    VPURT.Task updates(%6 : !VPURT.Barrier) {
      %8 = VPUIP.NNDMA {port = 0 : i64} inputs(%arg0 : memref<1x128x32x32xf16, #NHWC, @DDR>) outputs(%2 : memref<1x128x32x32xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x128x32x32xf16, #NHWC, [@CMX_NN, 0]>
    }
    VPURT.Task updates(%6 : !VPURT.Barrier) {
      %8 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst : memref<512x1x1x1xui8, #NHWC, @DDR>) outputs(%0 : memref<512x1x1x1xui8, #NHWC, [@CMX_NN, 0]>) -> memref<512x1x1x1xui8, #NHWC, [@CMX_NN, 0]>
    }
    VPURT.Task updates(%6 : !VPURT.Barrier) {
      %8 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_1 : memref<32x1x1x4xsi32, #NHWC, @DDR>) outputs(%5 : memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>) -> memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>
    }
    VPURT.Task updates(%6 : !VPURT.Barrier) {
      %8 = VPUIP.NNDMA {port = 0 : i64} inputs(%cst_0 : memref<32x1x1x128xi1, @DDR>) outputs(%3 : memref<32x1x1x128xi1, [@CMX_NN, 0]>) -> memref<32x1x1x128xi1, [@CMX_NN, 0]>
    }
    %7 = VPURT.ConfigureBarrier<1> -> !VPURT.Barrier
    VPURT.Task waits(%6 : !VPURT.Barrier) updates(%7 : !VPURT.Barrier) {
      %8 = VPUIP.NCEClusterTask {kernel_padding = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = #VPUIP.nce_task_type<CONV>} input(%2 : memref<1x128x32x32xf16, #NHWC, [@CMX_NN, 0]>) weights(%1 : memref<32x1x1x1xf16, #NHWC, [@CMX_NN, 0]>) weights_sparsity_map(%3 : memref<32x1x1x128xi1, [@CMX_NN, 0]>) weight_table(%5 : memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>) parent_input(%2 : memref<1x128x32x32xf16, #NHWC, [@CMX_NN, 0]>) parent_output(%4 : memref<1x32x32x32xf16, #NHWC, [@CMX_NN, 0]>) outputs(%4 : memref<1x32x32x32xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x32x32x32xf16, #NHWC, [@CMX_NN, 0]> variants : {
        DPUTask {inStart = [0, 0, 0], inEnd = [15, 15, 15], outEnd = [31, 31, 31], mpe_mode = #VPU.mpe_mode<CUBOID_16x16>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, outStart = [0, 0, 0]}
      } PPE : {
      }
    }
    VPURT.Task waits(%7 : !VPURT.Barrier) {
      %8 = VPUIP.NNDMA {port = 0 : i64} inputs(%4 : memref<1x32x32x32xf16, #NHWC, [@CMX_NN, 0]>) outputs(%arg1 : memref<1x32x32x32xf16, #NHWC, @DDR>) -> memref<1x32x32x32xf16, #NHWC, @DDR>
    }
    return %arg1 : memref<1x32x32x32xf16, #NHWC, @DDR>
  }
  IE.CNNNetwork entryPoint : @sparse_conv inputsInfo : {
    DataInfo "input_0" : tensor<1x128x32x32xf16>
  } outputsInfo : {
    DataInfo "output_0" : tensor<1x32x32x32xf16>
  }
}

//CHECK-LABEL: @sparse_conv
//CHECK: %[[VALCST:.*]] = const.Declare memref<32x1x1x128xi1, @DDR> = dense
//CHECK: %[[VALSPS:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <335872> -> memref<32x1x1x128xi1, [@CMX_NN, 0]>
//CHECK: VPUMI40XX.NNDMA{{.*}}inputs(%[[VALCST]] : memref<32x1x1x128xi1, @DDR>) outputs(%[[VALSPS]] : memref<32x1x1x128xi1, [@CMX_NN, 0]>)
//CHECK: VPUMI40XX.DPUInvariant
//CHECK-SAME: weights_sparsity_map(%[[VALSPS]] : memref<32x1x1x128xi1, [@CMX_NN, 0]>)

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
module @mainModule {

  IE.CNNNetwork entryPoint : @se_table_dpu_f16_f16_f16 inputsInfo : {
    DataInfo "input_0" : tensor<1x32x16x16xf16>
  } outputsInfo : {
    DataInfo "output_0" : tensor<1x32x16x16xf16>
  }

  func.func private @se_table_dpu_f16_f16_f16(%arg0: memref<1x32x16x16xf16, #NHWC, @DDR>, %arg1: memref<1x32x16x16xf16, #NHWC, @DDR>) -> memref<1x32x16x16xf16, #NHWC, @DDR> {
    %0 = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 0]>
    %1 = VPURT.DeclareBuffer <CMX_NN> [0] <18432> -> memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>
    %2 = VPURT.DeclareBuffer <CMX_NN> [0] <36352> -> memref<1x32x16x16xi1, [@CMX_NN, 0]>
    %3 = VPURT.DeclareBuffer <CMX_NN> [0] <35328> -> memref<1x1x16x16xi32, #NHWC, [@CMX_NN, 0]>
    %4 = VPURT.DeclareBuffer <CMX_NN> [0] <34816> -> memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>
    %5 = VPURT.DeclareBuffer <CMX_NN> [0] <2048> -> memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>
    VPURT.Task {
      %6 = VPUIP.NCEClusterTask {kernel_padding = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = #VPUIP.nce_task_type<CONV>} input(%1 : memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>) input_sparsity_map(%2 : memref<1x32x16x16xi1, [@CMX_NN, 0]>) input_storage_element_table(%3 : memref<1x1x16x16xi32, #NHWC, [@CMX_NN, 0]>) weights(%0 : memref<32x32x1x1xf16, #NHWC, [@CMX_NN, 0]>) weight_table(%4 : memref<32x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>) parent_input(%1 : memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>) parent_input_sparsity_map(%2 : memref<1x32x16x16xi1, [@CMX_NN, 0]>) parent_input_storage_element_table(%3 : memref<1x1x16x16xi32, #NHWC, [@CMX_NN, 0]>) parent_output(%5 : memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>) outputs(%5 : memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x32x16x16xf16, #NHWC, [@CMX_NN, 0]> variants : {
        DPUTask {inEnd = [15, 15, 31], inStart = [0, 0, 0], mpe_mode = #VPU.mpe_mode<CUBOID_16x16>, outEnd = [15, 15, 31], outStart = [0, 0, 0], pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>}
      } PPE : {
      }
    }
    return %arg1 : memref<1x32x16x16xf16, #NHWC, @DDR>
  }
}

//CHECK-LABEL: @se_table_dpu_f16_f16_f16
//CHECK: %[[VALSMP:.*]] = VPURT.DeclareBuffer <CMX_NN> {{.*}} -> memref<1x32x16x16xi1
//CHECK: %[[VALSET:.*]] = VPURT.DeclareBuffer <CMX_NN> {{.*}} -> memref<1x1x16x16xi32
//CHECK: VPUMI40XX.DPUInvariant
//CHECK-SAME: input_sparsity_map(%[[VALSMP]] : memref<1x32x16x16xi1
//CHECK-SAME: input_storage_element_table(%[[VALSET]] : memref<1x1x16x16xi32
//CHECK: VPUMI40XX.DPUVariant
//CHECK-NOT: lut_read

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!InputITI1 = !VPUIP.ITIBuffer<1x16x18x32xf16, {order = #NHWC, swizzlingScheme = #VPUIP.SwizzlingSchemeAttr<key = 5 : i64, sizeAlignment = 512 : i64>}, [@CMX_NN, 0],inwardHaloRegions = [], outwardHaloRegions = []>

module @TestDMLConvertITIBuffer {
IE.CNNNetwork entryPoint : @convert_iti_buffer inputsInfo : {
        DataInfo "input0" : tensor<1x16x18x32xf16>
    }
    outputsInfo : {
        DataInfo "output0" : tensor<1x16x18x32xf16>
    }
    func.func @convert_iti_buffer(%arg0: memref<1x16x18x32xf16, #NHWC, @DDR>, %arg1:  memref<1x16x18x32xf16, #NHWC, @DDR>) -> memref<1x16x18x32xf16, #NHWC, @DDR> {

        %cst = const.Declare memref<1x16x18x32xf16, #NHWC, @DDR> = dense<1.000> : tensor<1x16x18x32xf16>, [#const.Reorder<#NHWC>]
        %0 = VPURT.DeclareBuffer <CMX_NN> [0] <0> {DescriptorHandle = 5555 : ui64} -> !InputITI1
        %1 = VPURT.DeclareBuffer <CMX_NN> [0] <336384> -> memref<1x16x18x32xf16, #NHWC, [@CMX_NN, 0]>

        VPURT.Task {
            VPUIP.NNDMA {port = 0 : i64} inputs(%0: !InputITI1) outputs(%1 : memref<1x16x18x32xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x16x18x32xf16, #NHWC, [@CMX_NN, 0]>
        }
        return %arg1:  memref<1x16x18x32xf16, #NHWC, @DDR>
    }
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
module @TestDMLExtractFromDistributedBuffer {

IE.CNNNetwork entryPoint : @extract_from_distributed_buffer inputsInfo : {
    DataInfo "input_0" : tensor<1x32x32x32xf16>
  }
  outputsInfo : {
    DataInfo "output_0" : tensor<1x64x16x32xf16>
  }

func.func private @extract_from_distributed_buffer(%arg0: memref<1x32x32x32xf16, #NHWC, @DDR>, %arg1: memref<1x64x16x32xf16, #NHWC, @DDR>) -> (memref<1x64x16x32xf16, #NHWC, @DDR>) {
    %0 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <69632> {DescriptorHandle = 10 : ui64} -> !VPUIP.DistributedBuffer<1x32x32x32xf16, {order = #NHWC, strides = [32768, 1, 1024, 32]}, @CMX_NN, {mode = "DUPLICATED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 1, 1], uniform_distributed_segments}>
    %1 = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<64x32x1x1xf16, #NHWC, [@CMX_NN, 0]>
    %2 = VPURT.DeclareBuffer <CMX_NN> [0] <102400> -> memref<64x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>
    %3 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <4096> -> !VPUIP.DistributedBuffer<1x64x32x32xf16, {order = #NHWC, strides = [65536, 1, 2048, 64]}, @CMX_NN, {mode = "DUPLICATED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>
    %4 = VPURT.DeclareBuffer <CMX_NN> [0] <4096> -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]>

    VPURT.Task {
      VPUIP.NCEClusterTask { kernel_padding = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, kernel_size = [1, 1], kernel_strides = [1, 1], task_type = #VPUIP.nce_task_type<CONV>}
      input(%0 : !VPUIP.DistributedBuffer<1x32x32x32xf16, {order = #NHWC, strides = [32768, 1, 1024, 32]}, @CMX_NN, {mode = "DUPLICATED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 1, 1], uniform_distributed_segments}>) weights(%1 : memref<64x32x1x1xf16, #NHWC, [@CMX_NN, 0]>) weight_table(%2 : memref<64x1x1x4xsi32, #NHWC, [@CMX_NN, 0]>)
      parent_input(%0 : !VPUIP.DistributedBuffer<1x32x32x32xf16, {order = #NHWC, strides = [32768, 1, 1024, 32]}, @CMX_NN, {mode = "DUPLICATED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 1, 1], uniform_distributed_segments}>) parent_output(%3 : !VPUIP.DistributedBuffer<1x64x32x32xf16, {order = #NHWC, strides = [65536, 1, 2048, 64]}, @CMX_NN, {mode = "DUPLICATED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>) outputs(%4 : memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]>) -> memref<1x64x16x32xf16, #NHWC, [@CMX_NN, 0]> variants : {
        DPUTask {inStart = [0, 0, 0], inEnd = [15, 15, 15], outEnd = [31, 15, 63], mpe_mode = #VPU.mpe_mode<CUBOID_16x16>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, outStart = [0, 0, 0]}
      } PPE : {
      }
    }
    return %arg1 : memref<1x64x16x32xf16, #NHWC, @DDR>
}
}
