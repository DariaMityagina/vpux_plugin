//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=VPUX37XX compilation-mode=DefaultHW" --tile-act-shave-kernel-task --canonicalize %s | FileCheck %s

// -----

#NWHC = affine_map<(d0, d1, d2, d3) -> (d0, d3, d2, d1)>

module @VPU.SW {
  func.func private @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterStridedMVN(%arg0: memref<1x128x64x32xf16, #NWHC>)
        -> memref<1x128x64x32xf16, #NWHC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, #NWHC>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> memref<1x128x64x32xf16, #NWHC, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NWHC, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x128x64x32xf16, #NWHC, @CMX_NN>, memref<1x128x64x32xf16, #NWHC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16, #NWHC>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC>
    }
    return %6: memref<1x128x64x32xf16, #NWHC>


    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, #NWHC>) outputs([[INPUT_CMX]] as %arg2: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> memref<1x128x64x32xf16, #NWHC, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 64, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 64, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[MVN:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>) {
    // CHECK{LITERAL}:      %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg5: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, %arg2 as %arg6: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, %arg4 as %arg8: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) strides([[262144, 1, 128, 8192], [262144, 1, 128, 8192]]) on tile 0 -> (memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>){
    // CHECK:        VPUIP.SW.Kernel.run {attrs  = [false, true, 6.0892105102539063E-4]}(%arg5, %arg7) : memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg6, %arg8) : memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[MVN]]#0, [[MVN]]#1 : !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>) outputs(%4 : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16, #NWHC>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x128x64x32xf16, #NWHC>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileNoSymmetricClusterStridedMVN(%arg0: memref<1x33x16x1xf16>)
        -> memref<1x33x16x1xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x33x16x1xf16>) outputs(%0 as %arg2: memref<1x33x16x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16>) outputs(%arg2 : memref<1x33x16x1xf16, @CMX_NN>) -> memref<1x33x16x1xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x33x16x1xf16, @CMX_NN>) outputs(%3 as %arg2: memref<1x33x16x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x33x16x1xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x33x16x1xf16, @CMX_NN>) on tile 0 -> memref<1x33x16x1xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x33x16x1xf16, @CMX_NN>, memref<1x33x16x1xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x33x16x1xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x33x16x1xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, @CMX_NN>) outputs(%arg2 : memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16>
    }
    return %6: memref<1x33x16x1xf16>


    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x33x16x1xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x33x16x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16>) outputs(%arg2 : memref<1x33x16x1xf16, @CMX_NN>) -> memref<1x33x16x1xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 16, 0, 0] [1, 17, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 16, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 16, 0, 0] [1, 17, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 16, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MVN:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) {
    // CHECK{LITERAL}:      results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg5: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, %arg2 as %arg6: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, %arg4 as %arg8: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) strides([[272, 16, 1, 1], [256, 16, 1, 1]]) on tile 0 -> (memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>){
    // CHECK:                          VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg5, %arg7) : memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>
    // CHECK:                          VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg6, %arg8) : memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>
    // CHECK:               }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]]  = VPUIP.ConcatView inputs([[MVN]]#0, [[MVN]]#1 : !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) outputs(%4 : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x33x16x1xf16>
    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x33x16x1xf16, @CMX_NN>) outputs([[OUTPUT_DDR]] as %arg2: memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16> {
    // CHECK:                          VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, @CMX_NN>) outputs(%arg2 : memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16>
    // CHECK:    }
    // CHECK:    return [[COPY1]] : memref<1x33x16x1xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileClusterMVNForUnalignedShape(%arg0: memref<1x32x1x10240xf16>)
        -> memref<1x32x1x10240xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x32x1x10240xf16>) outputs(%0 as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16>) outputs(%arg2 : memref<1x32x1x10240xf16, @CMX_NN>) -> memref<1x32x1x10240xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%3 as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x32x1x10240xf16, @CMX_NN>) on tile 0 -> memref<1x32x1x10240xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x32x1x10240xf16, @CMX_NN>, memref<1x32x1x10240xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x32x1x10240xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 : memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16>
    }
    return %6: memref<1x32x1x10240xf16>

    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x32x1x10240xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16>) outputs(%arg2 : memref<1x32x1x10240xf16, @CMX_NN>) -> memref<1x32x1x10240xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
    // CHECK:    [[MVN:%.*]] = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs([[OUTPUT_CMX]] as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
    // CHECK:      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x32x1x10240xf16, @CMX_NN>) on tile 0 -> memref<1x32x1x10240xf16, @CMX_NN>{
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x32x1x10240xf16, @CMX_NN>, memref<1x32x1x10240xf16, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x32x1x10240xf16>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[MVN]] as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 : memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x32x1x10240xf16>
}

