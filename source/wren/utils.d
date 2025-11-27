module wren.utils;

nothrow @nogc:

import core.stdc.stdlib: strtod;
import core.stdc.string;

struct ByteBuffer
{
    ubyte* data;
    int count;
    int capacity;
};

void wrenByteBufferInit(ByteBuffer* buffer) nothrow @nogc
{
    buffer.data = null;
    buffer.capacity = 0;
    buffer.count = 0;
}

void wrenByteBufferClear(VM)(VM* vm, ByteBuffer* buffer) @nogc
{
    import wren.vm : wrenReallocate;
    wrenReallocate(vm, buffer.data, 0, 0);
    wrenByteBufferInit(buffer);
}

void wrenByteBufferFill(VM)(VM* vm, ByteBuffer* buffer, ubyte data, int count) @nogc
{
    import wren.vm : wrenReallocate;
    if (buffer.capacity < buffer.count + count) {
        int capacity = wrenPowerOf2Ceil(buffer.count + count);
        buffer.data = cast(ubyte*)wrenReallocate(vm, buffer.data,
                                                 buffer.capacity * (ubyte).sizeof, capacity * (ubyte).sizeof);
        buffer.capacity = capacity;
    }

    for (int i = 0; i < count; i++) {
        buffer.data[buffer.count++] = data;
    }
}

void wrenByteBufferWrite(VM)(VM* vm, ByteBuffer* buffer, ubyte data) @nogc
{
    wrenByteBufferFill(vm, buffer, data, 1);
}

struct IntBuffer
{
    int* data;
    int count;
    int capacity;
};

void wrenIntBufferInit(IntBuffer* buffer) nothrow @nogc
{
    buffer.data = null;
    buffer.capacity = 0;
    buffer.count = 0;
}

void wrenIntBufferClear(VM)(VM* vm, IntBuffer* buffer) @nogc
{
    import wren.vm : wrenReallocate;
    wrenReallocate(vm, buffer.data, 0, 0);
    wrenIntBufferInit(buffer);
}

void wrenIntBufferFill(VM)(VM* vm, IntBuffer* buffer, int data, int count) @nogc
{
    import wren.vm : wrenReallocate;
    if (buffer.capacity < buffer.count + count) {
        int capacity = wrenPowerOf2Ceil(buffer.count + count);
        buffer.data = cast(int*)wrenReallocate(vm, buffer.data,
                                               buffer.capacity * (int).sizeof, capacity * (int).sizeof);
        buffer.capacity = capacity;
    }

    for (int i = 0; i < count; i++) {
        buffer.data[buffer.count++] = data;
    }
}

void wrenIntBufferWrite(VM)(VM* vm, IntBuffer* buffer, int data) @nogc
{
    wrenIntBufferFill(vm, buffer, data, 1);
}

// Returns the number of bytes needed to encode [value] in UTF-8.
//
// Returns 0 if [value] is too large to encode.
int wrenUtf8EncodeNumBytes(int value) @nogc
{
  assert(value >= 0, "Cannot encode a negative value.");
  
  if (value <= 0x7f) return 1;
  if (value <= 0x7ff) return 2;
  if (value <= 0xffff) return 3;
  if (value <= 0x10ffff) return 4;
  return 0;
}


// Encodes value as a series of bytes in [bytes], which is assumed to be large
// enough to hold the encoded result.
//
// Returns the number of written bytes.
int wrenUtf8Encode(int value, ubyte* bytes) @nogc
{
  if (value <= 0x7f)
  {
    // Single byte (i.e. fits in ASCII).
    *bytes = value & 0x7f;
    return 1;
  }
  else if (value <= 0x7ff)
  {
    // Two byte sequence: 110xxxxx 10xxxxxx.
    *bytes = 0xc0 | ((value & 0x7c0) >> 6);
    bytes++;
    *bytes = 0x80 | (value & 0x3f);
    return 2;
  }
  else if (value <= 0xffff)
  {
    // Three byte sequence: 1110xxxx 10xxxxxx 10xxxxxx.
    *bytes = 0xe0 | ((value & 0xf000) >> 12);
    bytes++;
    *bytes = 0x80 | ((value & 0xfc0) >> 6);
    bytes++;
    *bytes = 0x80 | (value & 0x3f);
    return 3;
  }
  else if (value <= 0x10ffff)
  {
    // Four byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx.
    *bytes = 0xf0 | ((value & 0x1c0000) >> 18);
    bytes++;
    *bytes = 0x80 | ((value & 0x3f000) >> 12);
    bytes++;
    *bytes = 0x80 | ((value & 0xfc0) >> 6);
    bytes++;
    *bytes = 0x80 | (value & 0x3f);
    return 4;
  }

  // Invalid Unicode value. See: http://tools.ietf.org/html/rfc3629
  assert(0, "Unreachable");
}

