module wren.vm;
import wren.core;
import wren.common;
import wren.value;
import wren.utils;

@nogc:

// The type of a primitive function.
//
// Primitives are similar to foreign functions, but have more direct access to
// VM internals. It is passed the arguments in [args]. If it returns a value,
// it places it in `args[0]` and returns `true`. If it causes a runtime error
// or modifies the running fiber, it returns `false`.
alias Primitive = bool function(WrenVM* vm, Value* args);

// A generic allocation function that handles all explicit memory management
// used by Wren. It's used like so:
//
// - To allocate new memory, [memory] is NULL and [newSize] is the desired
//   size. It should return the allocated memory or NULL on failure.
//
// - To attempt to grow an existing allocation, [memory] is the memory, and
//   [newSize] is the desired size. It should return [memory] if it was able to
//   grow it in place, or a new pointer if it had to move it.
//
// - To shrink memory, [memory] and [newSize] are the same as above but it will
//   always return [memory].
//
// - To free memory, [memory] will be the memory to free and [newSize] will be
//   zero. It should return NULL.
alias WrenReallocateFn = void* function(void* memory, size_t newSize, void* userData);

// A function callable from Wren code, but implemented in C.
alias WrenForeignMethodFn = void function(WrenVM* vm);

// A finalizer function for freeing resources owned by an instance of a foreign
// class. Unlike most foreign methods, finalizers do not have access to the VM
// and should not interact with it since it's in the middle of a garbage
// collection.
alias WrenFinalizerFn = void function(void* data);

// Gives the host a chance to canonicalize the imported module name,
// potentially taking into account the (previously resolved) name of the module
// that contains the import. Typically, this is used to implement relative
// imports.
alias WrenResolveModuleFn = const(char)* function(WrenVM* vm, 
                                    const(char)* importer, const(char)* name);

// Called after loadModuleFn is called for module [name]. The original returned result
// is handed back to you in this callback, so that you can free memory if appropriate.
alias WrenLoadModuleCompleteFn = void function(WrenVM* vm, const(char)* name, WrenLoadModuleResult result);

// The result of a loadModuleFn call. 
// [source] is the source code for the module, or NULL if the module is not found.
// [onComplete] an optional callback that will be called once Wren is done with the result.
struct WrenLoadModuleResult
{
    const(char)* source;
    WrenLoadModuleCompleteFn onComplete;
    void* userData;
}

// Loads and returns the source code for the module [name].
alias WrenLoadModuleFn = WrenLoadModuleResult function(WrenVM* vm, const(char)* name);

// Returns a pointer to a foreign method on [className] in [module] with
// [signature].
alias WrenBindForeignMethodFn = WrenForeignMethodFn function(WrenVM* vm,
    const(char)* module_, const(char)* className, bool isStatic,
    const(char)* signature);

// Displays a string of text to the user.
alias WrenWriteFn = void function(WrenVM* vm, const(char)* text);

enum WrenErrorType
{
    // A syntax or resolution error detected at compile time.
    WREN_ERROR_COMPILE,

    // The error message for a runtime error.
    WREN_ERROR_RUNTIME,

    // One entry of a runtime error's stack trace.
    WREN_ERROR_STACK_TRACE
}

// Reports an error to the user.
//
// An error detected during compile time is reported by calling this once with
// [type] `WREN_ERROR_COMPILE`, the resolved name of the [module] and [line]
// where the error occurs, and the compiler's error [message].
//
// A runtime error is reported by calling this once with [type]
// `WREN_ERROR_RUNTIME`, no [module] or [line], and the runtime error's
// [message]. After that, a series of [type] `WREN_ERROR_STACK_TRACE` calls are
// made for each line in the stack trace. Each of those has the resolved
// [module] and [line] where the method or function is defined and [message] is
// the name of the method or function.
alias WrenErrorFn = void function(WrenVM* vm, WrenErrorType type, const(char)* module_,
    int line, const(char)* message);

struct WrenForeignClassMethods
{
    // The callback invoked when the foreign object is created.
    //
    // This must be provided. Inside the body of this, it must call
    // [wrenSetSlotNewForeign()] exactly once.
    WrenForeignMethodFn allocate;

