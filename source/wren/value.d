module wren.value;
import wren.common;
import wren.math;
import wren.utils;

@nogc:
// This defines the built-in types and their core representations in memory.
// Since Wren is dynamically typed, any variable can hold a value of any type,
// and the type can change at runtime. Implementing this efficiently is
// critical for performance.
//
// The main type exposed by this is [Value]. A C variable of that type is a
// storage location that can hold any Wren value. The stack, module variables,
// and instance fields are all implemented in C as variables of type Value.
//
// The built-in types for booleans, numbers, and null are unboxed: their value
// is stored directly in the Value, and copying a Value copies the value. Other
// types--classes, instances of classes, functions, lists, and strings--are all
// reference types. They are stored on the heap and the Value just stores a
// pointer to it. Copying the Value copies a reference to the same object. The
// Wren implementation calls these "Obj", or objects, though to a user, all
// values are objects.
//
// There is also a special singleton value "undefined". It is used internally
// but never appears as a real value to a user. It has two uses:
//
// - It is used to identify module variables that have been implicitly declared
//   by use in a forward reference but not yet explicitly declared. These only
//   exist during compilation and do not appear at runtime.
//
// - It is used to represent unused map entries in an ObjMap.
//
// There are two supported Value representations. The main one uses a technique
// called "NaN tagging" (explained in detail below) to store a number, any of
// the value types, or a pointer, all inside one double-precision floating
// point number. A larger, slower, Value type that uses a struct to store these
// is also supported, and is useful for debugging the VM.
//
// The representation is controlled by the `WREN_NAN_TAGGING` define. If that's
// defined, Nan tagging is used.

// Identifies which specific type a heap-allocated object is.
enum ObjType {
  OBJ_CLASS,
  OBJ_CLOSURE,
  OBJ_FIBER,
  OBJ_FN,
  OBJ_FOREIGN,
  OBJ_INSTANCE,
  OBJ_LIST,
  OBJ_MAP,
  OBJ_MODULE,
  OBJ_RANGE,
  OBJ_STRING,
  OBJ_UPVALUE
}

// Base struct for all heap-allocated objects.
struct Obj
{
    ObjType type;
    bool isDark;

    // The object's class.
    ObjClass* classObj;

    // The next object in the linked list of all currently allocated objects.
    Obj* next;
} 

static if (WREN_NAN_TAGGING)
{
    alias Value = ulong;
}
else
{
    enum ValueType {
        VAL_FALSE,
        VAL_NULL,
        VAL_NUM,
        VAL_TRUE,
        VAL_UNDEFINED,
        VAL_OBJ
    }

    struct Value {
        ValueType type;
        union AsValue {
            double num;
            Obj* obj;
        }
        AsValue as;
    }
}

mixin(DECLARE_BUFFER("Value", "Value"));

// These macros cast a Value to one of the specific object types. These do *not*
// perform any validation, so must only be used after the Value has been
// ensured to be the right type.
ObjClass* AS_CLASS(Value value)
{
    return cast(ObjClass*)AS_OBJ(value);
}

ObjClosure* AS_CLOSURE(Value value)
{
    return cast(ObjClosure*)AS_OBJ(value);
}

ObjFiber* AS_FIBER(Value value)
{
    return cast(ObjFiber*)AS_OBJ(value);
}

ObjFn* AS_FN(Value value)
{
    return cast(ObjFn*)AS_OBJ(value);
}

ObjForeign* AS_FOREIGN(Value value)
{
    return cast(ObjForeign*)AS_OBJ(value);
}

ObjInstance* AS_INSTANCE(Value value)
{
    return cast(ObjInstance*)AS_OBJ(value);
}

ObjList* AS_LIST(Value value)
{
    return cast(ObjList*)AS_OBJ(value);
}

ObjMap* AS_MAP(Value value)
{
    return cast(ObjMap*)AS_OBJ(value);
}

ObjModule* AS_MODULE(Value value)
{
    return cast(ObjModule*)AS_OBJ(value);
}

double AS_NUM(Value value)
{
    return wrenValueToNum(value);
}

ObjRange* AS_RANGE(Value value)
{
    return cast(ObjRange*)AS_OBJ(value);
}

ObjString* AS_STRING(Value value)
{
    return cast(ObjString*)AS_OBJ(value);
}

const(char)* AS_CSTRING(Value value)
{
    return (AS_STRING(value).value.ptr);
}

// These macros promote a primitive C value to a full Wren Value. There are
// more defined below that are specific to the Nan tagged or other
// representation.
Value BOOL_VAL(bool value)
{
    return value ? TRUE_VAL : FALSE_VAL;
}

Value NUM_VAL(double num)
{
    return wrenNumToValue(num);
}

Value OBJ_VAL(T)(T* obj)
{
    return wrenObjectToValue(cast(Obj*)obj);
}

// These perform type tests on a Value, returning `true` if the Value is of the
// given type.
bool IS_BOOL(Value value) {
    return wrenIsBool(value);
}

bool IS_CLASS(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_CLASS);
}

bool IS_CLOSURE(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_CLOSURE);
}

bool IS_FIBER(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_FIBER);
}

bool IS_FN(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_FN);
}

bool IS_FOREIGN(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_FOREIGN);
}

bool IS_INSTANCE(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_INSTANCE);
}

bool IS_LIST(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_LIST);
}

bool IS_MAP(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_MAP);
}

bool IS_RANGE(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_RANGE);
}

bool IS_STRING(Value value) {
    return wrenIsObjType(value, ObjType.OBJ_STRING);
}

// A heap-allocated string object.
struct ObjString
{
    Obj obj;

    // Number of bytes in the string, not including the null terminator.
    uint length;

    // The hash value of the string's contents.
    uint hash;

    // Inline array of the string's bytes followed by a null terminator.
    char[] value;
}

mixin(DECLARE_BUFFER("String", "ObjString*"));

alias SymbolTable = StringBuffer;

// This import has to be here. Otherwise, we run into weird undefined identifier problems.
import wren.vm;

// Initializes the symbol table.
void wrenSymbolTableInit(SymbolTable* symbols) @nogc
{
    wrenStringBufferInit(symbols);
}

// Frees all dynamically allocated memory used by the symbol table, but not the
// SymbolTable itself.
void wrenSymbolTableClear(WrenVM* vm, SymbolTable* symbols) @nogc
{
    wrenStringBufferClear(vm, symbols);
}

// Adds name to the symbol table. Returns the index of it in the table.
int wrenSymbolTableAdd(WrenVM* vm, SymbolTable* symbols,
                       const(char)* name, size_t length) @nogc
{
    ObjString* symbol = AS_STRING(wrenNewStringLength(vm, name, length));
  
    wrenPushRoot(vm, &symbol.obj);
    wrenStringBufferWrite(vm, symbols, symbol);
    wrenPopRoot(vm);
  
    return symbols.count - 1;
}

// Adds name to the symbol table. Returns the index of it in the table. Will
// use an existing symbol if already present.
int wrenSymbolTableEnsure(WrenVM* vm, SymbolTable* symbols,
                          const(char)* name, size_t length) @nogc
{
    // See if the symbol is already defined.
    int existing = wrenSymbolTableFind(symbols, name, length);
    if (existing != -1) return existing;

    // New symbol, so add it.
    return wrenSymbolTableAdd(vm, symbols, name, length);
}

// Looks up name in the symbol table. Returns its index if found or -1 if not.
int wrenSymbolTableFind(const SymbolTable* symbols,
                        const(char)* name, size_t length) @nogc
{
    // See if the symbol is already defined.
    // TODO: O(n). Do something better.
    for (int i = 0; i < symbols.count; i++)
    {
        if (wrenStringEqualsCString(cast(ObjString*)symbols.data[i], name, length)) return i;
    }

    return -1;
}

void wrenBlackenSymbolTable(WrenVM* vm, SymbolTable* symbolTable) @nogc
{
    for (int i = 0; i < symbolTable.count; i++)
    {
        wrenGrayObj(vm, &symbolTable.data[i].obj);
    }

    // Keep track of how much memory is still in use.
    vm.bytesAllocated += symbolTable.capacity * (*symbolTable.data).sizeof;
}

// The dynamically allocated data structure for a variable that has been used
// by a closure. Whenever a function accesses a variable declared in an
// enclosing function, it will get to it through this.
//
// An upvalue can be either "closed" or "open". An open upvalue points directly
// to a [Value] that is still stored on the fiber's stack because the local
// variable is still in scope in the function where it's declared.
//
// When that local variable goes out of scope, the upvalue pointing to it will
// be closed. When that happens, the value gets copied off the stack into the
// upvalue itself. That way, it can have a longer lifetime than the stack
// variable.
struct ObjUpvalue
{
    // The object header. Note that upvalues have this because they are garbage
    // collected, but they are not first class Wren objects.
    Obj obj;