// -----

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterHalfPixelInterpolate(%arg0: memref<1x1x96x160xf16>) -> memref<1x1x192x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x1x96x160xf16>) outputs(%0 as %arg3: memref<1x1x96x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x96x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x96x160xf16>) outputs(%arg3 : memref<1x1x96x160xf16, @CMX_NN>) -> memref<1x1x96x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x192x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x1x96x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x192x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x192x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x1x96x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x1x192x320xf16, @CMX_NN>) on tile 0 -> memref<1x1x192x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x1x96x160xf16, @CMX_NN>, memref<1x1x192x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x1x192x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x1x192x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x192x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    }
    return %5 : memref<1x1x192x320xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 47, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHEKC-SAME{LIERAL}:     !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}>
    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_INTERPOLATE:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY1]] as %arg1: memref<1x1x49x160xf16, @CMX_NN>, [[COPY0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x1x96x320xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x1x96x320xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg5: memref<1x1x49x160xf16, @CMX_NN>, %arg2 as %arg6: memref<1x1x49x160xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x1x96x320xf16, @CMX_NN>, %arg4 as %arg8: memref<1x1x96x320xf16, @CMX_NN>) on tile 0 -> (memref<1x1x96x320xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg5, %arg7) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 47, 0, 0], [0, 96, 0, 0]]}(%arg6, %arg8) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x1x192x320xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#0 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 96, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY3:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#1 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY2]], [[COPY3]] : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>, memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    // CHECK:    return [[CONCAT]] : memref<1x1x192x320xf16>
}

// -----

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterAlignCornersInterpolate(%arg0: memref<1x1x96x160xf16>) -> memref<1x1x192x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x1x96x160xf16>) outputs(%0 as %arg3: memref<1x1x96x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x96x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x96x160xf16>) outputs(%arg3 : memref<1x1x96x160xf16, @CMX_NN>) -> memref<1x1x96x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x192x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x1x96x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x192x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x192x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x1x96x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x1x192x320xf16, @CMX_NN>) on tile 0 -> memref<1x1x192x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 4, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x1x96x160xf16, @CMX_NN>, memref<1x1x192x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x1x192x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x1x192x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x192x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    }
    return %5 : memref<1x1x192x320xf16>


    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 47, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHEKC-SAME{LIERAL}:     !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}>
    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_INTERPOLATE:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY4]] as %arg1: memref<1x1x49x160xf16, @CMX_NN>, [[COPY2]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x1x96x320xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x1x96x320xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg5: memref<1x1x49x160xf16, @CMX_NN>, %arg2 as %arg6: memref<1x1x49x160xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x1x96x320xf16, @CMX_NN>, %arg4 as %arg8: memref<1x1x96x320xf16, @CMX_NN>) on tile 0 -> (memref<1x1x96x320xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 4, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg5, %arg7) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 4, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 47, 0, 0], [0, 96, 0, 0]]}(%arg6, %arg8) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x1x192x320xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#0 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 96, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#1 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>, memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    // CHECK:    return [[CONCAT]] : memref<1x1x192x320xf16>
}