    // The callback invoked when the garbage collector is about to collect a
    // foreign object's memory.
    //
    // This may be `NULL` if the foreign class does not need to finalize.
    WrenFinalizerFn finalize;
}

alias WrenBindForeignClassFn = WrenForeignClassMethods function(
    WrenVM* vm, const(char)* module_, const(char)* className);

struct WrenConfiguration
{
    // The callback Wren will use to allocate, reallocate, and deallocate memory.
    //
    // If `NULL`, defaults to a built-in function that uses `realloc` and `free`.
    WrenReallocateFn reallocateFn;

    // The callback Wren uses to resolve a module name.
    //
    // Some host applications may wish to support "relative" imports, where the
    // meaning of an import string depends on the module that contains it. To
    // support that without baking any policy into Wren itself, the VM gives the
    // host a chance to resolve an import string.
    //
    // Before an import is loaded, it calls this, passing in the name of the
    // module that contains the import and the import string. The host app can
    // look at both of those and produce a new "canonical" string that uniquely
    // identifies the module. This string is then used as the name of the module
    // going forward. It is what is passed to [loadModuleFn], how duplicate
    // imports of the same module are detected, and how the module is reported in
    // stack traces.
    //
    // If you leave this function NULL, then the original import string is
    // treated as the resolved string.
    //
    // If an import cannot be resolved by the embedder, it should return NULL and
    // Wren will report that as a runtime error.
    //
    // Wren will take ownership of the string you return and free it for you, so
    // it should be allocated using the same allocation function you provide
    // above.
    WrenResolveModuleFn resolveModuleFn;

    // The callback Wren uses to load a module.
    //
    // Since Wren does not talk directly to the file system, it relies on the
    // embedder to physically locate and read the source code for a module. The
    // first time an import appears, Wren will call this and pass in the name of
    // the module being imported. The method will return a result, which contains
    // the source code for that module. Memory for the source is owned by the 
    // host application, and can be freed using the onComplete callback.
    //
    // This will only be called once for any given module name. Wren caches the
    // result internally so subsequent imports of the same module will use the
    // previous source and not call this.
    //
    // If a module with the given name could not be found by the embedder, it
    // should return NULL and Wren will report that as a runtime error.
    WrenLoadModuleFn loadModuleFn;

    // The callback Wren uses to find a foreign method and bind it to a class.
    //
    // When a foreign method is declared in a class, this will be called with the
    // foreign method's module, class, and signature when the class body is
    // executed. It should return a pointer to the foreign function that will be
    // bound to that method.
    //
    // If the foreign function could not be found, this should return NULL and
    // Wren will report it as runtime error.
    WrenBindForeignMethodFn bindForeignMethodFn;

    // The callback Wren uses to find a foreign class and get its foreign methods.
    //
    // When a foreign class is declared, this will be called with the class's
    // module and name when the class body is executed. It should return the
    // foreign functions uses to allocate and (optionally) finalize the bytes
    // stored in the foreign object when an instance is created.
    WrenBindForeignClassFn bindForeignClassFn;

    // The callback Wren uses to display text when `System.print()` or the other
    // related functions are called.
    //
    // If this is `NULL`, Wren discards any printed text.
    WrenWriteFn writeFn;

    // The callback Wren uses to report errors.
    //
    // When an error occurs, this will be called with the module name, line
    // number, and an error message. If this is `NULL`, Wren doesn't report any
    // errors.
    WrenErrorFn errorFn;

    // The number of bytes Wren will allocate before triggering the first garbage
    // collection.
    //
    // If zero, defaults to 10MB.
    size_t initialHeapSize;

    // After a collection occurs, the threshold for the next collection is
    // determined based on the number of bytes remaining in use. This allows Wren
    // to shrink its memory usage automatically after reclaiming a large amount
    // of memory.
    //
    // This can be used to ensure that the heap does not get too small, which can
    // in turn lead to a large number of collections afterwards as the heap grows
    // back to a usable size.
    //
    // If zero, defaults to 1MB.
    size_t minHeapSize;

