//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch% allow-custom-values=true" --adjust-spill-size %s | FileCheck %s
// REQUIRES: arch-VPUX40XX

!dataTypeDdr = memref<1x256x56x56xf16, affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>, @DDR>
!dataTypeCmx = memref<1x256x56x56xf16, affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>, [@CMX_NN, 0]>

module @DmaSpillSingleCluster {
  IE.TileResource 1 of @NCE at 1.300000e+03 MHz {
    builtin.module @ReservedMemory {
      module @CompressDmaReservedMemory {
        IE.MemoryResource 64 bytes of @CMX_NN
      }
    }
  }

  IE.CNNNetwork entryPoint : @main inputsInfo : {
    DataInfo "data" : tensor<1x256x56x56xf16>
  } outputsInfo : {
    DataInfo "prob" : tensor<1x256x56x56xf16>
  }
  func.func @main(%arg0: !dataTypeDdr) -> !dataTypeDdr {

    %buf_in = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> !dataTypeCmx
    %buf_spill_write = memref.alloc() : !dataTypeDdr
    %buf_spill_read = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> !dataTypeCmx
    %buf_out = memref.alloc() : !dataTypeDdr


    %t0, %r0 = async.execute -> !async.value<!dataTypeCmx> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 0 : i64, cycleBegin = 0 : i64, cycleEnd = 100 : i64} {
        %0 = VPUIP.NNDMA inputs(%arg0 : !dataTypeDdr) outputs(%buf_in : !dataTypeCmx) -> !dataTypeCmx
        async.yield %0 : !dataTypeCmx
    }

    %t1, %r1 = async.execute [%t0] -> !async.value<!dataTypeDdr> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 1 : i64, cycleBegin = 100 : i64, cycleEnd = 200 : i64} {
        %0 = VPUIP.NNDMA {spillId = 0 : i64} inputs(%buf_in : !dataTypeCmx) outputs(%buf_spill_write : !dataTypeDdr) -> !dataTypeDdr
        async.yield %0 : !dataTypeDdr
    }

    %t2, %r2 = async.execute [%t1] (%r1 as %arg2: !async.value<!dataTypeDdr>) -> !async.value<!dataTypeCmx> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 2 : i64, cycleBegin = 200 : i64, cycleEnd = 300 : i64} {
        %0 = VPUIP.NNDMA {spillId = 0 : i64} inputs(%arg2 : !dataTypeDdr) outputs(%buf_spill_read : !dataTypeCmx) -> !dataTypeCmx
        async.yield %0 : !dataTypeCmx
    }

    %t3, %r3 = async.execute [%t2] (%r2 as %arg2: !async.value<!dataTypeCmx>) -> !async.value<!dataTypeDdr> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 3 : i64, cycleBegin = 300 : i64, cycleEnd = 400 : i64} {
        %0 = VPUIP.NNDMA inputs(%arg2 : !dataTypeCmx) outputs(%buf_out : !dataTypeDdr) -> !dataTypeDdr
        async.yield %0 : !dataTypeDdr
    }

    %r4 = async.await %r3 : !async.value<!dataTypeDdr>
    return %r4 : !dataTypeDdr
  }

    // CHECK:       [[BUF_IN:%.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>
    // CHECK:       [[BUF_SPILL_WRITE:%.*]] = memref.alloc() : memref<1x256x56x56xf16, {allocSize = 1630752 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>
    // CHECK:       [[BUF_SPILL_READ:%.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>
    // CHECK:       [[BUF_OUT:%.*]] = memref.alloc() : memref<1x256x56x56xf16, #NHWC, @DDR>

    // CHECK:       [[T0:%.+]], [[R0:%.+]] = async.execute
    // CHECK-SAME:      -> !async.value<memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>>
    // CHECK-NEXT:      VPUIP.NNDMA
    // CHECK-SAME:          inputs(%arg0 : memref<1x256x56x56xf16, #NHWC, @DDR>)
    // CHECK-SAME:          outputs([[BUF_IN]] : memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>)

    // CHECK:       [[T1:%.+]], [[R1:%.+]] = async.execute
    // CHECK-SAME:      [[T0]]
    // CHECK-SAME:      -> !async.value<memref<1x256x56x56xf16, {allocSize = 1630752 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>>
    // CHECK-NEXT:      VPUIP.NNDMA {compress_candidate, spillId = 0 : i64}
    // CHECK-SAME:          inputs([[BUF_IN]] : memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>)
    // CHECK-SAME:          outputs([[BUF_SPILL_WRITE]] : memref<1x256x56x56xf16, {allocSize = 1630752 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>)

    // CHECK:       [[T2:%.+]], [[R2:%.+]] = async.execute
    // CHECK-SAME:      [[T1]]
    // CHECK-SAME:      ([[R1]] as [[ARG0:%.*]]: !async.value<memref<1x256x56x56xf16, {allocSize = 1630752 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>>)
    // CHECK-SAME:      -> !async.value<memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>>
    // CHECK-NEXT:      VPUIP.NNDMA {compress_candidate, spillId = 0 : i64}
    // CHECK-SAME:          inputs([[ARG0]] : memref<1x256x56x56xf16, {allocSize = 1630752 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>)
    // CHECK-SAME:          outputs([[BUF_SPILL_READ]] : memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>)

    // CHECK:       [[T3:%.+]], [[R3:%.+]] = async.execute
    // CHECK-SAME:      [[T2]]
    // CHECK-SAME:      ([[R2]] as [[ARG3:%.*]]: !async.value<memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>>)
    // CHECK-SAME:      -> !async.value<memref<1x256x56x56xf16, #NHWC, @DDR>>
    // CHECK-NEXT:      VPUIP.NNDMA
    // CHECK-SAME:          inputs([[ARG3]] : memref<1x256x56x56xf16, #NHWC, [@CMX_NN, 0]>)
    // CHECK-SAME:          outputs([[BUF_OUT]] : memref<1x256x56x56xf16, #NHWC, @DDR>)

    // CHECK:       [[R4:%.+]] = async.await [[R3]] : !async.value<memref<1x256x56x56xf16, #NHWC, @DDR>>
    // CHECK-NEXT:  return [[R4]] : memref<1x256x56x56xf16, #NHWC, @DDR>
}