// -----

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterPytorchHalfPixelInterpolate(%arg0: memref<1x1x96x160xf16>) -> memref<1x1x192x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x1x96x160xf16>) outputs(%0 as %arg3: memref<1x1x96x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x96x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x96x160xf16>) outputs(%arg3 : memref<1x1x96x160xf16, @CMX_NN>) -> memref<1x1x96x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x192x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // LINEAR_ONNX = 2, PYTORCH_HALF_PIXEL = 1
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x1x96x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x192x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x192x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x1x96x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x1x192x320xf16, @CMX_NN>) on tile 0 -> memref<1x1x192x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 1, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x1x96x160xf16, @CMX_NN>, memref<1x1x192x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x1x192x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x1x192x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x192x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    }
    return %5 : memref<1x1x192x320xf16>

    // CHECK:    [[INPUT_SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 47, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUFF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{Literal}:            !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}>
    // CHECK:    [[INPUT_COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW1]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUFF1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) ->
    // CHECK-SAME{Literal}:            !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}> {
    // CHECK:                                   VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[INPUT_SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUFF0:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{Literal}:             !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}>
    // CHECK:    [[INPUT_COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW0]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUFF0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) ->
    // CHECK-SAME{Literal}:             !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}> {
    // CHECK:                                   VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUFF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUFF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INTERP:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[INPUT_COPY0]] as %arg1: memref<1x1x49x160xf16, @CMX_NN>, [[INPUT_COPY1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) outputs([[OUTPUT_BUFF0]] as %arg3: memref<1x1x96x320xf16, @CMX_NN>, [[OUTPUT_BUFF1]] as %arg4: memref<1x1x96x320xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                                   %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg5: memref<1x1x49x160xf16, @CMX_NN>, %arg2 as %arg6: memref<1x1x49x160xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x1x96x320xf16, @CMX_NN>, %arg4 as %arg8: memref<1x1x96x320xf16, @CMX_NN>) on tile 0 -> (memref<1x1x96x320xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>){
    // CHECK:                                         VPUIP.SW.Kernel.run {attrs = [2, 1, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg5, %arg7) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                                         VPUIP.SW.Kernel.run {attrs = [2, 1, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 47, 0, 0], [0, 96, 0, 0]]}(%arg6, %arg8) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUFF:%.*]] = memref.alloc() : memref<1x1x192x320xf16>
    // CHECK:    [[OUTPUT_SUBVIEW0:%.*]] = VPUIP.SubView [[OUTPUT_BUFF]] [0, 0, 0, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[OUTPUT_COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[INTERP]]#0 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW0]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:                                    VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[OUTPUT_SUBVIEW1:%.*]] = VPUIP.SubView [[OUTPUT_BUFF]] [0, 0, 96, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[OUTPUT_COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[INTERP]]#1 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW1]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:                                     VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[OUTPUT_COPY0]], [[OUTPUT_COPY1]] : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>, memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) outputs(%9 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    // CHECK:    return [[CONCAT:%.*]] : memref<1x1x192x320xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterGelu(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHEKC-SAME{LIERAL}:     !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_GELU:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY4]] as %arg1: memref<1x128x32x32xf16, @CMX_NN>, [[COPY2]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x128x32x32xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x128x32x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg5: memref<1x128x32x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#0 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#1 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterGeluWithCMXInput(%arg0: !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %2 = memref.alloc() : memref<1x128x64x32xf16>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%2 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %4 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %3: memref<1x128x64x32xf16>

    // CHECK:    [[INPUT_DDR1:%.*]] = memref.alloc() : memref<1x128x64x32xf16, @DDR>
    // CHECK:    [[COPYBACK1:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[INPUT_DDR1]] as %arg2: memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPYBACK1]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16, @DDR> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs([[INPUT_BUF1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[INPUT_DDR0:%.*]] = memref.alloc() : memref<1x128x64x32xf16, @DDR>
    // CHECK:    [[COPYBACK0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[INPUT_DDR0]] as %arg2: memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR> {
    // CHECK:                            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPYBACK0]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16, @DDR> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs([[INPUT_BUF0]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                            VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }

    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_GELU:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x128x32x32xf16, @CMX_NN>, [[COPY1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x128x32x32xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x128x32x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg5: memref<1x128x32x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#0 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#1 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterGeluWithdifferentTiles(%arg0: memref<1x128x6x32xf16>)
        -> memref<1x128x6x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x6x32xf16>) outputs(%0 as %arg2: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x6x32xf16>) outputs(%arg2 : memref<1x128x6x32xf16, @CMX_NN>) -> memref<1x128x6x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg6: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x6x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x6x32xf16, @CMX_NN>, memref<1x128x6x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x6x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x6x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x6x32xf16>) -> memref<1x128x6x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x6x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x6x32xf16>) -> memref<1x128x6x32xf16>
    }
    return %6: memref<1x128x6x32xf16>

    // CHECK:     [[INPUT_SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 4, 0] [1, 128, 2, 32] : memref<1x128x6x32xf16> to memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[INPUT_CMX_1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[COPY_INPUT_1:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW1]] as %arg1: memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs([[INPUT_CMX_1]] as %arg2: memref<1x128x2x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs(%arg2 : memref<1x128x2x32xf16, @CMX_NN>) -> memref<1x128x2x32xf16, @CMX_NN>
    // CHECK:     }
    // CHECK:     [[INPUT_SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 128, 4, 32] : memref<1x128x6x32xf16> to memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[INPUT_CMX_0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[COPY_INPUT_0:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW0]] as %arg1: memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs([[INPUT_CMX_0]] as %arg2: memref<1x128x4x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs(%arg2 : memref<1x128x4x32xf16, @CMX_NN>) -> memref<1x128x4x32xf16, @CMX_NN>
    // CHECK:     }
    // CHECK:     [[OUTPUT_CMX_1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[OUTPUT_CMX_0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[GELU:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY_INPUT_0]] as %arg1: memref<1x128x4x32xf16, @CMX_NN>, [[COPY_INPUT_1]] as %arg2: memref<1x128x2x32xf16, @CMX_NN>) outputs([[OUTPUT_CMX_0]] as %arg3: memref<1x128x4x32xf16, @CMX_NN>, [[OUTPUT_CMX_1]] as %arg4: memref<1x128x2x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                           %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg5: memref<1x128x4x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x2x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x4x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x2x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x4x32xf16, @CMX_NN>, memref<1x128x2x32xf16, @CMX_NN>){
    // CHECK:                                 VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x128x4x32xf16, @CMX_NN>, memref<1x128x4x32xf16, @CMX_NN>
    // CHECK:                                 VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x128x2x32xf16, @CMX_NN>, memref<1x128x2x32xf16, @CMX_NN>
    // CHECK:                           }
    // CHECK:     }
    // CHECK:     [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x6x32xf16>
    // CHECK:     [[OUTPUT_SUBVIEW0:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 4, 32] : memref<1x128x6x32xf16> to memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[COPY_OUTPUT_0:%.*]] = VPUIP.NCEClusterTiling inputs([[GELU]]#0 as %arg1: memref<1x128x4x32xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW0]] as %arg2: memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}> {
    // CHECK:                                 VPUIP.Copy inputs(%arg1 : memref<1x128x4x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     }
    // CHECK:     [[OUTPUT_SUBVIEW1:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 4, 0] [1, 128, 2, 32] : memref<1x128x6x32xf16> to memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[COPY_OUTPUT_1:%.*]] = VPUIP.NCEClusterTiling inputs([[GELU]]#1 as %arg1: memref<1x128x2x32xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW1]] as %arg2: memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}> {
    // CHECK:                                 VPUIP.Copy inputs(%arg1 : memref<1x128x2x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     }
    // CHECK:     [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY_OUTPUT_0]], [[COPY_OUTPUT_1]] : memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>, memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x6x32xf16>) -> memref<1x128x6x32xf16>
    // CHECK:     return [[CONCAT]] : memref<1x128x6x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_SoftMax(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "single_shave_softmax.cpp", VPU.kernel_entry = "singleShaveSoftmax"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterSoftmax(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [0]}(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x128x64x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 32, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 32, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SOFTMAX:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK{LITERAL}:      %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg5: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) strides([[131072, 1024, 32, 1], [131072, 1024, 32, 1]]) on tile 0 -> (memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>){
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [0]}(%arg5, %arg7) : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [0]}(%arg6, %arg8) : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[SOFTMAX]]#0, [[SOFTMAX]]#1 : !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) outputs([[OUTPUT_CMX]] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_SoftMax(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "single_shave_softmax.cpp", VPU.kernel_entry = "singleShaveSoftmax"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileClusterSoftmaxForUnsupportedAxis(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [2]}(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x128x64x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SOFTMAX:%.*]] = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[OUTPUT_CMX]] as %arg2: memref<1x128x64x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg3: memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x128x64x32xf16, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, @CMX_NN>{
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [2]}(%arg3, %arg4) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[SOFTMAX]] as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x128x64x32xf16>
}

