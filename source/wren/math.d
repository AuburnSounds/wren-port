module wren.math;

@nogc:
// Note: We had to get rid of the union here, as CTFE
// does not allow us to reinterpret fields via field
// overlapping. 
enum WREN_DOUBLE_QNAN_POS_MIN_BITS = cast(ulong)(0x7FF8000000000000);
enum WREN_DOUBLE_QNAN_POS_MAX_BITS = cast(ulong)(0x7FFFFFFFFFFFFFFF);

enum WREN_DOUBLE_NAN = wrenDoubleFromBits(WREN_DOUBLE_QNAN_POS_MIN_BITS);

double wrenDoubleFromBits(ulong bits) nothrow
{
    return *cast(double*)&bits;
}

ulong wrenDoubleToBits(double num) nothrow
{
    return *cast(ulong*)&num;
}

// no-floating-point abs
auto abs(Num)(Num x) {
    return x >= 0 ? x : -x;
}
