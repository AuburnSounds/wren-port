module wren.utils;

// We need buffers of a few different types.
// No pre-processor here :)
string DECLARE_BUFFER(string name, string type) {
    import std.format;
    return format!q"{
    struct %1$sBuffer {
        %2$s* data;
        int count;
        int capacity;
    };

    void wren%1$sBufferInit(%1$sBuffer* buffer) @nogc {
        buffer.data = null;
        buffer.capacity = 0;
        buffer.count = 0;
    }

    void wren%1$sBufferClear(VM)(VM* vm, %1$sBuffer* buffer) @nogc {
        wrenReallocate(vm, buffer.data, 0, 0);
        wren%1$sBufferInit(buffer);
    }

    void wren%1$sBufferFill(VM)(VM* vm, %1$sBuffer* buffer, %2$s data, int count) @nogc {
        if (buffer.capacity < buffer.count + count) {
            int capacity = wrenPowerOf2Ceil(buffer.count + count);
            buffer.data = cast(%2$s*)wrenReallocate(vm, buffer.data, 
                buffer.capacity * (%2$s).sizeof, capacity * (%2$s).sizeof);
            buffer.capacity = capacity;
        }

        for (int i = 0; i < count; i++) {
            buffer.data[buffer.count++] = data;
        }
    }

    void wren%1$sBufferWrite(VM)(VM* vm, %1$sBuffer* buffer, %2$s data) @nogc {
        wren%1$sBufferFill(vm, buffer, data, 1);
    }
    }"(name, type);
}

mixin(DECLARE_BUFFER("Byte", "ubyte"));
mixin(DECLARE_BUFFER("Int", "int"));

import wren.value : StringBuffer, wrenStringBufferInit, wrenStringBufferClear;
alias SymbolTable = StringBuffer;

// Initializes the symbol table.
void wrenSymbolTableInit(SymbolTable* symbols) @nogc
{
    wrenStringBufferInit(symbols);
}

// Frees all dynamically allocated memory used by the symbol table, but not the
// SymbolTable itself.
void wrenSymbolTableClear(VM)(VM* vm, SymbolTable* symbols) @nogc
{
    wrenStringBufferClear(vm, symbols);
}

// Adds name to the symbol table. Returns the index of it in the table.
int wrenSymbolTableAdd(VM)(VM* vm, SymbolTable* symbols,
                       const(char)* name, size_t length) @nogc
{
    assert(0, "Stub");
/*
  ObjString* symbol = AS_STRING(wrenNewStringLength(vm, name, length));
  
  wrenPushRoot(vm, &symbol->obj);
  wrenStringBufferWrite(vm, symbols, symbol);
  wrenPopRoot(vm);
  
  return symbols->count - 1;
  */
}

// Adds name to the symbol table. Returns the index of it in the table. Will
// use an existing symbol if already present.
int wrenSymbolTableEnsure(VM)(VM* vm, SymbolTable* symbols,
                          const(char)* name, size_t length) @nogc
{
    assert(0, "stub");
}

// Looks up name in the symbol table. Returns its index if found or -1 if not.
int wrenSymbolTableFind(const SymbolTable* symbols,
                        const(char)* name, size_t length) @nogc
{
    assert(0, "Stub");
}

void wrenBlackenSymbolTable(VM)(VM* vm, SymbolTable* symbolTable) @nogc
{
    assert(0, "Stub");
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
int wrenPowerOf2Ceil(int n) @nogc
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