    // Wren will resize the heap automatically as the number of bytes
    // remaining in use after a collection changes. This number determines the
    // amount of additional memory Wren will use after a collection, as a
    // percentage of the current heap size.
    //
    // For example, say that this is 50. After a garbage collection, when there
    // are 400 bytes of memory still in use, the next collection will be triggered
    // after a total of 600 bytes are allocated (including the 400 already in
    // use.)
    //
    // Setting this to a smaller number wastes less memory, but triggers more
    // frequent garbage collections.
    //
    // If zero, defaults to 50.
    int heapGrowthPercent;

    // User-defined data associated with the VM.
    void* userData;
}

enum WrenInterpretResult
{
    WREN_RESULT_SUCCESS,
    WREN_RESULT_COMPILE_ERROR,
    WREN_RESULT_RUNTIME_ERROR
}

// The type of an object stored in a slot.
//
// This is not necessarily the object's *class*, but instead its low level
// representation type.
enum WrenType
{
    WREN_TYPE_BOOL,
    WREN_TYPE_NUM,
    WREN_TYPE_FOREIGN,
    WREN_TYPE_LIST,
    WREN_TYPE_MAP,
    WREN_TYPE_NULL,
    WREN_TYPE_STRING,

    // The object is of a type that isn't accessible by the C API.
    WREN_TYPE_UNKNOWN
}

// The maximum number of temporary objects that can be made visible to the GC
// at one time.
enum WREN_MAX_TEMP_ROOTS = 8;

struct WrenVM
{
    ObjClass* boolClass;
    ObjClass* classClass;
    ObjClass* fiberClass;
    ObjClass* fnClass;
    ObjClass* listClass;
    ObjClass* mapClass;
    ObjClass* nullClass;
    ObjClass* numClass;
    ObjClass* objectClass;
    ObjClass* rangeClass;
    ObjClass* stringClass;

    // The fiber that is currently running.
    ObjFiber* fiber;

    // The loaded modules. Each key is an ObjString (except for the main module,
    // whose key is null) for the module's name and the value is the ObjModule
    // for the module.
    ObjMap* modules;
    
    // The most recently imported module. More specifically, the module whose
    // code has most recently finished executing.
    //
    // Not treated like a GC root since the module is already in [modules].
    ObjModule* lastModule;

    // Memory management data:

    // The number of bytes that are known to be currently allocated. Includes all
    // memory that was proven live after the last GC, as well as any new bytes
    // that were allocated since then. Does *not* include bytes for objects that
    // were freed since the last GC.
    size_t bytesAllocated;

    // The number of total allocated bytes that will trigger the next GC.
    size_t nextGC;

    // The first object in the linked list of all currently allocated objects.
    Obj* first;

    // The "gray" set for the garbage collector. This is the stack of unprocessed
    // objects while a garbage collection pass is in process.
    Obj** gray;
    int grayCount;
    int grayCapacity;

    // The list of temporary roots. This is for temporary or new objects that are
    // not otherwise reachable but should not be collected.
    //
    // They are organized as a stack of pointers stored in this array. This
    // implies that temporary roots need to have stack semantics: only the most
    // recently pushed object can be released.
    Obj*[WREN_MAX_TEMP_ROOTS] tempRoots;

    int numTempRoots;
    
    // Pointer to the first node in the linked list of active handles or NULL if
    // there are none.
    WrenHandle* handles;
    
    // Pointer to the bottom of the range of stack slots available for use from
    // the C API. During a foreign method, this will be in the stack of the fiber
    // that is executing a method.
    //
    // If not in a foreign method, this is initially NULL. If the user requests
    // slots by calling wrenEnsureSlots(), a stack is created and this is
    // initialized.
    Value* apiStack;

    WrenConfiguration config;
    
    // Compiler and debugger data:

    // The compiler that is currently compiling code. This is used so that heap
    // allocated objects used by the compiler can be found if a GC is kicked off
    // in the middle of a compile.
    void* compiler;

    // There is a single global symbol table for all method names on all classes.
    // Method calls are dispatched directly by index in this table.
    SymbolTable methodNames;
}

// The behavior of realloc() when the size is 0 is implementation defined. It
// may return a non-NULL pointer which must not be dereferenced but nevertheless
// should be freed. To prevent that, we avoid calling realloc() with a zero
// size.
static void* defaultReallocate(void* ptr, size_t newSize, void* _)
{
    import core.stdc.stdlib : free, realloc;

    if (newSize == 0)
    {
        free(ptr);
        return null;
    }
    
    return realloc(ptr, newSize);
}