// Decodes the UTF-8 sequence starting at [bytes] (which has max [length]),
// returning the code point.
//
// Returns -1 if the bytes are not a valid UTF-8 sequence.
int wrenUtf8Decode(ubyte* bytes, uint length) @nogc
{
  // Single byte (i.e. fits in ASCII).
  if (*bytes <= 0x7f) return *bytes;

  int value;
  uint remainingBytes;
  if ((*bytes & 0xe0) == 0xc0)
  {
    // Two byte sequence: 110xxxxx 10xxxxxx.
    value = *bytes & 0x1f;
    remainingBytes = 1;
  }
  else if ((*bytes & 0xf0) == 0xe0)
  {
    // Three byte sequence: 1110xxxx	 10xxxxxx 10xxxxxx.
    value = *bytes & 0x0f;
    remainingBytes = 2;
  }
  else if ((*bytes & 0xf8) == 0xf0)
  {
    // Four byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx.
    value = *bytes & 0x07;
    remainingBytes = 3;
  }
  else
  {
    // Invalid UTF-8 sequence.
    return -1;
  }

  // Don't read past the end of the buffer on truncated UTF-8.
  if (remainingBytes > length - 1) return -1;

  while (remainingBytes > 0)
  {
    bytes++;
    remainingBytes--;

    // Remaining bytes must be of form 10xxxxxx.
    if ((*bytes & 0xc0) != 0x80) return -1;

    value = value << 6 | (*bytes & 0x3f);
  }

  return value;
}

// Returns the number of bytes in the UTF-8 sequence starting with [byte].
//
// If the character at that index is not the beginning of a UTF-8 sequence,
// returns 0.
int wrenUtf8DecodeNumBytes(ubyte byte_) @nogc
{
  // If the byte starts with 10xxxxx, it's the middle of a UTF-8 sequence, so
  // don't count it at all.
  if ((byte_ & 0xc0) == 0x80) return 0;
  
  // The first byte's high bits tell us how many bytes are in the UTF-8
  // sequence.
  if ((byte_ & 0xf8) == 0xf0) return 4;
  if ((byte_ & 0xf0) == 0xe0) return 3;
  if ((byte_ & 0xe0) == 0xc0) return 2;
  return 1;
}

// From: http://graphics.stanford.edu/~seander/bithacks.html#RoundUpPowerOf2Float
// Returns the smallest power of two that is equal to or greater than [n].
int wrenPowerOf2Ceil(int n) nothrow @nogc
{
  n--;
  n |= n >> 1;
  n |= n >> 2;
  n |= n >> 4;
  n |= n >> 8;
  n |= n >> 16;
  n++;
  
  return n;
}

// Validates that [value] is within `[0, count)`. Also allows
// negative indices which map backwards from the end. Returns the valid positive
// index value. If invalid, returns `uint.max`.
uint wrenValidateIndex(uint count, long value) @nogc
{
  // Negative indices count from the end.
  if (value < 0) value = count + value;

  // Check bounds.
  if (value >= 0 && value < count) return cast(uint)value;

  return uint.max;
}


/// Float parsing


