module wren.math;

@nogc:
// Note: We had to get rid of the union here, as CTFE
// does not allow us to reinterpret fields via field
// overlapping. 
enum WREN_DOUBLE_QNAN_POS_MIN_BITS = cast(ulong)(0x7FF8000000000000);
enum WREN_DOUBLE_QNAN_POS_MAX_BITS = cast(ulong)(0x7FFFFFFFFFFFFFFF);

enum WREN_DOUBLE_NAN = wrenDoubleFromBits(WREN_DOUBLE_QNAN_POS_MIN_BITS);

static double wrenDoubleFromBits(ulong bits)
{
    return *cast(double*)&bits;
}

static ulong wrenDoubleToBits(double num)
{
    return *cast(ulong*)&num;
}