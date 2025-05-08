from algorithm import vectorize
from benchmark import (
    Bench,
    Bencher,
    BenchId,
    BenchMetric,
    ThroughputMeasure,
    keep,
)
from bit import pop_count
from math import align_down, ceildiv
from memory import UnsafePointer, pack_bits, memcpy, stack_allocation
from os import Atomic
from sys import simdwidthof, argv, has_accelerator
from time import perf_counter

from gpu import barrier, warp
from gpu.host import DeviceBuffer, DeviceContext, HostBuffer
from gpu.id import block_dim, block_idx, thread_idx
from gpu.memory import AddressSpace

alias G = UInt8(ord("G"))
alias C = UInt8(ord("C"))

alias U8_SIMD_WIDTH = simdwidthof[DType.uint8]()
"""Get the HW SIMD register size for uint8"""


fn count_nuc_content_manual[
    simd_width: Int, *nucs: UInt8
](sequence: Span[UInt8]) -> UInt:
    """Count the nucleotide content in a sequence.

    This implementation uses manual SIMD looping.

    Args:
        sequence: The nucleotide sequence to scan for counts.

    Parameters:
        simd_width: SIMD vector width to use.
        nucs: The variadic list of nucleotides include in the count.

    Return:
        The count of the observed nucs.
    """
    alias nucs_to_search = VariadicList(nucs)
    var count = 0
    var ptr = sequence.unsafe_ptr()

    # Determine the aligned endpoint
    # EX: with a simd_width=16, and a len(sequence)=24, the aligned end would be 16.
    var aligned_end = align_down(len(sequence), simd_width)
    # Loop over the input in "chunks" that are as wide as simd_width
    for offset in range(0, aligned_end, simd_width):
        # Load simd_width elements from the vector into a SIMD[DType.uint8, simd_width] vector
        var vector = ptr.offset(offset).load[width=simd_width]()

        # parameter means this is a run at compile time and turns into an unrolled loop.
        # So for each of the input nucleotides to check The loop is unrolled into a linear check.
        @parameter
        for i in range(0, len(nucs_to_search)):
            # alias is again compile time, so this is effectively a constant
            alias nuc_vector = SIMD[DType.uint8, simd_width](nucs_to_search[i])
            # assume simd_width=4 for this example
            # [A, T, C, G] == [C, C, C, C] -> [False, False, True, False]
            var mask = vector == nuc_vector
            # [False, False, True, False] -> [0010]
            var packed = pack_bits(mask)
            # pop_count counts the number of 1 bits
            count += Int(pop_count(packed))

    # The cleanup loop, to account for anything that doesn't fit in the SIMD vector
    for offset in range(aligned_end, len(sequence)):
        # Note, it's the same compile time loop over the input nucs, just loading them
        # into width 1 vectors instead.
        @parameter
        for i in range(0, len(nucs_to_search)):
            alias nuc = SIMD[DType.uint8, 1](nucs_to_search[i])
            count += Int(sequence[offset] == nuc)
    return count


fn count_nuc_content[
    simd_width: Int, *nucs: UInt8
](sequence: Span[UInt8]) -> UInt:
    """Count the nucleotide content in a sequence.

    This implementation uses the `vectorize` helper.

    Args:
        sequence: The nucleotide sequence to scan for counts.

    Parameters:
        simd_width: SIMD vector width to use.
        nucs: The variadic list of nucleotides include in the count.

    Return:
        The count of the observed nucs.
    """
    alias nucs_to_search = VariadicList(nucs)
    var count = 0
    var ptr = sequence.unsafe_ptr()

    # This is a closure that takes a SIMD width, and an offset, called by vectorize
    @parameter
    fn count_nucs[width: Int](offset: Int):
        @parameter
        for i in range(0, len(nucs_to_search)):
            alias nuc_vector = SIMD[DType.uint8, width](nucs_to_search[i])
            var vector = ptr.offset(offset).load[width=width]()
            var mask = vector == nuc_vector

            # pack_bits only works on sizes that correspond to types
            # so in the vectorize cleanup where width=1 we need to handle
            # the count specially.
            @parameter
            if width == 1:
                count += Int(mask)
            else:
                var packed = pack_bits(mask)
                count += Int(pop_count(packed))

    vectorize[count_nucs, simd_width](len(sequence))
    # Calls the provided function like:
    # count_nucs[16](0)
    # count_nucs[16](16)
    # count_nucs[16](32)
    # ...
    # And for the remainder, switch to SIMD width 1
    # count_nucs[1](48)

    return count