    // Pointer to the variable this upvalue is referencing.
    Value* value;

    // If the upvalue is closed (i.e. the local variable it was pointing to has
    // been popped off the stack) then the closed-over value will be hoisted out
    // of the stack into here. [value] will then be changed to point to this.
    Value closed;

    // Open upvalues are stored in a linked list by the fiber. This points to the
    // next upvalue in that list.    
    ObjUpvalue* next;
}



// TODO: See if it's actually a perf improvement to have this in a separate
// struct instead of in ObjFn.
// Stores debugging information for a function used for things like stack
// traces.
struct FnDebug
{
    // The name of the function. Heap allocated and owned by the FnDebug.
    char* name;

    // An array of line numbers. There is one element in this array for each
    // bytecode in the function's bytecode array. The value of that element is
    // the line in the source code that generated that instruction.
    IntBuffer sourceLines;
}

// A loaded module and the top-level variables it defines.
//
// While this is an Obj and is managed by the GC, it never appears as a
// first-class object in Wren.
struct ObjModule
{
    Obj obj;

    // The currently defined top-level variables.
    ValueBuffer variables;

    // Symbol table for the names of all module variables. Indexes here directly
    // correspond to entries in [variables].
    SymbolTable variableNames;

    // The name of the module.
    ObjString* name;
}

// A function object. It wraps and owns the bytecode and other debug information
// for a callable chunk of code.
//
// Function objects are not passed around and invoked directly. Instead, they
// are always referenced by an [ObjClosure] which is the real first-class
// representation of a function. This isn't strictly necessary if they function
// has no upvalues, but lets the rest of the VM assume all called objects will
// be closures.
struct ObjFn
{
    Obj obj;
    
    ByteBuffer code;
    ValueBuffer constants;
    
    // The module where this function was defined.
    ObjModule* module_;

    // The maximum number of stack slots this function may use.
    int maxSlots;
    
    // The number of upvalues this function closes over.
    int numUpvalues;
    
    // The number of parameters this function expects. Used to ensure that .call
    // handles a mismatch between number of parameters and arguments. This will
    // only be set for fns, and not ObjFns that represent methods or scripts.
    int arity;
    FnDebug* debug_;
}

// An instance of a first-class function and the environment it has closed over.
// Unlike [ObjFn], this has captured the upvalues that the function accesses.
struct ObjClosure
{
    Obj obj;

    // The function that this closure is an instance of.
    ObjFn* fn;

    // The upvalues this function has closed over.
    ObjUpvalue*[] upvalues;
}

struct CallFrame
{
    // Pointer to the current (really next-to-be-executed) instruction in the
    // function's bytecode.
    ubyte* ip;
    
    // The closure being executed.
    ObjClosure* closure;
    
    // Pointer to the first stack slot used by this call frame. This will contain
    // the receiver, followed by the function's parameters, then local variables
    // and temporaries.
    Value* stackStart;
}

// Tracks how this fiber has been invoked, aside from the ways that can be
// detected from the state of other fields in the fiber.
enum FiberState
{
    // The fiber is being run from another fiber using a call to `try()`.
    FIBER_TRY,
    
    // The fiber was directly invoked by `runInterpreter()`. This means it's the
    // initial fiber used by a call to `wrenCall()` or `wrenInterpret()`.
    FIBER_ROOT,
    
    // The fiber is invoked some other way. If [caller] is `NULL` then the fiber
    // was invoked using `call()`. If [numFrames] is zero, then the fiber has
    // finished running and is done. If [numFrames] is one and that frame's `ip`
    // points to the first byte of code, the fiber has not been started yet.
    FIBER_OTHER,
}

struct ObjFiber
{
    Obj obj;
    
    // The stack of value slots. This is used for holding local variables and
    // temporaries while the fiber is executing. It is heap-allocated and grown
    // as needed.
    Value* stack;
    
    // A pointer to one past the top-most value on the stack.
    Value* stackTop;
    
    // The number of allocated slots in the stack array.
    int stackCapacity;
    
    // The stack of call frames. This is a dynamic array that grows as needed but
    // never shrinks.
    CallFrame* frames;
    
    // The number of frames currently in use in [frames].
    int numFrames;
    
    // The number of [frames] allocated.
    int frameCapacity;
    
    // Pointer to the first node in the linked list of open upvalues that are
    // pointing to values still on the stack. The head of the list will be the
    // upvalue closest to the top of the stack, and then the list works downwards.
    ObjUpvalue* openUpvalues;
    
    // The fiber that ran this one. If this fiber is yielded, control will resume
    // to this one. May be `NULL`.
    ObjFiber* caller;
    
    // If the fiber failed because of a runtime error, this will contain the
    // error object. Otherwise, it will be null.
    Value error;
    
    FiberState state;
}

enum MethodType
{
    // A primitive method implemented in C in the VM. Unlike foreign methods,
    // this can directly manipulate the fiber's stack.
    METHOD_PRIMITIVE,

    // A primitive that handles .call on Fn.
    METHOD_FUNCTION_CALL,

    // A externally-defined C method.
    METHOD_FOREIGN,

    // A normal user-defined method.
    METHOD_BLOCK,
    
    // No method for the given symbol.
    METHOD_NONE
}

struct Method
{
    MethodType type;

    // The method function itself. The [type] determines which field of the union
    // is used.
    union AsType
    {
        Primitive primitive;
        WrenForeignMethodFn foreign;
        ObjClosure* closure;
    }

    AsType as;
}

mixin(DECLARE_BUFFER("Method", "Method"));

struct ObjClass
{
    Obj obj;
    ObjClass* superclass;

    // The number of fields needed for an instance of this class, including all
    // of its superclass fields.
    int numFields;

    // The table of methods that are defined in or inherited by this class.
    // Methods are called by symbol, and the symbol directly maps to an index in
    // this table. This makes method calls fast at the expense of empty cells in
    // the list for methods the class doesn't support.
    //
    // You can think of it as a hash table that never has collisions but has a
    // really low load factor. Since methods are pretty small (just a type and a
    // pointer), this should be a worthwhile trade-off.
    MethodBuffer methods;

    // The name of the class.
    ObjString* name;
    
    // The ClassAttribute for the class, if any
    Value attributes;
}

struct ObjForeign
{
    Obj obj;
    ubyte[] data;
}

struct ObjInstance
{
    Obj obj;
    Value[] fields;
}

struct ObjList
{
    Obj obj;
    
    // The elements in the list.
    ValueBuffer elements;
}

struct MapEntry
{
    // The entry's key, or UNDEFINED_VAL if the entry is not in use.
    Value key;

    // The value associated with the key. If the key is UNDEFINED_VAL, this will
    // be false to indicate an open available entry or true to indicate a
    // tombstone -- an entry that was previously in use but was then deleted.
    Value value;
}

// A hash table mapping keys to values.
//
// We use something very simple: open addressing with linear probing. The hash
// table is an array of entries. Each entry is a key-value pair. If the key is
// the special UNDEFINED_VAL, it indicates no value is currently in that slot.
// Otherwise, it's a valid key, and the value is the value associated with it.
//
// When entries are added, the array is dynamically scaled by GROW_FACTOR to
// keep the number of filled slots under MAP_LOAD_PERCENT. Likewise, if the map
// gets empty enough, it will be resized to a smaller array. When this happens,
// all existing entries are rehashed and re-added to the new array.
//
// When an entry is removed, its slot is replaced with a "tombstone". This is an
// entry whose key is UNDEFINED_VAL and whose value is TRUE_VAL. When probing
// for a key, we will continue past tombstones, because the desired key may be
// found after them if the key that was removed was part of a prior collision.
// When the array gets resized, all tombstones are discarded.
struct ObjMap
{
    Obj obj;

    // The number of entries allocated.
    uint capacity;

    // The number of entries in the map.
    uint count;

    // Pointer to a contiguous array of [capacity] entries.
    MapEntry* entries;
}

struct ObjRange
{
    Obj obj;

    // The beginning of the range.
    double from;

    // The end of the range. May be greater or less than [from].
    double to;

    // True if [to] is included in the range.
    bool isInclusive;
}

struct WrenHandle
{
  Value value;

  WrenHandle* prev;
  WrenHandle* next;
};

