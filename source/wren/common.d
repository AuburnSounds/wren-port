module wren.common;

@nogc:

// The Wren semantic version number components.
enum WREN_VERSION_MAJOR = 0;
enum WREN_VERSION_MINOR = 4;
enum WREN_VERSION_PATCH = 0;

// A human-friendly string representation of the version.
enum WREN_VERSION_STRING = "0.4.0";

// A monotonically increasing numeric representation of the version number. Use
// this if you want to do range checks over versions.
enum WREN_VERSION_NUMBER = WREN_VERSION_MAJOR * 1000000 +
                           WREN_VERSION_MINOR * 1000 +
                           WREN_VERSION_PATCH;

int wrenGetVersionNumber() {
    return WREN_VERSION_NUMBER;
}

// These flags let you control some details of the interpreter's implementation.
// Usually they trade-off a bit of portability for speed. They default to the
// most efficient behavior.

// If true, then Wren uses a NaN-tagged double for its core value
// representation. Otherwise, it uses a larger more conventional struct. The
// former is significantly faster and more compact. The latter is useful for
// debugging and may be more portable.
//
// Defaults to on.
version(WrenNoNanTagging)
{
    enum WREN_NAN_TAGGING = 0;
}
else 
{
    enum WREN_NAN_TAGGING = 1;
}

// The VM includes a number of optional modules. You can choose to include
// these or not. By default, they are all available. To disable one, set the
// corresponding `WREN_OPT_<name>` define to `0`.
version(WrenNoOptMeta)
{
    enum WREN_OPT_META = 0;
}
else
{
    enum WREN_OPT_META = 1;
}

version (WrenNoOptRandom)
{
    enum WREN_OPT_RANDOM = 0;
}
else
{
    enum WREN_OPT_RANDOM = 1;
}

// These flags are useful for debugging and hacking on Wren itself. They are not
// intended to be used for production code. They default to off.

// Set this to true to stress test the GC. It will perform a collection before
// every allocation. This is useful to ensure that memory is always correctly
// reachable.
version (WrenDebugGCStress)
{
    enum WREN_DEBUG_GC_STRESS = 1;
}
else
{
    enum WREN_DEBUG_GC_STRESS = 0;
}

// Set this to true to log memory operations as they occur.
version (WrenDebugTraceMemory)
{
    enum WREN_DEBUG_TRACE_MEMORY = 1;
}
else
{
    enum WREN_DEBUG_TRACE_MEMORY = 0;
}

// Set this to true to log garbage collections as they occur.
version (WrenDebugTraceGC)
{
    enum WREN_DEBUG_TRACE_GC = 1;
}
else
{
    enum WREN_DEBUG_TRACE_GC = 0;
}

// Set this to true to print out the compiled bytecode of each function.
version (WrenDebugDumpCompiledCode)
{
    enum WREN_DEBUG_DUMP_COMPILED_CODE = 1;
}
else
{
    enum WREN_DEBUG_DUMP_COMPILED_CODE = 0;
}

// Set this to trace each instruction as it's executed.
version (WrenDebugTraceInstructions)
{
    enum WREN_DEBUG_TRACE_INSTRUCTIONS = 1;
}
else
{
    enum WREN_DEBUG_TRACE_INSTRUCTIONS = 0;
}

// The maximum number of module-level variables that may be defined at one time.
// This limitation comes from the 16 bits used for the arguments to
// `CODE_LOAD_MODULE_VAR` and `CODE_STORE_MODULE_VAR`.
enum MAX_MODULE_VARS = 65536;

// The maximum number of arguments that can be passed to a method. Note that
// this limitation is hardcoded in other places in the VM, in particular, the
// `CODE_CALL_XX` instructions assume a certain maximum number.
enum MAX_PARAMETERS = 16;

// The maximum name of a method, not including the signature. This is an
// arbitrary but enforced maximum just so we know how long the method name
// strings need to be in the parser.
enum MAX_METHOD_NAME = 64;

// The maximum length of a method signature. Signatures look like:
//
//     foo        // Getter.
//     foo()      // No-argument method.
//     foo(_)     // One-argument method.
//     foo(_,_)   // Two-argument method.
//     init foo() // Constructor initializer.
//
// The maximum signature length takes into account the longest method name, the
// maximum number of parameters with separators between them, "init ", and "()".
enum MAX_METHOD_SIGNATURE = MAX_METHOD_NAME + (MAX_PARAMETERS * 2) + 6;

// The maximum length of an identifier. The only real reason for this limitation
// is so that error messages mentioning variables can be stack allocated.
enum MAX_VARIABLE_NAME = 64;

// The maximum number of fields a class can have, including inherited fields.
// This is explicit in the bytecode since `CODE_CLASS` and `CODE_SUBCLASS` take
// a single byte for the number of fields. Note that it's 255 and not 256
// because creating a class takes the *number* of fields, not the *highest
// field index*.
enum MAX_FIELDS = 255;

// XXX: move this to `wren.vm`?
// Use the VM's allocator to allocate an object of [type].
T* ALLOCATE(VM, T)(VM* vm) @nogc
{
    import wren.vm : wrenReallocate;
    return cast(typeof(return))wrenReallocate(vm, null, 0, T.sizeof);
}

// Use the VM's allocator to allocate an object of [mainType] containing a
// flexible array of [count] objects of [arrayType].
T* ALLOCATE_FLEX(VM, T, ArrayType)(VM* vm, size_t count) @nogc
{
    import std.traits : isArray;
    import wren.vm : wrenReallocate;
    T* obj = cast(T*)wrenReallocate(vm, null, 0, T.sizeof);
    ArrayType* arr = cast(ArrayType*)wrenReallocate(vm, null, 0, ArrayType.sizeof * count);

    // EEEEK. Since arrays differ in implementation,
    // we can't just malloc the size of an object + the size of the array we want to
    // allocate for. This is a little tricky way of getting around that --
    // but this WILL break if T has more then one array.
    static foreach(_mem; __traits(allMembers, T)) {{
        alias member = __traits(getMember, T, _mem);
        static if (isArray!(typeof(member))) {
            alias ArrayElementType = typeof(member[0]);
            static if (is(ArrayElementType == ArrayType)) {
                __traits(child, obj, member) = arr[0 .. count];
            }  
        }
    }}
    return obj;
}

T* ALLOCATE_ARRAY(VM, T)(VM* vm, size_t count) @nogc
{
    import wren.vm : wrenReallocate;
    return cast(typeof(return))wrenReallocate(vm, null, 0, T.sizeof * count);
}

void DEALLOCATE(VM)(VM* vm, void* pointer) @nogc
{
    import wren.vm : wrenReallocate;
    wrenReallocate(vm, pointer, 0, 0);
}