// -----

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileClusterHalfPixelInterpolateForCMXSizeRequirement(%arg0: memref<1x16x154x160xf16>) -> memref<1x16x308x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x16x154x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 16, 77, 160], [1, 16, 77, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 76, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x16x154x160xf16>) outputs(%0 as %arg3: memref<1x16x154x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x16x154x160xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 16, 77, 160], [1, 16, 77, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 76, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x16x154x160xf16>) outputs(%arg3 : memref<1x16x154x160xf16, @CMX_NN>) -> memref<1x16x154x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x16x308x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x16x154x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x16x308x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x16x308x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x16x154x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x16x308x320xf16, @CMX_NN>) on tile 0 -> memref<1x16x308x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 154, 16, 1], [320, 308, 16, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x16x154x160xf16, @CMX_NN>, memref<1x16x308x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x16x308x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x16x308x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x16x308x320xf16>) -> memref<1x16x308x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x16x308x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x16x308x320xf16>) -> memref<1x16x308x320xf16>
    }
    return %5 : memref<1x16x308x320xf16>

    // CHECK:    [[INPUT_BUF:%.*]] = VPURT.AllocDistributed
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x16x154x160xf16>) outputs([[INPUT_BUF]] as %arg2: memref<1x16x154x160xf16, @CMX_NN>)
    // CHECK:                          VPUIP.Copy inputs(%arg1 : memref<1x16x154x160xf16>) outputs(%arg2 : memref<1x16x154x160xf16, @CMX_NN>) -> memref<1x16x154x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF:%.*]] = VPURT.AllocDistributed
    // CHECK:    [[INTERP:%.*]] = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x16x154x160xf16, @CMX_NN>) outputs([[OUTPUT_BUF]] as %arg2: memref<1x16x308x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x16x308x320xf16, affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                          VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg3: memref<1x16x154x160xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x16x308x320xf16, @CMX_NN>) on tile 0 -> memref<1x16x308x320xf16, @CMX_NN>{
    // CHECK:                             VPUIP.SW.Kernel.run
    // CHECK-NOT:                         VPUIP.SW.Kernel.run
    // CHECK:                          }
    // CHECK:    }
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Multiply(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_mul.cpp", VPU.kernel_entry = "eltwise_mul"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterMultiply() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                          %1 as %arg1: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                  outputs(%2 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Multiply
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x88x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %5: memref<1x64x88x88xf16>

    // For Multiply First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // For Multiply Second Input
    // CHECK:    [[INPUT1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[MULTI_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MULTI_OUT_TILE0:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTI_OUT_TILE1:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTIPLY:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK-SAME{LIERAL}:        inputs([[INPUT0_TILE1]] as %arg0: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK-SAME{LIERAL}:               [[INPUT1_TILE1]] as %arg1: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as %arg2: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as %arg3: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs([[MULTI_OUT_TILE1]] as %arg4: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[MULTI_OUT_TILE0]] as %arg5: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:    %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Multiply
    // CHECK:                     inputs(%arg0 as %arg6: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg1 as %arg7: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg2 as %arg8: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg3 as %arg9: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs(%arg4 as %arg10: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             %arg5 as %arg11: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg7, %arg10) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg8, %arg9, %arg11) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[MULTIPLY]]#0, [[MULTIPLY]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[MULTI_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Multiply(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_mul.cpp", VPU.kernel_entry = "eltwise_mul"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterMultiplyAtBroadcastAxis() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                       %1 as %arg1: memref<1x1x1x88xf16, #NHWC, @CMX_NN>)
                                outputs(%2 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {result_segment_sizes = dense<[1, 0]> : vector<2xi32>} @VPU.SW::@builtin_Multiply
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x1x1x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x88x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %5: memref<1x64x88x88xf16>

    // For Multiply First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // For Multiply Second Input
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 1, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, {order = #NHWC, strides = [88, 1, 88, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 1, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, {order = #NHWC, strides = [88, 1, 88, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[MULTI_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MULTI_OUT_TILE0:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTI_OUT_TILE1:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTIPLY:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK-SAME{LIERAL}:        inputs([[INPUT0_TILE1]] as %arg0: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK-SAME{LIERAL}:               [[INPUT1_TILE1]] as %arg1: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as %arg2: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as %arg3: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs([[MULTI_OUT_TILE1]] as %arg4: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[MULTI_OUT_TILE0]] as %arg5: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:    %results:2 = VPUIP.SW.Kernel {result_segment_sizes = dense<[2, 0]> : vector<2xi32>} @VPU.SW::@builtin_Multiply
    // CHECK:                     inputs(%arg0 as %arg6: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg1 as %arg7: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                            %arg2 as %arg8: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg3 as %arg9: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs(%arg4 as %arg10: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             %arg5 as %arg11: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg7, %arg10) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg8, %arg9, %arg11) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[MULTIPLY]]#0, [[MULTIPLY]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[MULTI_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}