// An IEEE 754 double-precision float is a 64-bit value with bits laid out like:
//
// 1 Sign bit
// | 11 Exponent bits
// | |          52 Mantissa (i.e. fraction) bits
// | |          |
// S[Exponent-][Mantissa------------------------------------------]
//
// The details of how these are used to represent numbers aren't really
// relevant here as long we don't interfere with them. The important bit is NaN.
//
// An IEEE double can represent a few magical values like NaN ("not a number"),
// Infinity, and -Infinity. A NaN is any value where all exponent bits are set:
//
//  v--NaN bits
// -11111111111----------------------------------------------------
//
// Here, "-" means "doesn't matter". Any bit sequence that matches the above is
// a NaN. With all of those "-", it obvious there are a *lot* of different
// bit patterns that all mean the same thing. NaN tagging takes advantage of
// this. We'll use those available bit patterns to represent things other than
// numbers without giving up any valid numeric values.
//
// NaN values come in two flavors: "signalling" and "quiet". The former are
// intended to halt execution, while the latter just flow through arithmetic
// operations silently. We want the latter. Quiet NaNs are indicated by setting
// the highest mantissa bit:
//
//             v--Highest mantissa bit
// -[NaN      ]1---------------------------------------------------
//
// If all of the NaN bits are set, it's not a number. Otherwise, it is.
// That leaves all of the remaining bits as available for us to play with. We
// stuff a few different kinds of things here: special singleton values like
// "true", "false", and "null", and pointers to objects allocated on the heap.
// We'll use the sign bit to distinguish singleton values from pointers. If
// it's set, it's a pointer.
//
// v--Pointer or singleton?
// S[NaN      ]1---------------------------------------------------
//
// For singleton values, we just enumerate the different values. We'll use the
// low bits of the mantissa for that, and only need a few:
//
//                                                 3 Type bits--v
// 0[NaN      ]1------------------------------------------------[T]
//
// For pointers, we are left with 51 bits of mantissa to store an address.
// That's more than enough room for a 32-bit address. Even 64-bit machines
// only actually use 48 bits for addresses, so we've got plenty. We just stuff
// the address right into the mantissa.
//
// Ta-da, double precision numbers, pointers, and a bunch of singleton values,
// all stuffed into a single 64-bit sequence. Even better, we don't have to
// do any masking or work to extract number values: they are unmodified. This
// means math on numbers is fast.
static if (WREN_NAN_TAGGING)
{
    // A mask that selects the sign bit.
    enum SIGN_BIT = cast(ulong)1 << 63;

    // The bits that must be set to indicate a quiet NaN.
    enum QNAN = cast(ulong)0x7ffc000000000000;

    // If the NaN bits are set, it's not a number.
    bool IS_NUM(Value value)
    {
        return (((value) & QNAN) != QNAN);
    }

    // An object pointer is a NaN with a set sign bit.
    bool IS_OBJ(Value value)
    {
        return (((value) & (QNAN | SIGN_BIT)) == (QNAN | SIGN_BIT));
    }

    bool IS_FALSE(Value value)
    {
        return ((value) == FALSE_VAL);
    }

    bool IS_NULL(Value value)
    {
        return ((value) == NULL_VAL);
    }

    bool IS_UNDEFINED(Value value)
    {
        return ((value) == UNDEFINED_VAL);
    }

    // Masks out the tag bits used to identify the singleton value.
    enum MASK_TAG = 7;

    // Tag values for the different singleton values.
    enum TAG_NAN = 0;
    enum TAG_NULL = 1;
    enum TAG_FALSE = 2;
    enum TAG_TRUE = 3;
    enum TAG_UNDEFINED = 4;
    enum TAG_UNUSED2 = 5;
    enum TAG_UNUSED3 = 6;
    enum TAG_UNUSED4 = 7;

    // Value -> 0 or 1.
    bool AS_BOOL(Value value)
    {
        return ((value) == TRUE_VAL);
    }

    // Value -> Obj*.
    Obj* AS_OBJ(Value value)
    {
        return (cast(Obj*)cast(ulong)((value) & ~(SIGN_BIT | QNAN)));
    } 

    // Singleton values.
    enum NULL_VAL = (cast(Value)cast(ulong)(QNAN | TAG_NULL));
    enum FALSE_VAL = (cast(Value)cast(ulong)(QNAN | TAG_FALSE));
    enum TRUE_VAL = (cast(Value)cast(ulong)(QNAN | TAG_TRUE));
    enum UNDEFINED_VAL = (cast(Value)cast(ulong)(QNAN | TAG_UNDEFINED));

    int GET_TAG(Value value)
    {
        return (cast(int)((value) & MASK_TAG));
    }
}
else
{
    // Value -> 0 or 1.
    bool AS_BOOL(Value value)
    {
        return ((value).type = VAL_TRUE);
    }

    // Value -> Obj*.
    Obj* AS_OBJ(Value value)
    {
        return ((value).as.obj);
    }

    // Determines if [value] is a garbage-collected object or not.
    bool IS_OBJ(Value value)
    {
        return ((value).type == VAL_OBJ);
    }

    bool IS_FALSE(Value value)
    {
        return ((value).type == VAL_FALSE);
    }

    bool IS_NULL(Value value)
    {
        return ((value).type == VAL_NULL);
    }

    bool IS_NUM(Value value)
    {
        return ((value).type == VAL_NUM);
    }

    bool IS_UNDEFINED(Value value)
    {
        return ((value).type == VAL_UNDEFINED);
    }

    // Singleton values.
    enum FALSE_VAL = Value(ValueType.VAL_FALSE, null);
    enum NULL_VAL = Value(ValueType.VAL_NULL, null);
    enum TRUE_VAL = Value(ValueType.VAL_TRUE, null);
    enum UNDEFINED_VAL = Value(ValueType.VAL_UNDEFINED, null);
}

// Returns true if [a] and [b] are strictly the same value. This is identity
// for object values, and value equality for unboxed values.
static bool wrenValuesSame(Value a, Value b)
{
    static if (WREN_NAN_TAGGING)
    {
        return a == b;
    }
    else
    {
        if (a.type != b.type) return false;
        if (a.type == VAL_NUM) return a.as.num == b.as.num;
        return a.as.obj == b.as.obj;
    }
}

// Returns true if [value] is a bool. Do not call this directly, instead use
// [IS_BOOL].
static bool wrenIsBool(Value value)
{
    static if (WREN_NAN_TAGGING)
    {
        return value == TRUE_VAL || value == FALSE_VAL;
    }
    else
    {
        return value.type == ValueType.VAL_FALSE || value.type == ValueType.VAL_TRUE;
    }
}

// Returns true if [value] is an object of type [type]. Do not call this
// directly, instead use the [IS___] macro for the type in question.
static bool wrenIsObjType(Value value, ObjType type)
{
    return IS_OBJ(value) && AS_OBJ(value).type == type;
}

// Converts the raw object pointer [obj] to a [Value].
static Value wrenObjectToValue(Obj* obj)
{
    static if (WREN_NAN_TAGGING)
    {
        return cast(Value)(SIGN_BIT | QNAN | cast(ulong)(obj));
    }
    else
    {
        Value value;
        value.type = ValueType.VAL_OBJ;
        value.as.obj = obj;
        return value;
    }
}

// Interprets [value] as a [double].
static double wrenValueToNum(Value value)
{
    static if (WREN_NAN_TAGGING)
    {
        return wrenDoubleFromBits(value);
    }
    else
    {
        return value.as.num;
    }
}

// Converts [num] to a [Value].
static Value wrenNumToValue(double num)
{
    static if (WREN_NAN_TAGGING)
    {
        return wrenDoubleToBits(num);
    }
    else
    {
        Value value;
        value.type = ValueType.VAL_NUM;
        value.as.num = num;
        return value;
    }
}

// Validates that [arg] is a valid object for use as a map key. Returns true if
// it is and returns false otherwise. Use validateKey usually, for a runtime error.
// This separation exists to aid the API in surfacing errors to the developer as well.
static bool wrenMapIsValidKey(Value arg)
{
    return IS_BOOL(arg)
      || IS_CLASS(arg)
      || IS_NULL(arg)
      || IS_NUM(arg)
      || IS_RANGE(arg)
      || IS_STRING(arg);
}

// TODO: Tune these.
// The initial (and minimum) capacity of a non-empty list or map object.
enum MIN_CAPACITY = 16;

// The rate at which a collection's capacity grows when the size exceeds the
// current capacity. The new capacity will be determined by *multiplying* the
// old capacity by this. Growing geometrically is necessary to ensure that
// adding to a collection has O(1) amortized complexity.
enum GROW_FACTOR = 2;

// The maximum percentage of map entries that can be filled before the map is
// grown. A lower load takes more memory but reduces collisions which makes
// lookup faster.
enum MAP_LOAD_PERCENT = 75;

// The number of call frames initially allocated when a fiber is created. Making
// this smaller makes fibers use less memory (at first) but spends more time
// reallocating when the call stack grows.
enum INITIAL_CALL_FRAMES = 4;

static void initObj(WrenVM* vm, Obj* obj, ObjType type, ObjClass* classObj)
{
    obj.type = type;
    obj.isDark = false;
    obj.classObj = classObj;
    obj.next = vm.first;
    vm.first = obj;
}