fn count_nuc_content_naive(sequence: Span[UInt8], nucs: List[UInt8]) -> Int:
    """Count the nucleotide content in a sequence.

    Args:
        sequence: The nucleotide sequence to scan for counts.
        nucs: The list of nucleotides include in the count.

    Return:
        The count of the observed nucs.
    """
    var count = 0
    for i in range(0, len(sequence)):
        for j in range(0, len(nucs)):
            count += Int(sequence[i] == nucs[j])
    return count


fn count_nuc_content_gpu[
    block_size: UInt, coarse_factor: UInt, *nucs: UInt8
](
    sequence: UnsafePointer[Scalar[DType.uint8]],
    sequence_length: UInt,
    count_output: UnsafePointer[Scalar[DType.uint64]],
):
    """GPU Kernel for doing GC counting in a sum-reduction pattern.

    Args:
        sequence: Pointer to the DNA sequence to do counts on.
        sequence_length: Length of the DNA sequence.
        count_output: Pointer to location to store the GC count.

    Parameters:
        block_size: The number of threads per block.
        coarse_factor: Number of elements each thread to work though.
        nucs: Variadic list of nucleotides to count.
    """
    alias nucs_to_search = VariadicList(nucs)
    # Shared cache for this warp
    alias cache = stack_allocation[
        block_size, Scalar[DType.uint64], address_space = AddressSpace.SHARED
    ]()

    # segment of the sequence this block will count
    var segment = coarse_factor * 2 * block_dim.x * block_idx.x
    var i = segment + thread_idx.x  # Global index
    var t = thread_idx.x  # thread id
    # Each thread zeros its cache index
    cache[t] = 0
    barrier()  # Sync up all the threads on the warp

    # Iterate over the segment, each iteration will cover 32 values
    var sum = UInt16(0)
    for tile in range(0, coarse_factor * 2):
        # Determine the global index into the sequence for this thread
        var index = i + tile * block_size
        # if the index is outside or length, do nothing, this will stall this tread
        if index < sequence_length:
            var base = sequence[i + tile * block_size]

            # Same comptime pattern we saw in the SIMD code
            @parameter
            for i in range(0, len(nucs_to_search)):
                sum += UInt16(base == nucs_to_search[i])
    # Store this threads sum in the cache
    cache[t] = UInt64(sum)

    # Do the reduction (see diagram)
    var stride = block_dim.x // 2
    while stride >= 1:
        barrier()
        if t < stride:
            cache[t] += cache[t + stride]
        stride = stride // 2

    # Finally, have the first thread in the warp set add to the global sum
    if t == 0:
        _ = Atomic.fetch_add(count_output, cache[t])


fn count_nuc_content_gpu_shuffle[
    block_size: UInt, coarse_factor: UInt, *nucs: UInt8
](
    sequence: UnsafePointer[Scalar[DType.uint8]],
    sequence_length: UInt,
    count_output: UnsafePointer[Scalar[DType.uint64]],
):
    """GPU Kernel for doing GC counting in a sum-reduction pattern.

    Args:
        sequence: Pointer to the DNA sequence to do counts on.
        sequence_length: Length of the DNA sequence.
        count_output: Pointer to location to store the GC count.

    Parameters:
        block_size: The number of threads per block.
        coarse_factor: Number of elements each thread to work though.
        nucs: Variadic list of nucleotides to count.
    """
    # Compile time constraint on block_size
    constrained[block_size == 32, "Block size must equal warp size"]()

    alias nucs_to_search = VariadicList(nucs)

    # Each thread zeros its cache index
    var segment = coarse_factor * 2 * block_dim.x * block_idx.x
    var i = segment + thread_idx.x
    var t = thread_idx.x
    barrier()

    var sum = UInt32(0)

    @parameter
    for tile in range(0, coarse_factor * 2):
        var index = i + tile * block_size
        if index < sequence_length:
            var base = sequence[i + tile * block_size]

            @parameter
            for i in range(0, len(nucs_to_search)):
                sum += UInt32(base == nucs_to_search[i])

    alias offsets = InlineArray[UInt32, size=5](16, 8, 4, 2, 1)

    # No more shared cache!
    # This uses a shuffle, which passes a value 1 thread down
    @parameter
    for offset in range(0, len(offsets)):
        sum += warp.shuffle_down(sum, offsets[offset])

    if t == 0:
        _ = Atomic.fetch_add(count_output, UInt64(sum))


