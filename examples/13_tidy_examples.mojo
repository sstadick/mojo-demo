import math

from algorithm import vectorize
from bit import pop_count
from gpu.host import DeviceBuffer, DeviceContext, HostBuffer
from gpu.id import block_dim, block_idx, thread_idx
from math import ceildiv
from memory import pack_bits
from sys import simdwidthof

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
    var aligned_end = math.align_down(len(sequence), simd_width)
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


fn count_nuc_content_gpu[
    *nucs: UInt8
](
    sequence: DeviceBuffer[DType.uint8],
    sequence_length: UInt,
    count_output: DeviceBuffer[DType.uint64],
) -> UInt:
    """Count the nucleotide content in a sequence.

    Args:
        sequence: The nucleotide sequence to scan for counts.

    Parameters:
        simd_width: SIMD vector width to use.
        nucs: The variadic list of nucleotides include in the count.

    Return:
        The count of the observed nucs.
    """
    # Calculate global thread index
    var thread_id = (block_idx.x * block_dim.x) + thread_idx.x
    
    pass


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


def main():
    alias G = UInt8(ord("G"))
    alias C = UInt8(ord("C"))

    var seq = "ACTGACTGACGCCCCCCCCCCCCTTTTTTTTT".as_bytes()

    var count_vectorized = count_nuc_content[U8_SIMD_WIDTH, G, C](seq)
    var count_manual_simd = count_nuc_content_manual[U8_SIMD_WIDTH, G, C](seq)
    var count_naive = count_nuc_content_naive(seq, List(G, C))

    if count_vectorized != count_manual_simd or count_vectorized != count_naive:
        raise "All counts not equal!"

    print("GC Content:", count_vectorized)