// Creates a new "raw" class. It has no metaclass or superclass whatsoever.
// This is only used for bootstrapping the initial Object and Class classes,
// which are a little special.
ObjClass* wrenNewSingleClass(WrenVM* vm, int numFields, ObjString* name)
{
    ObjClass* classObj = ALLOCATE!(WrenVM, ObjClass)(vm);
    initObj(vm, &classObj.obj, ObjType.OBJ_CLASS, null);
    classObj.superclass = null;
    classObj.numFields = numFields;
    classObj.name = name;
    classObj.attributes = NULL_VAL;

    wrenPushRoot(vm, cast(Obj*)classObj);
    wrenMethodBufferInit(&classObj.methods);
    wrenPopRoot(vm);

    return classObj;
}

// Makes [superclass] the superclass of [subclass], and causes subclass to
// inherit its methods. This should be called before any methods are defined
// on subclass.
void wrenBindSuperclass(WrenVM* vm, ObjClass* subclass, ObjClass* superclass)
{
    assert(superclass != null, "Must have superclass");

    subclass.superclass = superclass;

    // Include the superclass in the total number of fields.
    if (subclass.numFields != -1)
    {
        subclass.numFields += superclass.numFields;
    }
    else
    {
        assert(superclass.numFields == 0, 
                "A foreign class cannot inherit from a class with fields.");
    }

    // Inherit methods from its superclass.
    for (int i = 0; i < superclass.methods.count; i++)
    {
        wrenBindMethod(vm, subclass, i, superclass.methods.data[i]);
    } 
}

// Creates a new class object as well as its associated metaclass.
ObjClass* wrenNewClass(WrenVM* vm, ObjClass* superclass, int numFields,
                            ObjString* name)
{
    assert(0, "Stub");
}

void wrenBindMethod(WrenVM* vm, ObjClass* classObj, int symbol, Method method)
{
    // Make sure the buffer is big enough to contain the symbol's index.
    if (symbol >= classObj.methods.count)
    {
        Method noMethod;
        noMethod.type = MethodType.METHOD_NONE;
        wrenMethodBufferFill(vm, &classObj.methods, noMethod,
                             symbol - classObj.methods.count + 1);
    }

    classObj.methods.data[symbol] = method;
}

// Creates a new closure object that invokes [fn]. Allocates room for its
// upvalues, but assumes outside code will populate it.
ObjClosure* wrenNewClosure(WrenVM* vm, ObjFn* fn)
{
    ObjClosure* closure = ALLOCATE_FLEX!(WrenVM, ObjClosure, ObjUpvalue*)(vm, fn.numUpvalues);

    initObj(vm, &closure.obj, ObjType.OBJ_CLOSURE, vm.fnClass);

    closure.fn = fn;

    // Clear the upvalue array. We need to do this in case a GC is triggered
    // after the closure is created but before the upvalue array is populated.
    for (int i = 0; i < fn.numUpvalues; i++) closure.upvalues[i] = null;

    return closure; 
}

// Adds a new [CallFrame] to [fiber] invoking [closure] whose stack starts at
// [stackStart].
void wrenAppendCallFrame(WrenVM* vm, ObjFiber* fiber, ObjClosure* closure, Value* stackStart)
{
    assert(fiber.frameCapacity > fiber.numFrames, "No memory for call frame");

    CallFrame* frame = &fiber.frames[fiber.numFrames++];
    frame.stackStart = stackStart;
    frame.closure = closure;
    frame.ip = closure.fn.code.data;
}

// Creates a new fiber object that will invoke [closure].
ObjFiber* wrenNewFiber(WrenVM* vm, ObjClosure* closure)
{
    // Allocate the arrays before the fiber in case it triggers a GC.
    CallFrame* frames = ALLOCATE_ARRAY!(WrenVM, CallFrame)(vm, INITIAL_CALL_FRAMES);

    // Add one slot for the unused implicit receiver slot that the compiler
    // assumes all functions have.
    int stackCapacity = closure == null 
        ? 1
        : wrenPowerOf2Ceil(closure.fn.maxSlots + 1);
    Value* stack = ALLOCATE_ARRAY!(WrenVM, Value)(vm, stackCapacity);

    ObjFiber* fiber = ALLOCATE!(WrenVM, ObjFiber)(vm);
    initObj(vm, &fiber.obj, ObjType.OBJ_FIBER, vm.fiberClass);

    fiber.stack = stack;
    fiber.stackTop = fiber.stack;
    fiber.stackCapacity = stackCapacity;

    fiber.frames = frames;
    fiber.frameCapacity = INITIAL_CALL_FRAMES;
    fiber.numFrames = 0;

    fiber.openUpvalues = null;
    fiber.caller = null;
    fiber.error = NULL_VAL;
    fiber.state = FiberState.FIBER_OTHER;

    if (closure != null)
    {
        // Initialize the first call frame.
        wrenAppendCallFrame(vm, fiber, closure, fiber.stack);

        // The first slot always holds the closure.
        fiber.stackTop[0] = OBJ_VAL(closure);
        fiber.stackTop++;
    }

    return fiber;
}

// Ensures [fiber]'s stack has at least [needed] slots.
void wrenEnsureStack(WrenVM* vm, ObjFiber* fiber, int needed)
{
    if (fiber.stackCapacity >= needed) return;

    int capacity = wrenPowerOf2Ceil(needed);

    Value* oldStack = fiber.stack;
    fiber.stack = cast(Value*)wrenReallocate(vm, fiber.stack,
                                             Value.sizeof * fiber.stackCapacity,
                                             Value.sizeof * capacity);
    fiber.stackCapacity = capacity;

    // If the reallocation moves the stack, then we need to recalculate every
    // pointer that points into the old stack to into the same relative distance
    // in the new stack. We have to be a little careful about how these are
    // calculated because pointer subtraction is only well-defined within a
    // single array, hence the slightly redundant-looking arithmetic below.
    if (fiber.stack != oldStack)
    {
        // Top of the stack.
        if (vm.apiStack >= oldStack && vm.apiStack <= fiber.stackTop)
        {
            vm.apiStack = fiber.stack + (vm.apiStack - oldStack);
        }

        // Stack pointer for each call frame.
        for (int i = 0; i < fiber.numFrames; i++)
        {
            CallFrame* frame = &fiber.frames[i];
            frame.stackStart = fiber.stack + (frame.stackStart - oldStack);
        }

        // Open upvalues.
        for (ObjUpvalue* upvalue = fiber.openUpvalues;
             upvalue != null;
             upvalue = upvalue.next)
        {
            upvalue.value = fiber.stack + (upvalue.value - oldStack);
        }

        fiber.stackTop = fiber.stack + (fiber.stackTop - oldStack);
    }
}

static bool wrenHasError(ObjFiber* fiber)
{
    return !IS_NULL(fiber.error);
}

ObjForeign* wrenNewForeign(WrenVM* vm, ObjClass* classObj, size_t size)
{
    import core.stdc.string : memset;
    ObjForeign* object = ALLOCATE_FLEX!(WrenVM, ObjForeign, ubyte)(vm, size);
    initObj(vm, &object.obj, ObjType.OBJ_FOREIGN, classObj);

    // Zero out the bytes.
    memset(object.data.ptr, 0, size);
    return object;
}

// Creates a new empty function. Before being used, it must have code,
// constants, etc. added to it.
ObjFn* wrenNewFunction(WrenVM* vm, ObjModule* module_, int maxSlots)
{
    FnDebug* debug_ = ALLOCATE!(WrenVM, FnDebug)(vm);
    debug_.name = null;
    wrenIntBufferInit(&debug_.sourceLines);

    ObjFn* fn = ALLOCATE!(WrenVM, ObjFn)(vm);
    initObj(vm, &fn.obj, ObjType.OBJ_FN, vm.fnClass);

    wrenValueBufferInit(&fn.constants);
    wrenByteBufferInit(&fn.code);
    fn.module_ = module_;
    fn.maxSlots = maxSlots;
    fn.numUpvalues = 0;
    fn.arity = 0;
    fn.debug_ = debug_;

    return fn;
}

void wrenFunctionBindName(WrenVM* vm, ObjFn* fn, const(char)* name, int length)
{
    import core.stdc.string : memcpy;
    fn.debug_.name = ALLOCATE_ARRAY!(WrenVM, char)(vm, length + 1);
    memcpy(fn.debug_.name, name, length);
    fn.debug_.name[length] = '\0';
}

// Creates a new instance of the given [classObj].
Value wrenNewInstance(WrenVM* vm, ObjClass* classObj)
{
    ObjInstance* instance = ALLOCATE_FLEX!(WrenVM, ObjInstance, Value)(vm, classObj.numFields);
    initObj(vm, &instance.obj, ObjType.OBJ_INSTANCE, classObj);

    // Initialize fields to null.
    for (int i = 0; i < classObj.numFields; i++)
    {
        instance.fields[i] = NULL_VAL;
    }

    return OBJ_VAL(instance);
}