fn read_genome(read file: String) raises -> List[UInt8]:
    var genome = List[UInt8](
        capacity=3209286105
    )  # Size of the file we are reading for benchmarks
    var buffer = InlineArray[UInt8, size = 1024 * 128 * 5](fill=0)
    with open(file, "rb") as fh:
        while (bytes_read := fh.read(buffer)) > 0:
            genome.extend(Span(buffer)[0:bytes_read])

    return genome


fn bench_gpu(
    genome: Span[UInt8],
    mut b: Bench,
    expected_count: UInt,
    read bytes_: ThroughputMeasure,
) raises:
    var ctx = DeviceContext()

    # Set up buffers
    var host_genome = ctx.enqueue_create_host_buffer[DType.uint8](len(genome))
    var dev_genome = ctx.enqueue_create_buffer[DType.uint8](len(genome))
    var host_output = ctx.enqueue_create_host_buffer[DType.uint64](1)
    var dev_output = ctx.enqueue_create_buffer[DType.uint64](1).enqueue_fill(0)
    ctx.synchronize()
    memcpy(host_genome.unsafe_ptr(), genome.unsafe_ptr(), len(genome))
    var start = perf_counter()
    host_genome.enqueue_copy_to(dev_genome)
    ctx.synchronize()
    var end = perf_counter()
    print("Data TX took:", end - start)

    # Should now be ready to run
    alias block_size = 32  # Equal to a warp
    alias coarse_factor = 32
    ctx.enqueue_function[
        count_nuc_content_gpu[block_size, coarse_factor, G, C]
    ](
        dev_genome.unsafe_ptr(),
        UInt(len(genome)),
        dev_output.unsafe_ptr(),
        grid_dim=ceildiv(len(genome), (coarse_factor * block_size)),
        block_dim=block_size,
    )
    dev_output.enqueue_copy_to(host_output)
    ctx.synchronize()
    if host_output[0] != expected_count:
        raise "Invalid GPU output base impl"

    dev_output = dev_output.enqueue_fill(0)
    ctx.enqueue_function[
        count_nuc_content_gpu_shuffle[block_size, coarse_factor, G, C]
    ](
        dev_genome.unsafe_ptr(),
        UInt(len(genome)),
        dev_output.unsafe_ptr(),
        grid_dim=ceildiv(len(genome), (coarse_factor * block_size)),
        block_dim=block_size,
    )
    dev_output.enqueue_copy_to(host_output)
    ctx.synchronize()
    if host_output[0] != expected_count:
        raise "Invalid GPU output for shuffle"

    @parameter
    @always_inline
    fn bench_gpu[cf: UInt](mut b: Bencher) raises:
        var f = ctx.compile_function[
            count_nuc_content_gpu[block_size, cf, G, C]
        ]()

        @parameter
        @always_inline
        fn kernel_launch(ctx: DeviceContext) raises:
            ctx.enqueue_function(
                f,
                dev_genome.unsafe_ptr(),
                UInt(len(genome)),
                dev_output.unsafe_ptr(),
                grid_dim=ceildiv(len(genome), (cf * block_size)),
                block_dim=block_size,
            )

        b.iter_custom[kernel_launch](ctx)

    @parameter
    @always_inline
    fn bench_gpu_shuffle[cf: UInt](mut b: Bencher) raises:
        var f = ctx.compile_function[
            count_nuc_content_gpu_shuffle[block_size, cf, G, C]
        ]()

        @parameter
        @always_inline
        fn kernel_launch(ctx: DeviceContext) raises:
            ctx.enqueue_function(
                f,
                dev_genome.unsafe_ptr(),
                UInt(len(genome)),
                dev_output.unsafe_ptr(),
                grid_dim=ceildiv(len(genome), (cf * block_size)),
                block_dim=block_size,
            )

        b.iter_custom[kernel_launch](ctx)

    @parameter
    @always_inline
    fn bench_gpu_with_data_tx[cf: UInt](mut b: Bencher) raises:
        var f = ctx.compile_function[
            count_nuc_content_gpu[block_size, cf, G, C]
        ]()

        @parameter
        @always_inline
        fn kernel_launch(ctx: DeviceContext) raises:
            host_genome.enqueue_copy_to(dev_genome)
            ctx.enqueue_function(
                f,
                dev_genome.unsafe_ptr(),
                UInt(len(genome)),
                dev_output.unsafe_ptr(),
                grid_dim=ceildiv(len(genome), (cf * block_size)),
                block_dim=block_size,
            )
            host_output.enqueue_copy_to(dev_output)
            var count = host_output[0]
            keep(count)

        b.iter_custom[kernel_launch](ctx)

    b.bench_function[bench_gpu[32]](
        BenchId("GPU coarse factor " + String(32)), bytes_
    )
    b.bench_function[bench_gpu_with_data_tx[32]](
        BenchId("GPU coarse factor " + String(32) + " w/ data tx"), bytes_
    )
    b.bench_function[bench_gpu_shuffle[32]](
        BenchId("GPU shuffle coarse factor " + String(32)), bytes_
    )


