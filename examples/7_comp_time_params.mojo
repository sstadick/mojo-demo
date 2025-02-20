from sys.info import simdwidthof


fn repeat[count: Int](msg: String):
    @parameter
    for i in range(count):  # this will get unrolled based on the count
        print(msg)


alias INV_LN2: Float64 = 1.4426950216e00
alias NEG_LN2: Float64 = -0.69314718056

alias SIMD_UINT64_WIDTH = simdwidthof[
    DType.uint64
]()  # Get the vector size for this dtype on the host system


fn add_mul[
    data_type: DType, elements: Int
](x: SIMD[data_type, elements], y: SIMD[data_type, elements]) -> SIMD[
    data_type, elements
]:
    """This is contrived, + and * just work out of the box on numeric types."""
    var z = x + y
    return z * x * y


fn main() raises:
    repeat[10]("Hello.")
    var x = SIMD[DType.uint64, SIMD_UINT64_WIDTH](10)
    var y = SIMD[DType.uint64, SIMD_UINT64_WIDTH](7)
    var z = add_mul(x, y)  # params inferred
    print(z)