// Creates a new list with [numElements] elements (which are left
// uninitialized.)
ObjList* wrenNewList(WrenVM* vm, uint numElements)
{
    // Allocate this before the list object in case it triggers a GC which would
    // free the list.
    Value* elements = null;
    if (numElements > 0)
    {
        elements = ALLOCATE_ARRAY!(WrenVM, Value)(vm, numElements);
    }

    ObjList* list = ALLOCATE!(WrenVM, ObjList)(vm);
    initObj(vm, &list.obj, ObjType.OBJ_LIST, vm.listClass);
    list.elements.capacity = numElements;
    list.elements.count = numElements;
    list.elements.data = elements;
    return list;
}

// Inserts [value] in [list] at [index], shifting down the other elements.
void wrenListInsert(WrenVM* vm, ObjList* list, Value value, uint index)
{
    if (IS_OBJ(value)) wrenPushRoot(vm, AS_OBJ(value));

    // Add a slot at the end of the list.
    wrenValueBufferWrite(vm, &list.elements, NULL_VAL);

    if (IS_OBJ(value)) wrenPopRoot(vm);

    // Shift the existing elements down.
    for (uint i = list.elements.count - 1; i > index; i--)
    {
        list.elements.data[i] = list.elements.data[i - 1];
    }

    // Store the new element.
    list.elements.data[index] = value;
}

// Searches for [value] in [list], returns the index or -1 if not found.
int wrenListIndexOf(WrenVM* vm, ObjList* list, Value value)
{
    int count = list.elements.count;
    for (int i = 0; i < count; i++)
    {
        Value item = list.elements.data[i];
        if(wrenValuesEqual(item, value)) {
            return i;
        }
    }
    return -1;
}

Value wrenListRemoveAt(WrenVM* vm, ObjList* list, uint index)
{
    Value removed = list.elements.data[index];

    if (IS_OBJ(removed)) wrenPushRoot(vm, AS_OBJ(removed));

    // Shift items up.
    for (int i = index; i < list.elements.count - 1; i++)
    {
        list.elements.data[i] = list.elements.data[i + 1];
    }

    // If we have too much excess capacity, shrink it.
    if (list.elements.capacity / GROW_FACTOR >= list.elements.count)
    {
        list.elements.data = cast(Value*)wrenReallocate(vm, list.elements.data,
            Value.sizeof * list.elements.capacity,
            Value.sizeof * (list.elements.capacity / GROW_FACTOR));
        list.elements.capacity /= GROW_FACTOR;
    }

    if (IS_OBJ(removed)) wrenPopRoot(vm);

    list.elements.count--;
    return removed;
}

// Creates a new empty map.
ObjMap* wrenNewMap(WrenVM* vm)
{
    ObjMap* map = ALLOCATE!(WrenVM, ObjMap)(vm);
    initObj(vm, &map.obj, ObjType.OBJ_MAP, vm.mapClass);
    map.capacity = 0;
    map.count = 0;
    map.entries = null;
    return map;
}

static uint hashBits(ulong hash)
{
    // From v8's ComputeLongHash() which in turn cites:
    // Thomas Wang, Integer Hash Functions.
    // http://www.concentric.net/~Ttwang/tech/inthash.htm
    hash = ~hash + (hash << 18);  // hash = (hash << 18) - hash - 1;
    hash = hash ^ (hash >> 31);
    hash = hash * 21;  // hash = (hash + (hash << 2)) + (hash << 4);
    hash = hash ^ (hash >> 11);
    hash = hash + (hash << 6);
    hash = hash ^ (hash >> 22);
    return cast(uint)(hash & 0x3fffffff);
}

// Generates a hash code for [num].
static uint hashNumber(double num)
{
    // Hash the raw bits of the value.
    return hashBits(wrenDoubleToBits(num));
}

// Generates a hash code for [object].
static uint hashObject(Obj* object)
{
    switch (object.type)
    {
        case ObjType.OBJ_CLASS:
            // Classes just use their name.
            return hashObject(cast(Obj*)(cast(ObjClass*)object).name);
        
        // Allow bare (non-closure) functions so that we can use a map to find
        // existing constants in a function's constant table. This is only used
        // internally. Since user code never sees a non-closure function, they
        // cannot use them as map keys.
        case ObjType.OBJ_FN:
        {
            ObjFn* fn = cast(ObjFn*)object;
            return hashNumber(fn.arity) ^ hashNumber(fn.code.count);
        }

        case ObjType.OBJ_RANGE:
        {
            ObjRange* range = cast(ObjRange*)object;
            return hashNumber(range.from) ^ hashNumber(range.to);
        }

        case ObjType.OBJ_STRING:
            return (cast(ObjString*)object).hash;

        default:
            assert(false, "Only immutable objects can be hashed.");
    }
}

// Generates a hash code for [value], which must be one of the built-in
// immutable types: null, bool, class, num, range, or string.
static uint hashValue(Value value)
{
    // TODO: We'll probably want to randomize this at some point.
    static if (WREN_NAN_TAGGING)
    {
        if (IS_OBJ(value)) return hashObject(AS_OBJ(value));

        // Hash the raw bits of the unboxed value.
        return hashBits(value);
    }
    else
    {
        switch (value.type)
        {
            case VAL_FALSE: return 0;
            case VAL_NULL:  return 1;
            case VAL_NUM:   return hashNumber(AS_NUM(value));
            case VAL_TRUE:  return 2;
            case VAL_OBJ:   return hashObject(AS_OBJ(value));
            default:        assert(0, "Unreachable?");
        }
  
        return 0;
    }
}

// Looks for an entry with [key] in an array of [capacity] [entries].
//
// If found, sets [result] to point to it and returns `true`. Otherwise,
// returns `false` and points [result] to the entry where the key/value pair
// should be inserted.
static bool findEntry(MapEntry* entries, uint capacity, Value key,
                      MapEntry** result)
{
    // If there is no entry array (an empty map), we definitely won't find it.
    if (capacity == 0) return false;
    
    // Figure out where to insert it in the table. Use open addressing and
    // basic linear probing.
    uint startIndex = hashValue(key) % capacity;
    uint index = startIndex;
    
    // If we pass a tombstone and don't end up finding the key, its entry will
    // be re-used for the insert.
    MapEntry* tombstone = null;
    
    // Walk the probe sequence until we've tried every slot.
    do
    {
        MapEntry* entry = &entries[index];
        
        if (IS_UNDEFINED(entry.key))
        {
        // If we found an empty slot, the key is not in the table. If we found a
        // slot that contains a deleted key, we have to keep looking.
        if (IS_FALSE(entry.value))
        {
            // We found an empty slot, so we've reached the end of the probe
            // sequence without finding the key. If we passed a tombstone, then
            // that's where we should insert the item, otherwise, put it here at
            // the end of the sequence.
            *result = tombstone != null ? tombstone : entry;
            return false;
        }
        else
        {
            // We found a tombstone. We need to keep looking in case the key is
            // after it, but we'll use this entry as the insertion point if the
            // key ends up not being found.
            if (tombstone == null) tombstone = entry;
        }
        }
        else if (wrenValuesEqual(entry.key, key))
        {
        // We found the key.
        *result = entry;
        return true;
        }
        
        // Try the next slot.
        index = (index + 1) % capacity;
    }
    while (index != startIndex);
    
    // If we get here, the table is full of tombstones. Return the first one we
    // found.
    assert(tombstone != null, "Map should have tombstones or empty entries.");
    *result = tombstone;
    return false;
}

// Inserts [key] and [value] in the array of [entries] with the given
// [capacity].
//
// Returns `true` if this is the first time [key] was added to the map.
static bool insertEntry(MapEntry* entries, uint capacity,
                        Value key, Value value)
{
    assert(entries != null, "Should ensure capacity before inserting.");
    
    MapEntry* entry;
    if (findEntry(entries, capacity, key, &entry))
    {
        // Already present, so just replace the value.
        entry.value = value;
        return false;
    }
    else
    {
        entry.key = key;
        entry.value = value;
        return true;
    }
}

// Updates [map]'s entry array to [capacity].
static void resizeMap(WrenVM* vm, ObjMap* map, uint capacity)
{
    // Create the new empty hash table.
    MapEntry* entries = ALLOCATE_ARRAY!(WrenVM, MapEntry)(vm, capacity);
    for (uint i = 0; i < capacity; i++)
    {
        entries[i].key = UNDEFINED_VAL;
        entries[i].value = FALSE_VAL;
    }

    // Re-add the existing entries.
    if (map.capacity > 0)
    {
        for (uint i = 0; i < map.capacity; i++)
        {
        MapEntry* entry = &map.entries[i];
        
        // Don't copy empty entries or tombstones.
        if (IS_UNDEFINED(entry.key)) continue;

        insertEntry(entries, capacity, entry.key, entry.value);
        }
    }

    // Replace the array.
    DEALLOCATE(vm, map.entries);
    map.entries = entries;
    map.capacity = capacity;
}