def validate_methods(genome: Span[UInt8]) -> UInt:
    # Verify all solutions produce same results
    var start = perf_counter()
    var count_vectorized = count_nuc_content[U8_SIMD_WIDTH, G, C](genome)
    var end = perf_counter()
    print("Vectorized took:", end - start)

    start = perf_counter()
    var count_manual_simd = count_nuc_content_manual[U8_SIMD_WIDTH, G, C](
        genome
    )
    end = perf_counter()
    print("Manual took:", end - start)

    start = perf_counter()
    var count_naive = count_nuc_content_naive(genome, List(G, C))
    end = perf_counter()
    print("Naive took:", end - start)

    if count_vectorized != count_manual_simd or count_vectorized != count_naive:
        raise "All counts not equal!"

    print("GC Content:", count_vectorized)
    return count_vectorized


def main():
    """Compare methods of counting GC content.

    Data prep:
    ```
    wget https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz
    zcat hg38.fa.gz | grep -v '^>' | tr -d '\n' > hg38_seqs_only.txt
    ```
    """
    var genome_file = argv()[1]
    var genome = read_genome(genome_file)

    var expected_gc = validate_methods(genome)

    var b = Bench()
    var bytes_ = ThroughputMeasure(BenchMetric.bytes, len(genome))

    @parameter
    @always_inline
    fn bench_manual_simd[simd_width: Int](mut b: Bencher) raises:
        @parameter
        @always_inline
        fn run() raises:
            var count = count_nuc_content_manual[simd_width, G, C](genome)
            keep(count)

        b.iter[run]()

    @parameter
    @always_inline
    fn bench_vectorized[simd_width: Int](mut b: Bencher) raises:
        @parameter
        @always_inline
        fn run() raises:
            var count = count_nuc_content[simd_width, G, C](genome)
            keep(count)

        b.iter[run]()

    @parameter
    @always_inline
    fn bench_naive(mut b: Bencher) raises:
        @parameter
        @always_inline
        fn run() raises:
            var count = count_nuc_content_naive(genome, List(G, C))
            keep(count)

        b.iter[run]()

    @parameter
    if has_accelerator():
        bench_gpu(genome, b, expected_gc, bytes_)

    b.bench_function[bench_manual_simd[U8_SIMD_WIDTH]](
        BenchId("Manual SIMD, width " + String(U8_SIMD_WIDTH)), bytes_
    )
    b.bench_function[bench_vectorized[U8_SIMD_WIDTH]](
        BenchId("Vectorized, width " + String(U8_SIMD_WIDTH)), bytes_
    )
    b.bench_function[bench_manual_simd[U8_SIMD_WIDTH * 2]](
        BenchId("Manual SIMD, width " + String(U8_SIMD_WIDTH * 2)), bytes_
    )
    b.bench_function[bench_vectorized[U8_SIMD_WIDTH * 2]](
        BenchId("Vectorized, width " + String(U8_SIMD_WIDTH * 2)), bytes_
    )
    b.bench_function[bench_naive](BenchId("Naive"), bytes_)

    b.config.verbose_metric_names = False
    print(b)