/// strtod replacement, but without locale
///     s Must be a zero-terminated string.
/// Note that this code is duplicated in dplug:core, this was to avoid a dependency on dplug:core here.
public double strtod_nolocale(const(char)* s, const(char)** p)
{
    bool strtod_err = false;
    const(char)* pend;
    double r = stb__clex_parse_number_literal(s, &pend, &strtod_err, true);
    if (p) 
        *p = pend;
    if (strtod_err)
        r = 0.0;
    return r;
}
unittest
{    
    string[8] sPartial = ["0x123lol", "+0x1.921fb54442d18p+0001()", "0,", "-0.0,,,,", "0.65,stuff", "1.64587okokok", "-1.0e+9HELLO", "1.1454e-25f#STUFF"]; 
    for (int n = 0; n < 8; ++n)
    {
        const(char)* p1, p2;
        double r1 = strtod(sPartial[n].ptr, &p1); // in unittest, no program tampering the C locale
        double r2 = strtod_nolocale(sPartial[n].ptr, &p2);
        //import core.stdc.stdio;
        //debug printf("parsing \"%s\" %lg %lg %p %p\n", sPartial[n].ptr, r1, r2, p1, p2);
        assert(p1 == p2);
    }
}

/// C-locale independent string to integer parsing.
/// Params:
///     s = Must be a zero-terminated string.
///     mustConsumeEntireInput = if true, check that s is entirely consumed by parsing the number.
///     err = optional bool
/// Note: unlike with `convertStringToDouble`, the string "4.7" will parse to just 4. Replaces %d in scanf-like functions.
/// Only parse correctly from -2147483648 to 2147483647.
/// Larger values are clamped to this -2147483648 to 2147483647 range.
public int convertStringToInteger(const(char)* s, 
                                  bool mustConsumeEntireInput,
                                  bool* err) pure nothrow @nogc
{
    if (s is null)
    {
        if (err) *err = true;
        return 0;
    }

    const(char)* end;
    bool strtod_err = false;
    bool allowFloat = false;
    double r = stb__clex_parse_number_literal(s, &end, &strtod_err, allowFloat);

    if (strtod_err)
    {
        if (err) *err = true;
        return 0;
    }

    if (mustConsumeEntireInput)
    {
        size_t len = strlen(s);
        if (end != s + len)
        {
            if (err) *err = true; // did not consume whole string
            return 0;
        }
    }

    if (err) *err = false; // no error

    double r2 = cast(int)r;
    assert(r2 == r); // should have returned an integer that fits in a double, like the whole int.min to int.max range.
    return cast(int)r;
}
unittest
{
    bool err;
    assert(4 == convertStringToInteger(" 4.7\n", false, &err));
    assert(!err);

    assert(-2147483648 == convertStringToInteger("-2147483649", false, &err));
    assert( 1 == convertStringToInteger("1e30", false, &err));
    assert( 0 == convertStringToInteger("-0", false, &err));
    assert( 2147483647 == convertStringToInteger("10000000000", false, &err));
}


/// C-locale independent string to float parsing.
/// Params:
///     s = Must be a zero-terminated string.
///     mustConsumeEntireInput = if true, check that s is entirely consumed by parsing the number.
///     err = optional bool
public double convertStringToDouble(const(char)* s, 
                                    bool mustConsumeEntireInput,
                                    bool* err) pure nothrow @nogc
{
    if (s is null)
    {
        if (err) *err = true;
        return 0.0;
    }

    const(char)* end;
    bool strtod_err = false;
    double r = stb__clex_parse_number_literal(s, &end, &strtod_err, true);

    if (strtod_err)
    {
        if (err) *err = true;
        return 0.0;
    }

    if (mustConsumeEntireInput)
    {
        size_t len = strlen(s);
        if (end != s + len)
        {
            if (err) *err = true; // did not consume whole string
            return 0.0;
        }
    }

    if (err) *err = false; // no error
    return r;
}
unittest
{
    //import core.stdc.stdio;
    import std.math.operations;

    string[9] s = ["14", "0x123", "+0x1.921fb54442d18p+0001", "0", "-0.0", "   \n\t\n\f\r 0.65", "1.64587", "-1.0e+9", "1.1454e-25"]; 
    double[9] correct = [14, 0x123, +0x1.921fb54442d18p+0001, 0.0, -0.0, 0.65L, 1.64587, -1e9, 1.1454e-25f];

    string[9] sPartial = ["14top", "0x123lol", "+0x1.921fb54442d18p+0001()", "0,", "-0.0,,,,", "   \n\t\n\f\r 0.65,stuff", "1.64587okokok", "-1.0e+9HELLO", "1.1454e-25f#STUFF"]; 
    for (int n = 0; n < s.length; ++n)
    {
        /*
        // Check vs scanf
        double sa;
        if (sscanf(s[n].ptr, "%lf", &sa) == 1)
        {
        debug printf("scanf finds %lg\n", sa);
        }
        else
        debug printf("scanf no parse\n");
        */

        bool err;
        double a = convertStringToDouble(s[n].ptr, true, &err);
        //import std.stdio;
        //debug writeln(a, " correct is ", correct[n]);
        assert(!err);
        assert( isClose(a, correct[n], 0.0001) );

        bool err2;
        double b = convertStringToDouble(s[n].ptr, false, &err2);
        assert(!err2);
        assert(b == a); // same parse

        //debug printf("%lf\n", a);

        convertStringToDouble(s[n].ptr, true, null); // should run without error pointer
    }
}