// Looks up [key] in [map]. If found, returns the value. Otherwise, returns
// `UNDEFINED_VAL`.
Value wrenMapGet(ObjMap* map, Value key)
{
    MapEntry* entry;
    if (findEntry(map.entries, map.capacity, key, &entry)) return entry.value;

    return UNDEFINED_VAL;
}

// Associates [key] with [value] in [map].
void wrenMapSet(WrenVM* vm, ObjMap* map, Value key, Value value)
{
    // If the map is getting too full, make room first.
    if (map.count + 1 > map.capacity * MAP_LOAD_PERCENT / 100)
    {
        // Figure out the new hash table size.
        uint capacity = map.capacity * GROW_FACTOR;
        if (capacity < MIN_CAPACITY) capacity = MIN_CAPACITY;

        resizeMap(vm, map, capacity);
    }

    if (insertEntry(map.entries, map.capacity, key, value))
    {
        // A new key was added.
        map.count++;
    }
}

void wrenMapClear(WrenVM* vm, ObjMap* map)
{
    DEALLOCATE(vm, map.entries);
    map.entries = null;
    map.capacity = 0;
    map.count = 0;
}

// Removes [key] from [map], if present. Returns the value for the key if found
// or `NULL_VAL` otherwise.
Value wrenMapRemoveKey(WrenVM* vm, ObjMap* map, Value key)
{
    MapEntry* entry;
    if (!findEntry(map.entries, map.capacity, key, &entry)) return NULL_VAL;

    // Remove the entry from the map. Set this value to true, which marks it as a
    // deleted slot. When searching for a key, we will stop on empty slots, but
    // continue past deleted slots.
    Value value = entry.value;
    entry.key = UNDEFINED_VAL;
    entry.value = TRUE_VAL;

    if (IS_OBJ(value)) wrenPushRoot(vm, AS_OBJ(value));

    map.count--;

    if (map.count == 0)
    {
        // Removed the last item, so free the array.
        wrenMapClear(vm, map);
    }
    else if (map.capacity > MIN_CAPACITY &&
            map.count < map.capacity / GROW_FACTOR * MAP_LOAD_PERCENT / 100)
    {
        uint capacity = map.capacity / GROW_FACTOR;
        if (capacity < MIN_CAPACITY) capacity = MIN_CAPACITY;

        // The map is getting empty, so shrink the entry array back down.
        // TODO: Should we do this less aggressively than we grow?
        resizeMap(vm, map, capacity);
    }

    if (IS_OBJ(value)) wrenPopRoot(vm);
    return value;
}

// Creates a new module.
ObjModule* wrenNewModule(WrenVM* vm, ObjString* name)
{
  ObjModule* module_ = ALLOCATE!(WrenVM, ObjModule)(vm);

  // Modules are never used as first-class objects, so don't need a class.
  initObj(vm, cast(Obj*)module_, ObjType.OBJ_MODULE, null);

  wrenPushRoot(vm, cast(Obj*)module_);

  wrenSymbolTableInit(&module_.variableNames);
  wrenValueBufferInit(&module_.variables);

  module_.name = name;

  wrenPopRoot(vm);
  return module_;
}

// Creates a new range from [from] to [to].
Value wrenNewRange(WrenVM* vm, double from, double to, bool isInclusive)
{
  ObjRange* range = ALLOCATE!(WrenVM, ObjRange)(vm);
  initObj(vm, &range.obj, ObjType.OBJ_RANGE, vm.rangeClass);
  range.from = from;
  range.to = to;
  range.isInclusive = isInclusive;

  return OBJ_VAL(range);
}

// Creates a new string object with a null-terminated buffer large enough to
// hold a string of [length] but does not fill in the bytes.
//
// The caller is expected to fill in the buffer and then calculate the string's
// hash.
static ObjString* allocateString(WrenVM* vm, size_t length)
{
    ObjString* str = ALLOCATE_FLEX!(WrenVM, ObjString, char)(vm, length + 1);
    initObj(vm, &str.obj, ObjType.OBJ_STRING, vm.stringClass);
    str.length = cast(int)length;
    str.value[length] = '\0';

    return str;
}

static void hashString(ObjString* str)
{
    // FNV-1a hash. See: http://www.isthe.com/chongo/tech/comp/fnv/
    uint hash = 2166136261u;

    // This is O(n) on the length of the string, but we only call this when a new
    // string is created. Since the creation is also O(n) (to copy/initialize all
    // the bytes), we allow this here.
    for (uint i = 0; i < str.length; i++)
    {
        hash ^= str.value[i];
        hash *= 16777619;
    }

    str.hash = hash;
}

// Creates a new string object and copies [text] into it.
//
// [text] must be non-NULL.
Value wrenNewString(WrenVM* vm, const(char)* text)
{
    import core.stdc.string : strlen;
    return wrenNewStringLength(vm, text, strlen(text));
}

// Creates a new string object of [length] and copies [text] into it.
//
// [text] may be NULL if [length] is zero.
Value wrenNewStringLength(WrenVM* vm, const(char)* text, size_t length)
{
    import core.stdc.string : memcpy;
    // Allow NULL if the string is empty since byte buffers don't allocate any
    // characters for a zero-length string.
    assert(length == 0 || text != null, "Unexpected null string.");

    ObjString* str = allocateString(vm, length);

    // Copy the string (if given one).
    if (length > 0 && text != null) memcpy(str.value.ptr, text, length);

    hashString(str);
    return OBJ_VAL(str);
}

// Creates a new string object from [text], which should be a bare C string
// literal. This determines the length of the string automatically at compile
// time based on the size of the character array (-1 for the terminating '\0').
Value CONST_STRING(WrenVM* vm, const(char)[] text)
{
    return wrenNewStringLength(vm, text.ptr, text.length);
}

// Creates a new string object by taking a range of characters from [source].
// The range starts at [start], contains [count] bytes, and increments by
// [step].
Value wrenNewStringFromRange(WrenVM* vm, ObjString* source, int start,
                                 uint count, int step)
{
    ubyte* from = cast(ubyte*)source.value;
    int length = 0;
    for (uint i = 0; i < count; i++)
    {
        length += wrenUtf8DecodeNumBytes(from[start + i * step]);
    }

    ObjString* result = allocateString(vm, length);
    result.value[length] = '\0';

    ubyte* to = cast(ubyte*)result.value;
    for (uint i = 0; i < count; i++)
    {
        int index = start + i * step;
        int codePoint = wrenUtf8Decode(from + index, source.length - index);

        if (codePoint != -1)
        {
            to += wrenUtf8Encode(codePoint, to);
        }
    }

    hashString(result);
    return OBJ_VAL(result);
}

// Produces a string representation of [value].
Value wrenNumToString(WrenVM* vm, double value)
{
    import std.math : isNaN, isInfinity;
    import core.stdc.stdio : sprintf;
    if (isNaN(value))
    {
        return CONST_STRING(vm, "nan");
    }

    if (isInfinity(value))
    {
        if (value > 0.0)
        {
            return CONST_STRING(vm, "infinity");
        }
        else
        {
            return CONST_STRING(vm, "-infinity");
        }
    }

    // This is large enough to hold any double converted to a string using
    // "%.14g". Example:
    //
    //     -1.12345678901234e-1022
    //
    // So we have:
    //
    // + 1 char for sign
    // + 1 char for digit
    // + 1 char for "."
    // + 14 chars for decimal digits
    // + 1 char for "e"
    // + 1 char for "-" or "+"
    // + 4 chars for exponent
    // + 1 char for "\0"
    // = 24
    char[24] buffer;
    int length = sprintf(buffer.ptr, "%.14g", value);
    return wrenNewStringLength(vm, buffer.ptr, length);
}

// Creates a new string containing the UTF-8 encoding of [value].
Value wrenStringFromCodePoint(WrenVM* vm, int value)
{
    int length = wrenUtf8EncodeNumBytes(value);
    assert(length != 0, "Value out of range");

    ObjString* str = allocateString(vm, length);

    wrenUtf8Encode(value, cast(ubyte*)str.value);
    hashString(str);

    return OBJ_VAL(str);
}

// Creates a new string from the integer representation of a byte
Value wrenStringFromByte(WrenVM *vm, ubyte value)
{
    int length = 1;
    ObjString* str = allocateString(vm, length);
    str.value[0] = value;
    hashString(str);
    return OBJ_VAL(str);
}

