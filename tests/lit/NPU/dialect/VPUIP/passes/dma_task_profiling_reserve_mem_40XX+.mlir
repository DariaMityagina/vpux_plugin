//
// Copyright (C) 2023-2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --init-compiler="vpu-arch=%arch% allow-custom-values=true" --dma-task-profiling-reserve-mem="dma-profiling=true" %s | FileCheck %s
// REQUIRES: arch-NPU40XX

module @SimpleGraph {
  IE.CNNNetwork entryPoint : @main inputsInfo : {
    DataInfo "data" : tensor<1x16x4x4xf16>
  } outputsInfo : {
    DataInfo "prob" : tensor<1x16x4x4xf16>
  }
  func.func @main(%arg0: memref<1x16x4x4xf16>, %arg1: memref<1x16x4x4xf16>) -> memref<1x16x4x4xf16> {
    return %arg1 : memref<1x16x4x4xf16>
  }

    // CHECK:         ReservedMemory
    // CHECK-NEXT:         DmaProfilingReservedMemory
    // CHECK-NEXT:         IE.MemoryResource 4096 bytes of @DDR

    // CHECK:     IE.TileResource
    // CHECK:         ReservedMemory
    // CHECK-NEXT:         DmaProfilingReservedMemory
    // CHECK-NEXT:         IE.MemoryResource 512 bytes of @CMX_NN
}