private double stb__clex_parse_number_literal(const(char)* p, 
                                              const(char)**q, 
                                              bool* err,
                                              bool allowFloat) pure nothrow @nogc
{
    const(char)* s = p;
    double value=0;
    int base=10;
    int exponent=0;
    int signMantissa = 1;

    // Skip leading whitespace, like scanf and strtod do
    while (true)
    {
        char ch = *p;
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\f' || ch == '\r')
        {
            p += 1;
        }
        else
            break;
    }


    if (*p == '-') 
    {
        signMantissa = -1;
        p += 1;
    } 
    else if (*p == '+') 
    {
        p += 1;
    }

    if (*p == '0') 
    {
        if (p[1] == 'x' || p[1] == 'X') 
        {
            base=16;
            p += 2;
        }
    }

    for (;;) 
    {
        if (*p >= '0' && *p <= '9')
            value = value*base + (*p++ - '0');
        else if (base == 16 && *p >= 'a' && *p <= 'f')
            value = value*base + 10 + (*p++ - 'a');
        else if (base == 16 && *p >= 'A' && *p <= 'F')
            value = value*base + 10 + (*p++ - 'A');
        else
            break;
    }

    if (allowFloat)
    {
        if (*p == '.') 
        {
            double pow, addend = 0;
            ++p;
            for (pow=1; ; pow*=base) 
            {
                if (*p >= '0' && *p <= '9')
                    addend = addend*base + (*p++ - '0');
                else if (base == 16 && *p >= 'a' && *p <= 'f')
                    addend = addend*base + 10 + (*p++ - 'a');
                else if (base == 16 && *p >= 'A' && *p <= 'F')
                    addend = addend*base + 10 + (*p++ - 'A');
                else
                    break;
            }
            value += addend / pow;
        }
        if (base == 16) {
            // exponent required for hex float literal, else it's an integer literal like 0x123
            exponent = (*p == 'p' || *p == 'P');
        } else
            exponent = (*p == 'e' || *p == 'E');

        if (exponent) 
        {
            int sign = p[1] == '-';
            uint exponent2 = 0;
            double power=1;
            ++p;
            if (*p == '-' || *p == '+')
                ++p;
            while (*p >= '0' && *p <= '9')
                exponent2 = exponent2*10 + (*p++ - '0');

            if (base == 16)
                power = stb__clex_pow(2, exponent2);
            else
                power = stb__clex_pow(10, exponent2);
            if (sign)
                value /= power;
            else
                value *= power;
        }
    }

    if (q) *q = p;
    if (err) *err = false; // seen no error

    if (signMantissa < 0)
        value = -value;

    if (!allowFloat)
    {
        // clamp and round to nearest integer
        if (value > int.max) value = int.max;
        if (value < int.min) value = int.min;
    }    
    return value;
}

private double stb__clex_pow(double base, uint exponent) pure nothrow @nogc
{
    double value=1;
    for ( ; exponent; exponent >>= 1) {
        if (exponent & 1)
            value *= base;
        base *= base;
    }
    return value;
}