void wrenInitConfiguration(WrenConfiguration* config)
{
    config.reallocateFn = &defaultReallocate;
    config.resolveModuleFn = null;
    config.loadModuleFn = null;
    config.bindForeignMethodFn = null;
    config.bindForeignClassFn = null;
    config.writeFn = null;
    config.errorFn = null;
    config.initialHeapSize = 1024 * 1024 * 10;
    config.minHeapSize = 1024 * 1024;
    config.heapGrowthPercent = 50;
    config.userData = null;
}

WrenVM* wrenNewVM(WrenConfiguration* config)
{
    import core.stdc.string : memset, memcpy;
    WrenReallocateFn reallocate = &defaultReallocate;
    void* userData = null;
    if (config != null) {
        userData = config.userData;
        reallocate = config.reallocateFn ? config.reallocateFn : &defaultReallocate;
    }

    WrenVM* vm = cast(WrenVM*)reallocate(null, WrenVM.sizeof, userData);
    memset(vm, 0, WrenVM.sizeof);

    // Copy the configuration if given one.
    if (config != null)
    {
        memcpy(&vm.config, config, WrenConfiguration.sizeof);
        // We choose to set this after copying, 
        // rather than modifying the user config pointer
        vm.config.reallocateFn = reallocate;
    }
    else
    {
        wrenInitConfiguration(&vm.config);
    }

    // TODO: Should we allocate and free this during a GC?
    vm.grayCount = 0;
    // TODO: Tune this.
    vm.grayCapacity = 4;
    vm.gray = cast(Obj**)reallocate(null, vm.grayCapacity * (Obj*).sizeof, userData);
    vm.nextGC = vm.config.initialHeapSize;

    wrenSymbolTableInit(&vm.methodNames);

    vm.modules = wrenNewMap(vm);
    wrenInitializeCore(vm);
    return vm;
}

void wrenFreeVM(WrenVM* vm)
{
    assert(vm.methodNames.count > 0, "VM appears to have already been freed.");

    // Free all of the GC objects.
    Obj* obj = vm.first;
    while (obj != null)
    {
        Obj* next = obj.next;
        wrenFreeObj(vm, obj);
        obj = next;
    }

    // Free up the GC gray set.
    vm.gray = cast(Obj**)vm.config.reallocateFn(vm.gray, 0, vm.config.userData);

    // Tell the user if they didn't free any handles. We don't want to just free
    // them here because the host app may still have pointers to them that they
    // may try to use. Better to tell them about the bug early.
    assert(vm.handles == null, "All handles have not been released.");

    wrenSymbolTableClear(vm, &vm.methodNames);

    DEALLOCATE(vm, vm);
}

void wrenCollectGarbage(WrenVM* vm)
{
    
}

// Looks up the previously loaded module with [name].
//
// Returns `NULL` if no module with that name has been loaded.
static ObjModule* getModule(WrenVM* vm, Value name)
{
  Value moduleValue = wrenMapGet(vm.modules, name);
  return !IS_UNDEFINED(moduleValue) ? AS_MODULE(moduleValue) : null;
}

static Value getModuleVariable(WrenVM* vm, ObjModule* module_,
                               Value variableName)
{
  ObjString* variable = AS_STRING(variableName);
  uint variableEntry = wrenSymbolTableFind(&module_.variableNames,
                                               variable.value.ptr,
                                               variable.length);
  
  // It's a runtime error if the imported variable does not exist.
  if (variableEntry != uint.max)
  {
    return module_.variables.data[variableEntry];
  }
  
  vm.fiber.error = wrenStringFormat(vm,
      "Could not find a variable named '@' in module '@'.",
      variableName, OBJ_VAL(module_.name));
  return NULL_VAL;
}