// Creates a new formatted string from [format] and any additional arguments
// used in the format string.
//
// This is a very restricted flavor of formatting, intended only for internal
// use by the VM. Two formatting characters are supported, each of which reads
// the next argument as a certain type:
//
// $ - A C string.
// @ - A Wren string object.
Value wrenStringFormat(WrenVM* vm, const char* format, ...)
{
    import core.stdc.stdarg;
    import core.stdc.string : strlen, memcpy;
    va_list argList;

    // Calculate the length of the result string. Do this up front so we can
    // create the final string with a single allocation.
    va_start(argList, format);
    size_t totalLength = 0;
    for (const(char)* c = format; *c != '\0'; c++)
    {
        switch (*c)
        {
        case '$':
            totalLength += strlen(va_arg!(const(char*))(argList));
            break;

        case '@':
            totalLength += AS_STRING(va_arg!(Value)(argList)).length;
            break;

        default:
            // Any other character is interpreted literally.
            totalLength++;
        }
    }
    va_end(argList);

    // Concatenate the string.
    ObjString* result = allocateString(vm, totalLength);

    va_start(argList, format);
    char* start = result.value.ptr;
    for (const(char)* c = format; *c != '\0'; c++)
    {
        switch (*c)
        {
        case '$':
        {
            const char* str = va_arg!(const(char)*)(argList);
            size_t length = strlen(str);
            memcpy(start, str, length);
            start += length;
            break;
        }

        case '@':
        {
            ObjString* str = AS_STRING(va_arg!(Value)(argList));
            memcpy(start, str.value.ptr, str.length);
            start += str.length;
            break;
        }

        default:
            // Any other character is interpreted literally.
            *start++ = *c;
        }
    }
    va_end(argList);

    hashString(result);

    return OBJ_VAL(result);
}

// Creates a new string containing the code point in [string] starting at byte
// [index]. If [index] points into the middle of a UTF-8 sequence, returns an
// empty string.
Value wrenStringCodePointAt(WrenVM* vm, ObjString* string_, uint index)
{
    assert(index < string_.length, "Index out of bounds.");

    int codePoint = wrenUtf8Decode(cast(ubyte*)string_.value + index,
                                    string_.length - index);
    if (codePoint == -1)
    {
        // If it isn't a valid UTF-8 sequence, treat it as a single raw byte.
        char[2] bytes;
        bytes[0] = string_.value[index];
        bytes[1] = '\0';
        return wrenNewStringLength(vm, bytes.ptr, 1);
    }

    return wrenStringFromCodePoint(vm, codePoint);
}

// Uses the Boyer-Moore-Horspool string matching algorithm.
// Search for the first occurence of [needle] within [haystack] and returns its
// zero-based offset. Returns `UINT32_MAX` if [haystack] does not contain
// [needle].
uint wrenStringFind(ObjString* haystack, ObjString* needle, uint start)
{
    // Edge case: An empty needle is always found.
    if (needle.length == 0) return start;

    // If the needle goes past the haystack it won't be found.
    if (start + needle.length > haystack.length) return uint.max;

    // If the startIndex is too far it also won't be found.
    if (start >= haystack.length) return uint.max;

    // Pre-calculate the shift table. For each character (8-bit value), we
    // determine how far the search window can be advanced if that character is
    // the last character in the haystack where we are searching for the needle
    // and the needle doesn't match there.
    uint[ubyte.max] shift;
    uint needleEnd = needle.length - 1;

    // By default, we assume the character is not the needle at all. In that case
    // case, if a match fails on that character, we can advance one whole needle
    // width since.
    for (uint index = 0; index < ubyte.max; index++)
    {
        shift[index] = needle.length;
    }

    // Then, for every character in the needle, determine how far it is from the
    // end. If a match fails on that character, we can advance the window such
    // that it the last character in it lines up with the last place we could
    // find it in the needle.
    for (uint index = 0; index < needleEnd; index++)
    {
        char c = needle.value[index];
        shift[cast(ubyte)c] = needleEnd - index;
    }

    // Slide the needle across the haystack, looking for the first match or
    // stopping if the needle goes off the end.
    char lastChar = needle.value[needleEnd];
    uint range = haystack.length - needle.length;

    for (uint index = start; index <= range; )
    {
        import core.stdc.string : memcmp;
        // Compare the last character in the haystack's window to the last character
        // in the needle. If it matches, see if the whole needle matches.
        char c = haystack.value[index + needleEnd];
        if (lastChar == c &&
            memcmp(haystack.value.ptr + index, needle.value.ptr, needleEnd) == 0)
        {
            // Found a match.
            return index;
        }

        // Otherwise, slide the needle forward.
        index += shift[cast(ubyte)c];
    }

    // Not found.
    return uint.max;
}

// Returns true if [a] and [b] represent the same string.
static bool wrenStringEqualsCString(ObjString* a, const(char)* b, size_t length)
{
    import core.stdc.string : memcmp;
    return a.length == length && memcmp(a.value.ptr, b, length) == 0;
}

// Creates a new open upvalue pointing to [value] on the stack.
ObjUpvalue* wrenNewUpvalue(WrenVM* vm, Value* value)
{
    ObjUpvalue* upvalue = ALLOCATE!(WrenVM, ObjUpvalue)(vm);

    // Upvalues are never used as first-class objects, so don't need a class.
    initObj(vm, &upvalue.obj, ObjType.OBJ_UPVALUE, null);

    upvalue.value = value;
    upvalue.closed = NULL_VAL;
    upvalue.next = null;

    return upvalue;
}

// Mark [obj] as reachable and still in use. This should only be called
// during the sweep phase of a garbage collection.
void wrenGrayObj(WrenVM* vm, Obj* obj)
{
    if (obj == null) return;

    // Stop if the object is already darkened so we don't get stuck in a cycle.
    if (obj.isDark) return;

    // It's been reached.
    obj.isDark = true;

    // Add it to the gray list so it can be recursively explored for
    // more marks later.
    if (vm.grayCount >= vm.grayCapacity)
    {
        vm.grayCapacity = vm.grayCount * 2;
        vm.gray = cast(Obj**)vm.config.reallocateFn(vm.gray,
                                                vm.grayCapacity * (Obj*).sizeof,
                                                vm.config.userData);
    }

    vm.gray[vm.grayCount++] = obj;
}

// Mark [value] as reachable and still in use. This should only be called
// during the sweep phase of a garbage collection.
void wrenGrayValue(WrenVM* vm, Value value)
{
    if (!IS_OBJ(value)) return;
    wrenGrayObj(vm, AS_OBJ(value));
}

// Mark the values in [buffer] as reachable and still in use. This should only
// be called during the sweep phase of a garbage collection.
void wrenGrayBuffer(WrenVM* vm, ValueBuffer* buffer)
{
    for (int i = 0; i < buffer.count; i++)
    {
        wrenGrayValue(vm, buffer.data[i]);
    }
}

static void blackenClass(WrenVM* vm, ObjClass* classObj)
{
    // The metaclass.
    wrenGrayObj(vm, cast(Obj*)classObj.obj.classObj);

    // The superclass.
    wrenGrayObj(vm, cast(Obj*)classObj.superclass);

    // Method function objects.
    for (int i = 0; i < classObj.methods.count; i++)
    {
        if (classObj.methods.data[i].type == MethodType.METHOD_BLOCK)
        {
        wrenGrayObj(vm, cast(Obj*)classObj.methods.data[i].as.closure);
        }
    }

    wrenGrayObj(vm, cast(Obj*)classObj.name);

    if(!IS_NULL(classObj.attributes)) wrenGrayObj(vm, AS_OBJ(classObj.attributes));

    // Keep track of how much memory is still in use.
    vm.bytesAllocated += ObjClass.sizeof;
    vm.bytesAllocated += classObj.methods.capacity * Method.sizeof;
}

static void blackenClosure(WrenVM* vm, ObjClosure* closure)
{
    // Mark the function.
    wrenGrayObj(vm, cast(Obj*)closure.fn);

    // Mark the upvalues.
    for (int i = 0; i < closure.fn.numUpvalues; i++)
    {
        wrenGrayObj(vm, cast(Obj*)closure.upvalues[i]);
    }

    // Keep track of how much memory is still in use.
    vm.bytesAllocated += ObjClosure.sizeof;
    vm.bytesAllocated += (ObjUpvalue*).sizeof * closure.fn.numUpvalues;
}

static void blackenFiber(WrenVM* vm, ObjFiber* fiber)
{
  // Stack functions.
  for (int i = 0; i < fiber.numFrames; i++)
  {
    wrenGrayObj(vm, cast(Obj*)fiber.frames[i].closure);
  }

  // Stack variables.
  for (Value* slot = fiber.stack; slot < fiber.stackTop; slot++)
  {
    wrenGrayValue(vm, *slot);
  }

  // Open upvalues.
  ObjUpvalue* upvalue = fiber.openUpvalues;
  while (upvalue != null)
  {
    wrenGrayObj(vm, cast(Obj*)upvalue);
    upvalue = upvalue.next;
  }

  // The caller.
  wrenGrayObj(vm, cast(Obj*)fiber.caller);
  wrenGrayValue(vm, fiber.error);

  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjFiber.sizeof;
  vm.bytesAllocated += fiber.frameCapacity * CallFrame.sizeof;
  vm.bytesAllocated += fiber.stackCapacity * Value.sizeof;
}