// -----

!dataTypeDdr = memref<1x256x56x56xf16, affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>, @DDR>
!dataTypeCmx = memref<1x256x56x56xf16, affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>, @CMX_NN>
!dataDistTypeCmx = !VPUIP.DistributedBuffer<1x256x56x56xf16, affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>

module @DmaSpillMultiCluster {
  IE.TileResource 1 of @NCE at 1.300000e+03 MHz {
    builtin.module @ReservedMemory {
      module @CompressDmaReservedMemory {
        IE.MemoryResource 64 bytes of @CMX_NN
      }
    }
  }

  IE.CNNNetwork entryPoint : @main inputsInfo : {
    DataInfo "data" : tensor<1x256x56x56xf16>
  } outputsInfo : {
    DataInfo "prob" : tensor<1x256x56x56xf16>
  }
  func.func @main(%arg0: !dataTypeDdr) -> !dataTypeDdr {

    %buf_in = VPURT.DeclareBuffer <CMX_NN> <0> -> !dataDistTypeCmx
    %buf_spill_write = memref.alloc() : !dataTypeDdr
    %buf_spill_read = VPURT.DeclareBuffer <CMX_NN> <0> -> !dataDistTypeCmx
    %buf_out = memref.alloc() : !dataTypeDdr


    %t0, %r0 = async.execute -> !async.value<!dataDistTypeCmx> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 0 : i64, cycleBegin = 0 : i64, cycleEnd = 100 : i64} {
        %0 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: !dataTypeDdr) outputs(%buf_in as %arg3: !dataTypeCmx) -> !dataDistTypeCmx {
            %1 = VPUIP.NNDMA inputs(%arg2 : !dataTypeDdr) outputs(%arg3 : !dataTypeCmx) -> !dataTypeCmx
        }
        async.yield %0 : !dataDistTypeCmx
    }

    %t1, %r1 = async.execute [%t0] -> !async.value<!dataTypeDdr> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 1 : i64, cycleBegin = 100 : i64, cycleEnd = 200 : i64} {
        %0 = VPUIP.NCEClusterTiling inputs(%buf_in as %arg2: !dataTypeCmx) outputs(%buf_spill_write as %arg3: !dataTypeDdr) -> !dataTypeDdr {
            %1 = VPUIP.NNDMA {spillId = 0 : i64} inputs(%arg2 : !dataTypeCmx) outputs(%arg3 : !dataTypeDdr) -> !dataTypeDdr
        }
        async.yield %0 : !dataTypeDdr
    }

    %t2, %r2 = async.execute [%t1] (%r1 as %arg2: !async.value<!dataTypeDdr>) -> !async.value<!dataDistTypeCmx> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 2 : i64, cycleBegin = 200 : i64, cycleEnd = 300 : i64} {
        %0 = VPUIP.NCEClusterTiling inputs(%arg2 as %arg3: !dataTypeDdr) outputs(%buf_spill_read as %arg4: !dataTypeCmx) -> !dataDistTypeCmx {
            %1 = VPUIP.NNDMA {spillId = 0 : i64} inputs(%arg3 : !dataTypeDdr) outputs(%arg4 : !dataTypeCmx) -> !dataTypeCmx
        }
        async.yield %0 : !dataDistTypeCmx
    }

    %t3, %r3 = async.execute [%t2] (%r2 as %arg2: !async.value<!dataDistTypeCmx>) -> !async.value<!dataTypeDdr> attributes {VPUIP.executor = @DMA_NN, VPUIP.executorIdx = [0, 1], "async-deps-index" = 3 : i64, cycleBegin = 300 : i64, cycleEnd = 400 : i64} {
        %0 = VPUIP.NCEClusterTiling inputs(%arg2 as %arg3: !dataTypeCmx) outputs(%buf_out as %arg4: !dataTypeDdr) -> !dataTypeDdr {
            %1 = VPUIP.NNDMA inputs(%arg3 : !dataTypeCmx) outputs(%arg4 : !dataTypeDdr) -> !dataTypeDdr
        }
        async.yield %0 : !dataTypeDdr
    }

    %r4 = async.await %r3 : !async.value<!dataTypeDdr>
    return %r4 : !dataTypeDdr
  }

    // CHECK:       [[BUF_IN:%.*]] = VPURT.DeclareBuffer <CMX_NN> <0> -> !VPUIP.DistributedBuffer<1x256x56x56xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>
    // CHECK:       [[BUF_SPILL_WRITE:%.*]] = memref.alloc() : memref<1x256x56x56xf16, {allocSize = 1630784 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>
    // CHECK:       [[BUF_SPILL_READ:%.*]] = VPURT.DeclareBuffer <CMX_NN> <0> -> !VPUIP.DistributedBuffer<1x256x56x56xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>
    // CHECK:       [[BUF_OUT:%.*]] = memref.alloc() : memref<1x256x56x56xf16, #NHWC, @DDR>

    // CHECK:       [[T0:%.+]], [[R0:%.+]] = async.execute
    // CHECK-SAME:      -> !async.value<!VPUIP.DistributedBuffer<1x256x56x56xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>>
    // CHECK-NEXT:      VPUIP.NCEClusterTiling
    // CHECK-NEXT:          VPUIP.NNDMA

    // CHECK:       [[T1:%.+]], [[R1:%.+]] = async.execute
    // CHECK-SAME:      [[T0]]
    // CHECK-SAME:      -> !async.value<memref<1x256x56x56xf16, {allocSize = 1630784 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>>
    // CHECK-NEXT:      VPUIP.NCEClusterTiling
    // CHECK-SAME:      inputs([[BUF_IN]] as %arg1: memref<1x256x56x56xf16, #NHWC, @CMX_NN>)
    // CHECK-SAME:      outputs([[BUF_SPILL_WRITE]] as %arg2: memref<1x256x56x56xf16, {allocSize = 1630784 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>)
    // CHECK-NEXT:          VPUIP.NNDMA {compress_candidate, spillId = 0 : i64}

    // CHECK:       [[T2:%.+]], [[R2:%.+]] = async.execute
    // CHECK-SAME:      [[T1]]
    // CHECK-SAME:      ([[R1]] as [[ARG0:%.*]]: !async.value<memref<1x256x56x56xf16, {allocSize = 1630784 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>>)
    // CHECK-SAME:      -> !async.value<!VPUIP.DistributedBuffer<1x256x56x56xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>>
    // CHECK-NEXT:      VPUIP.NCEClusterTiling
    // CHECK-SAME:      inputs([[ARG0]] as [[ARG1:%.*]]: memref<1x256x56x56xf16, {allocSize = 1630784 : i64, compression = #VPUIP.Compression<CompressionCandidate>, order = #NHWC}, @DDR>)
    // CHECK-SAME:      outputs([[BUF_SPILL_READ]] as [[ARG2:%.*]]: memref<1x256x56x56xf16, #NHWC, @CMX_NN>)
    // CHECK-NEXT:          VPUIP.NNDMA {compress_candidate, spillId = 0 : i64}

    // CHECK:       [[T3:%.+]], [[R3:%.+]] = async.execute
    // CHECK-SAME:      [[T2]]
    // CHECK-SAME:      ([[R2]] as [[ARG3:%.*]]: !async.value<!VPUIP.DistributedBuffer<1x256x56x56xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, uniform_distributed_segments}>>)
    // CHECK-SAME:      -> !async.value<memref<1x256x56x56xf16, #NHWC, @DDR>>
    // CHECK-NEXT:      VPUIP.NCEClusterTiling
    // CHECK-SAME:      inputs([[ARG3]] as [[ARG4:%.*]]: memref<1x256x56x56xf16, #NHWC, @CMX_NN>)
    // CHECK-SAME:      outputs([[BUF_OUT]] as [[ARG4:%.*]]: memref<1x256x56x56xf16, #NHWC, @DDR>)
    // CHECK-NEXT:          VPUIP.NNDMA

    // CHECK:       [[R4:%.+]] = async.await [[R3]] : !async.value<memref<1x256x56x56xf16, #NHWC, @DDR>>
    // CHECK-NEXT:  return [[R4]] : memref<1x256x56x56xf16, #NHWC, @DDR>
}
