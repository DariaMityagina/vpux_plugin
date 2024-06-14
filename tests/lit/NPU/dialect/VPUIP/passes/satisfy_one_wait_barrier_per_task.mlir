//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --satisfy-one-wait-barrier-per-task="max-variant-count=8" %s | FileCheck %s
// REQUIRES: arch-VPUX30XX || arch-VPUX37XX || arch-VPUX40XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @LegalProducers
func.func @LegalProducers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //   0 1   2 3
    //    |     |
    //   bar0  bar1
    //     \   /
    //       4

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumer

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //    0 1 2 3
    //       |
    //      bar0
    //       |
    //       4

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK-NOT:            VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotLegalProducerCount
func.func @NotLegalProducerCount() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 1 2  3 4
    //    |     |
    //   bar0  bar1
    //     \   /
    //       5

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumer

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 1 2
    //    |
    //   bar0
    //    |
    //   3 4
    //    |
    //   bar1
    //    |
    //    5

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotLegalProducerCountWithProducerCountGreaterThanHalfMaxSlotCount
func.func @NotLegalProducerCountWithProducerCountGreaterThanHalfMaxSlotCount() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers
    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    // 0 1 2 3       7 8 9 10
    //  4 5 6        11 12 13
    //    |              |
    //   bar0          bar1
    //      \        /
    //         14

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }


    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }
    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }


    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumer

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 1 2 3
    //    |
    //   bar0
    //    |
    //   4 5 6
    //    |
    //   bar1
    //    |
    //   7 8 9 10
    //    |
    //   bar2
    //    |
    //   11 12 13
    //    |
    //   bar3
    //    |
    //   14


    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR2:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR3:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)


    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier) updates([[BAR2]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier) updates([[BAR2]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier) updates([[BAR2]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier) updates([[BAR2]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR2]] : !VPURT.Barrier) updates([[BAR3]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR2]] : !VPURT.Barrier) updates([[BAR3]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR2]] : !VPURT.Barrier) updates([[BAR3]] : !VPURT.Barrier)
}
    // CHECK: VPURT.Task waits([[BAR3]] : !VPURT.Barrier)



// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotOrderedBarrierProducers
func.func @NotOrderedBarrierProducers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //   0 2  1 3 4
    //    |     |
    //   bar0  bar1
    //     \   /
    //       5

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumer

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 1 2 3
    //     |
    //    bar0
    //     |
    //     4
    //     |
    //    bar1
    //     |
    //     5

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @LegalSharedParallelProducers
func.func @LegalSharedParallelProducers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //    0  1 2  3
    //    |  / \  |
    //   bar0    bar1
    //     \     /
    //        4

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumer

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //    0 1 2 3
    //       |
    //      bar0
    //       |
    //       4

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK-NOT:            VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotLegalSharedParallelProducers
func.func @NotLegalSharedParallelProducers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //    0  1 2  3 4
    //    |  /  \  |
    //   bar0     bar1
    //     \     /
    //        5

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumer

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 1 2 3
    //     |
    //    bar0
    //     |
    //     4
    //     |
    //    bar1
    //     |
    //     5

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotOrderedSharedParallelProducers
func.func @NotOrderedSharedParallelProducers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //    0  4 1  3 2
    //    |  /  \  |
    //   bar0     bar1
    //     \     /
    //        5

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumer

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 1 2 3
    //     |
    //    bar0
    //     |
    //     4
    //     |
    //    bar1
    //     |
    //     5

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier) updates([[BAR1]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @LegalProducersWithOtherUsers
func.func @LegalProducersWithOtherUsers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //   0 1   2 3
    //    |     |
    //   bar0  bar1
    //   /  \ /   \
    //  4    5     6

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumers

    VPURT.Task waits(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task waits(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //     0 1    2 3
    //     / \    / \
    //  bar0  bar1  bar2
    //   |     |     |
    //   4     5     6

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR2:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR2]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR2]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR2]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotLegalProducersWithOtherUsers
func.func @NotLegalProducersWithOtherUsers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 1 2  3 4
    //    |     |
    //   bar0  bar1
    //   /  \ /   \
    //  5    6     7

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumers

    VPURT.Task waits(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task waits(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //     0 1 2
    //     /   \
    //  bar0   bar1
    //   |      |
    //   5     3 4
    //         / \
    //      bar2 bar3
    //       |    |
    //       7    6

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR2:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR3:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier) updates([[BAR2]], [[BAR3]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier) updates([[BAR2]], [[BAR3]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR3]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR2]] : !VPURT.Barrier)
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotOrderedProducersWithOtherUsers
func.func @NotOrderedProducersWithOtherUsers() -> memref<1x16x1x1xf16, #NHWC, @DDR> {
    // barriers

    %bar0 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    %bar1 = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // dummy buffers

    %buf0 = VPURT.DeclareBuffer <DDR> <0> -> memref<1x16x1x1xf16, #NHWC, @DDR>
    %buf1 = VPURT.DeclareBuffer <DDR> <32> -> memref<1x16x1x1xf16, #NHWC, @DDR>

    //  0 3 4  1 2
    //    |     |
    //   bar0  bar1
    //   /  \ /   \
    //  5    6     7

    // parallel wait barriers

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task updates(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    // barrier consumers

    VPURT.Task waits(%bar0: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task waits(%bar0, %bar1: !VPURT.Barrier, !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    VPURT.Task waits(%bar1: !VPURT.Barrier) {
         VPUIP.NNDMA
            inputs(%buf0: memref<1x16x1x1xf16, #NHWC, @DDR>)
            outputs(%buf1: memref<1x16x1x1xf16, #NHWC, @DDR>)
            -> memref<1x16x1x1xf16, #NHWC, @DDR>
    }

    return %buf1 : memref<1x16x1x1xf16, #NHWC, @DDR>

    //      0 3    1 2
    //     /   \  /   \
    //    /    bar1  bar2
    //   |      |     |
    //   |      4     7
    //    \   /   \
    //     bar0   bar3
    //      |      |
    //      5      6

    // CHECK: [[BAR0:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR1:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR2:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier
    // CHECK: [[BAR3:%.*]] = VPURT.DeclareVirtualBarrier -> !VPURT.Barrier

    // CHECK: VPURT.Task updates([[BAR0]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR2]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR2]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)
    // CHECK: VPURT.Task updates([[BAR0]], [[BAR1]] : !VPURT.Barrier, !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR1]] : !VPURT.Barrier) updates([[BAR0]], [[BAR3]] : !VPURT.Barrier, !VPURT.Barrier)

    // CHECK: VPURT.Task waits([[BAR0]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR3]] : !VPURT.Barrier)
    // CHECK: VPURT.Task waits([[BAR2]] : !VPURT.Barrier)
}