static void blackenFn(WrenVM* vm, ObjFn* fn)
{
  // Mark the constants.
  wrenGrayBuffer(vm, &fn.constants);

  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjFn.sizeof;
  vm.bytesAllocated += ubyte.sizeof * fn.code.capacity;
  vm.bytesAllocated += Value.sizeof * fn.constants.capacity;
  
  // The debug line number buffer.
  vm.bytesAllocated += int.sizeof * fn.code.capacity;
  // TODO: What about the function name?
}

static void blackenForeign(WrenVM* vm, ObjForeign* foreign)
{
  // TODO: Keep track of how much memory the foreign object uses. We can store
  // this in each foreign object, but it will balloon the size. We may not want
  // that much overhead. One option would be to let the foreign class register
  // a C function that returns a size for the object. That way the VM doesn't
  // always have to explicitly store it.
}

static void blackenInstance(WrenVM* vm, ObjInstance* instance)
{
  wrenGrayObj(vm, cast(Obj*)instance.obj.classObj);

  // Mark the fields.
  for (int i = 0; i < instance.obj.classObj.numFields; i++)
  {
    wrenGrayValue(vm, instance.fields[i]);
  }

  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjInstance.sizeof;
  vm.bytesAllocated += Value.sizeof * instance.obj.classObj.numFields;
}

static void blackenList(WrenVM* vm, ObjList* list)
{
  // Mark the elements.
  wrenGrayBuffer(vm, &list.elements);

  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjList.sizeof;
  vm.bytesAllocated += Value.sizeof * list.elements.capacity;
}

static void blackenMap(WrenVM* vm, ObjMap* map)
{
  // Mark the entries.
  for (uint i = 0; i < map.capacity; i++)
  {
    MapEntry* entry = &map.entries[i];
    if (IS_UNDEFINED(entry.key)) continue;

    wrenGrayValue(vm, entry.key);
    wrenGrayValue(vm, entry.value);
  }

  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjMap.sizeof;
  vm.bytesAllocated += MapEntry.sizeof * map.capacity;
}

static void blackenModule(WrenVM* vm, ObjModule* module_)
{
  // Top-level variables.
  for (int i = 0; i < module_.variables.count; i++)
  {
    wrenGrayValue(vm, module_.variables.data[i]);
  }

  wrenBlackenSymbolTable(vm, &module_.variableNames);

  wrenGrayObj(vm, cast(Obj*)module_.name);

  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjModule.sizeof;
}

static void blackenRange(WrenVM* vm, ObjRange* range)
{
  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjRange.sizeof;
}

static void blackenString(WrenVM* vm, ObjString* str)
{
  // Keep track of how much memory is still in use.
  vm.bytesAllocated += ObjString.sizeof + str.length + 1;
}

static void blackenUpvalue(WrenVM* vm, ObjUpvalue* upvalue)
{
    // Mark the closed-over object (in case it is closed).
    wrenGrayValue(vm, upvalue.closed);

    // Keep track of how much memory is still in use.
    vm.bytesAllocated += ObjUpvalue.sizeof;
}

static void blackenObject(WrenVM* vm, Obj* obj)
{
    static if (WREN_DEBUG_TRACE_MEMORY)
    {
        import core.stdc.stdio : printf;
        import wren.dbg : wrenDumpValue;
        printf("mark ");
        wrenDumpValue(OBJ_VAL(obj));
        printf(" @ %p\n", obj);
    }

    // Traverse the object's fields.
    switch (obj.type) with(ObjType)
    {
        case OBJ_CLASS:    blackenClass(   vm, cast(ObjClass*)   obj); break;
        case OBJ_CLOSURE:  blackenClosure( vm, cast(ObjClosure*) obj); break;
        case OBJ_FIBER:    blackenFiber(   vm, cast(ObjFiber*)   obj); break;
        case OBJ_FN:       blackenFn(      vm, cast(ObjFn*)      obj); break;
        case OBJ_FOREIGN:  blackenForeign( vm, cast(ObjForeign*) obj); break;
        case OBJ_INSTANCE: blackenInstance(vm, cast(ObjInstance*)obj); break;
        case OBJ_LIST:     blackenList(    vm, cast(ObjList*)    obj); break;
        case OBJ_MAP:      blackenMap(     vm, cast(ObjMap*)     obj); break;
        case OBJ_MODULE:   blackenModule(  vm, cast(ObjModule*)  obj); break;
        case OBJ_RANGE:    blackenRange(   vm, cast(ObjRange*)   obj); break;
        case OBJ_STRING:   blackenString(  vm, cast(ObjString*)  obj); break;
        case OBJ_UPVALUE:  blackenUpvalue( vm, cast(ObjUpvalue*) obj); break;
        default: assert(0, "Unexpected object type");
    }
}

// Processes every object in the gray stack until all reachable objects have
// been marked. After that, all objects are either white (freeable) or black
// (in use and fully traversed).
void wrenBlackenObjects(WrenVM* vm)
{
    while (vm.grayCount > 0)
    {
        // Pop an item from the gray stack.
        Obj* obj = vm.gray[--vm.grayCount];
        blackenObject(vm, obj);
    }
}

// Releases all memory owned by [obj], including [obj] itself.
void wrenFreeObj(WrenVM* vm, Obj* obj)
{
    static if (WREN_DEBUG_TRACE_MEMORY)
    {
        import core.stdc.stdio;
        import wren.dbg : wrenDumpValue;
        printf("free ");
        wrenDumpValue(OBJ_VAL(obj));
        printf (" @ %p\n", obj);
    }

    switch (obj.type)
    {
        case ObjType.OBJ_CLASS: {
            wrenMethodBufferClear(vm, &(cast(ObjClass*)obj).methods);
            break;
        }
        
        case ObjType.OBJ_FIBER: {
            ObjFiber* fiber = cast(ObjFiber*)obj;
            DEALLOCATE(vm, fiber.frames);
            DEALLOCATE(vm, fiber.stack);
            break;
        }
        
        case ObjType.OBJ_FN: {
            ObjFn* fn = cast(ObjFn*)obj;
            wrenValueBufferClear(vm, &fn.constants);
            wrenByteBufferClear(vm, &fn.code);
            wrenIntBufferClear(vm, &fn.debug_.sourceLines);
            DEALLOCATE(vm, fn.debug_.name);
            DEALLOCATE(vm, fn.debug_);
            break;
        }

        case ObjType.OBJ_FOREIGN:
            assert(0, "stub");
        
        case ObjType.OBJ_LIST:
            wrenValueBufferClear(vm, &(cast(ObjList*)obj).elements);
            break;
        
        case ObjType.OBJ_MAP:
            DEALLOCATE(vm, (cast(ObjMap*)obj).entries);
            break;
        
        case ObjType.OBJ_MODULE:
            wrenSymbolTableClear(vm, &(cast(ObjModule*)obj).variableNames);
            wrenValueBufferClear(vm, &(cast(ObjModule*)obj).variables);
            break;
        
        case ObjType.OBJ_CLOSURE:
        case ObjType.OBJ_INSTANCE:
        case ObjType.OBJ_RANGE:
        case ObjType.OBJ_STRING:
        case ObjType.OBJ_UPVALUE:
            break;
        
        default:
            assert(0, "Unexpected object type");       
    }
}

// Returns true if [a] and [b] are equivalent. Immutable values (null, bools,
// numbers, ranges, and strings) are equal if they have the same data. All
// other values are equal if they are identical objects.
bool wrenValuesEqual(Value a, Value b)
{
    if (wrenValuesSame(a, b)) return true;

    // If we get here, it's only possible for two heap-allocated immutable objects
    // to be equal.
    if (!IS_OBJ(a) || !IS_OBJ(b)) return false;

    Obj* aObj = AS_OBJ(a);
    Obj* bObj = AS_OBJ(b);

    // Must be the same type.
    if (aObj.type != bObj.type) return false;

    switch (aObj.type)
    {
        case ObjType.OBJ_RANGE:
        {
            ObjRange* aRange = cast(ObjRange*)aObj;
            ObjRange* bRange = cast(ObjRange*)bObj;
            return aRange.from == bRange.from &&
                    aRange.to == bRange.to &&
                    aRange.isInclusive == bRange.isInclusive;
        }

        case ObjType.OBJ_STRING:
        {
            ObjString* aString = cast(ObjString*)aObj;
            ObjString* bString = cast(ObjString*)bObj;
            return aString.hash == bString.hash &&
                wrenStringEqualsCString(aString, bString.value.ptr, bString.length);
        }

        default:
            // All other types are only equal if they are same, which they aren't if
            // we get here.
            return false;
    }
}