// A generic allocation function that handles all explicit memory management.
// It's used like so:
//
// - To allocate new memory, [memory] is NULL and [oldSize] is zero. It should
//   return the allocated memory or NULL on failure.
//
// - To attempt to grow an existing allocation, [memory] is the memory,
//   [oldSize] is its previous size, and [newSize] is the desired size.
//   It should return [memory] if it was able to grow it in place, or a new
//   pointer if it had to move it.
//
// - To shrink memory, [memory], [oldSize], and [newSize] are the same as above
//   but it will always return [memory].
//
// - To free memory, [memory] will be the memory to free and [newSize] and
//   [oldSize] will be zero. It should return NULL.
void* wrenReallocate(WrenVM* vm, void* memory, size_t oldSize, size_t newSize)
{
    static if (WREN_DEBUG_TRACE_MEMORY)
    {
        import core.stdc.stdio : printf;
        printf("reallocate %p %lu -> %lu",
                memory, cast(ulong)oldSize, cast(ulong)newSize);
    }

    // If new bytes are being allocated, add them to the total count. If objects
    // are being completely deallocated, we don't track that (since we don't
    // track the original size). Instead, that will be handled while marking
    // during the next GC.
    vm.bytesAllocated += newSize - oldSize;

    static if (WREN_DEBUG_GC_STRESS)
    {
        // Since collecting calls this function to free things, make sure we don't
        // recurse.
        if (newSize > 0) wrenCollectGarbage(vm);
    }
    else
    {
        if (newSize > 0 && vm.bytesAllocated > vm.nextGC) wrenCollectGarbage(vm);
    }

    return vm.config.reallocateFn(memory, newSize, vm.config.userData);
}

Value wrenGetModuleVariable(WrenVM* vm, Value moduleName, Value variableName)
{
    ObjModule* module_ = getModule(vm, moduleName);
    if (module_ == null)
    {
        vm.fiber.error = wrenStringFormat(vm, "Module '@' is not loaded.",
                                            moduleName);
        return NULL_VAL;
    }
    
    return getModuleVariable(vm, module_, variableName);
}

Value wrenFindVariable(WrenVM* vm, ObjModule* module_, const char* name)
{
    import core.stdc.string : strlen;
    int symbol = wrenSymbolTableFind(&module_.variableNames, name, strlen(name));
    return module_.variables.data[symbol];
}

int wrenDeclareVariable(WrenVM* vm, ObjModule* module_, const char* name,
                        size_t length, int line)
{
    if (module_.variables.count == MAX_MODULE_VARS) return -2;

    // Implicitly defined variables get a "value" that is the line where the
    // variable is first used. We'll use that later to report an error on the
    // right line.
    wrenValueBufferWrite(vm, &module_.variables, NUM_VAL(line));
    return wrenSymbolTableAdd(vm, &module_.variableNames, name, length);
}

int wrenDefineVariable(WrenVM* vm, ObjModule* module_, const char* name,
                       size_t length, Value value, int* line)
{
    if (module_.variables.count == MAX_MODULE_VARS) return -2;

    if (IS_OBJ(value)) wrenPushRoot(vm, AS_OBJ(value));

    // See if the variable is already explicitly or implicitly declared.
    int symbol = wrenSymbolTableFind(&module_.variableNames, name, length);

    if (symbol == -1)
    {
        // Brand new variable.
        symbol = wrenSymbolTableAdd(vm, &module_.variableNames, name, length);
        wrenValueBufferWrite(vm, &module_.variables, value);
    }
    else if (IS_NUM(module_.variables.data[symbol]))
    {
        // An implicitly declared variable's value will always be a number.
        // Now we have a real definition.
        if(line) *line = cast(int)AS_NUM(module_.variables.data[symbol]);
        module_.variables.data[symbol] = value;

        // If this was a localname we want to error if it was 
        // referenced before this definition.
        if (wrenIsLocalName(name)) symbol = -3;
    }
    else
    {
        // Already explicitly declared.
        symbol = -1;
    }

    if (IS_OBJ(value)) wrenPopRoot(vm);

    return symbol;
}

void wrenPushRoot(WrenVM* vm, Obj* obj)
{
    assert(obj != null, "Cannot root NULL");
    assert(vm.numTempRoots < WREN_MAX_TEMP_ROOTS, "Too many temporary roots.");

    vm.tempRoots[vm.numTempRoots++] = obj;
}

void wrenPopRoot(WrenVM* vm)
{
    assert(vm.numTempRoots > 0, "No temporary roots to release.");
    vm.numTempRoots--;
}

static bool wrenIsLocalName(const(char)* name)
{
    return name[0] >= 'a' && name[0] <= 'z';
}