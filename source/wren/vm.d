module wren.vm;
import wren.core;
import wren.common;
import wren.opcodes;
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
// - To allocate new memory, [memory] is null and [newSize] is the desired
//   size. It should return the allocated memory or null on failure.
//
// - To attempt to grow an existing allocation, [memory] is the memory, and
//   [newSize] is the desired size. It should return [memory] if it was able to
//   grow it in place, or a new pointer if it had to move it.
//
// - To shrink memory, [memory] and [newSize] are the same as above but it will
//   always return [memory].
//
// - To free memory, [memory] will be the memory to free and [newSize] will be
//   zero. It should return null.
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
// [source] is the source code for the module, or null if the module is not found.
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
    // This may be `null` if the foreign class does not need to finalize.
    WrenFinalizerFn finalize;
}

alias WrenBindForeignClassFn = WrenForeignClassMethods function(
    WrenVM* vm, const(char)* module_, const(char)* className);

struct WrenConfiguration
{
    // The callback Wren will use to allocate, reallocate, and deallocate memory.
    //
    // If `null`, defaults to a built-in function that uses `realloc` and `free`.
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
    // If you leave this function null, then the original import string is
    // treated as the resolved string.
    //
    // If an import cannot be resolved by the embedder, it should return null and
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
    // should return null and Wren will report that as a runtime error.
    WrenLoadModuleFn loadModuleFn;

    // The callback Wren uses to find a foreign method and bind it to a class.
    //
    // When a foreign method is declared in a class, this will be called with the
    // foreign method's module, class, and signature when the class body is
    // executed. It should return a pointer to the foreign function that will be
    // bound to that method.
    //
    // If the foreign function could not be found, this should return null and
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
    // If this is `null`, Wren discards any printed text.
    WrenWriteFn writeFn;

    // The callback Wren uses to report errors.
    //
    // When an error occurs, this will be called with the module name, line
    // number, and an error message. If this is `null`, Wren doesn't report any
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
    
    // Pointer to the first node in the linked list of active handles or null if
    // there are none.
    WrenHandle* handles;
    
    // Pointer to the bottom of the range of stack slots available for use from
    // the C API. During a foreign method, this will be in the stack of the fiber
    // that is executing a method.
    //
    // If not in a foreign method, this is initially null. If the user requests
    // slots by calling wrenEnsureSlots(), a stack is created and this is
    // initialized.
    Value* apiStack;

    WrenConfiguration config;
    
    // Compiler and debugger data:

    // The compiler that is currently compiling code. This is used so that heap
    // allocated objects used by the compiler can be found if a GC is kicked off
    // in the middle of a compile.
    import wren.compiler : Compiler;
    Compiler* compiler;

    // There is a single global symbol table for all method names on all classes.
    // Method calls are dispatched directly by index in this table.
    SymbolTable methodNames;
}

// The behavior of realloc() when the size is 0 is implementation defined. It
// may return a non-null pointer which must not be dereferenced but nevertheless
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
    static if (WREN_DEBUG_TRACE_MEMORY || WREN_DEBUG_TRACE_GC)
    {
        import core.stdc.stdio : printf;
        import core.stdc.time;
        printf("-- gc --\n");

        size_t before = vm.bytesAllocated;
        double startTime = cast(double)clock() / CLOCKS_PER_SEC;
    }

    // Mark all reachable objects.

    // Reset this. As we mark objects, their size will be counted again so that
    // we can track how much memory is in use without needing to know the size
    // of each *freed* object.
    //
    // This is important because when freeing an unmarked object, we don't always
    // know how much memory it is using. For example, when freeing an instance,
    // we need to know its class to know how big it is, but its class may have
    // already been freed.
    vm.bytesAllocated = 0;

    wrenGrayObj(vm, cast(Obj*)vm.modules);

    // Temporary roots.
    for (int i = 0; i < vm.numTempRoots; i++)
    {
        wrenGrayObj(vm, vm.tempRoots[i]);
    }

    // The current fiber.
    wrenGrayObj(vm, cast(Obj*)vm.fiber);

    // The handles.
    for (WrenHandle* handle = vm.handles;
        handle != null;
        handle = handle.next)
    {
        wrenGrayValue(vm, handle.value);
    }

    // Any object the compiler is using (if there is one).
    import wren.compiler : wrenMarkCompiler;
    if (vm.compiler != null) wrenMarkCompiler(vm, vm.compiler);

    // Method names.
    wrenBlackenSymbolTable(vm, &vm.methodNames);

    // Now that we have grayed the roots, do a depth-first search over all of the
    // reachable objects.
    wrenBlackenObjects(vm);

    // Collect the white objects.
    Obj** obj = &vm.first;
    while (*obj != null)
    {
        if (!((*obj).isDark))
        {
            // This object wasn't reached, so remove it from the list and free it.
            Obj* unreached = *obj;
            *obj = unreached.next;
            wrenFreeObj(vm, unreached);
        }
        else
        {
            // This object was reached, so unmark it (for the next GC) and move on to
            // the next.
            (*obj).isDark = false;
            obj = &(*obj).next;
        }
    }

    // Calculate the next gc point, this is the current allocation plus
    // a configured percentage of the current allocation.
    vm.nextGC = vm.bytesAllocated + ((vm.bytesAllocated * vm.config.heapGrowthPercent) / 100);
    if (vm.nextGC < vm.config.minHeapSize) vm.nextGC = vm.config.minHeapSize;

    static if (WREN_DEBUG_TRACE_MEMORY || WREN_DEBUG_TRACE_GC)
    {
        double elapsed = (cast(double)clock / CLOCKS_PER_SEC) - startTime;
        // Explicit cast because size_t has different sizes on 32-bit and 64-bit and
        // we need a consistent type for the format string.
        printf("GC %lu before, %lu after (%lu collected), next at %lu. Took %.3fms.\n",
            cast(ulong)before,
            cast(ulong)vm.bytesAllocated,
            cast(ulong)(before - vm.bytesAllocated),
            cast(ulong)vm.nextGC,
            elapsed*1000.0);
    }
}

// A generic allocation function that handles all explicit memory management.
// It's used like so:
//
// - To allocate new memory, [memory] is null and [oldSize] is zero. It should
//   return the allocated memory or null on failure.
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
//   [oldSize] will be zero. It should return null.
void* wrenReallocate(WrenVM* vm, void* memory, size_t oldSize, size_t newSize)
{
    static if (WREN_DEBUG_TRACE_MEMORY)
    {
        import core.stdc.stdio : printf;
        printf("reallocate %p %lu . %lu",
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

// Captures the local variable [local] into an [Upvalue]. If that local is
// already in an upvalue, the existing one will be used. (This is important to
// ensure that multiple closures closing over the same variable actually see
// the same variable.) Otherwise, it will create a new open upvalue and add it
// the fiber's list of upvalues.
static ObjUpvalue* captureUpvalue(WrenVM* vm, ObjFiber* fiber, Value* local)
{
    // If there are no open upvalues at all, we must need a new one.
    if (fiber.openUpvalues == null)
    {
        fiber.openUpvalues = wrenNewUpvalue(vm, local);
        return fiber.openUpvalues;
    }

    ObjUpvalue* prevUpvalue = null;
    ObjUpvalue* upvalue = fiber.openUpvalues;

    // Walk towards the bottom of the stack until we find a previously existing
    // upvalue or pass where it should be.
    while (upvalue != null && upvalue.value > local)
    {
        prevUpvalue = upvalue;
        upvalue = upvalue.next;
    }

    // Found an existing upvalue for this local.
    if (upvalue != null && upvalue.value == local) return upvalue;

    // We've walked past this local on the stack, so there must not be an
    // upvalue for it already. Make a new one and link it in in the right
    // place to keep the list sorted.
    ObjUpvalue* createdUpvalue = wrenNewUpvalue(vm, local);
    if (prevUpvalue == null)
    {
        // The new one is the first one in the list.
        fiber.openUpvalues = createdUpvalue;
    }
    else
    {
        prevUpvalue.next = createdUpvalue;
    }

    createdUpvalue.next = upvalue;
    return createdUpvalue;
}

// Closes any open upvalues that have been created for stack slots at [last]
// and above.
static void closeUpvalues(ObjFiber* fiber, Value* last)
{
    while (fiber.openUpvalues != null &&
            fiber.openUpvalues.value >= last)
    {
        ObjUpvalue* upvalue = fiber.openUpvalues;

        // Move the value into the upvalue itself and point the upvalue to it.
        upvalue.closed = *upvalue.value;
        upvalue.value = &upvalue.closed;

        // Remove it from the open upvalue list.
        fiber.openUpvalues = upvalue.next;
    }
}

// Looks up a foreign method in [moduleName] on [className] with [signature].
//
// This will try the host's foreign method binder first. If that fails, it
// falls back to handling the built-in modules.
static WrenForeignMethodFn findForeignMethod(WrenVM* vm,
                                             const char* moduleName,
                                             const char* className,
                                             bool isStatic,
                                             const char* signature)
{
    WrenForeignMethodFn method = null;
    
    if (vm.config.bindForeignMethodFn != null)
    {
        method = vm.config.bindForeignMethodFn(vm, moduleName, className, isStatic,
                                                signature);
    }
    
    // If the host didn't provide it, see if it's an optional one.
    if (method == null)
    {
        import core.stdc.string : strcmp;
        static if (false) {
            if (strcmp(moduleName, "meta") == 0)
            {
                method = wrenMetaBindForeignMethod(vm, className, isStatic, signature);
            }
        }
        static if (false) {
            if (strcmp(moduleName, "random") == 0)
            {
                method = wrenRandomBindForeignMethod(vm, className, isStatic, signature);
            }
        }
    }

  return method;
}

// Defines [methodValue] as a method on [classObj].
//
// Handles both foreign methods where [methodValue] is a string containing the
// method's signature and Wren methods where [methodValue] is a function.
//
// Aborts the current fiber if the method is a foreign method that could not be
// found.
static void bindMethod(WrenVM* vm, int methodType, int symbol,
                       ObjModule* module_, ObjClass* classObj, Value methodValue)
{
    const(char)* className = classObj.name.value.ptr;
    if (methodType == Code.CODE_METHOD_STATIC) classObj = classObj.obj.classObj;

    Method method;
    if (IS_STRING(methodValue))
    {
        const(char)* name = AS_CSTRING(methodValue);
        method.type = MethodType.METHOD_FOREIGN;
        method.as.foreign = findForeignMethod(vm, module_.name.value.ptr,
                                            className,
                                            methodType == Code.CODE_METHOD_STATIC,
                                            name);

        if (method.as.foreign == null)
        {
            vm.fiber.error = wrenStringFormat(vm,
                "Could not find foreign method '@' for class $ in module '$'.".ptr,
                methodValue, classObj.name.value.ptr, module_.name.value.ptr);
            return;
        }
    }
    else
    {
        import wren.compiler : wrenBindMethodCode;

        method.as.closure = AS_CLOSURE(methodValue);
        method.type = MethodType.METHOD_BLOCK;

        // Patch up the bytecode now that we know the superclass.
        wrenBindMethodCode(classObj, method.as.closure.fn);
    }

    wrenBindMethod(vm, classObj, symbol, method);
}

static void callForeign(WrenVM* vm, ObjFiber* fiber,
                        WrenForeignMethodFn foreign, int numArgs)
{
    assert(vm.apiStack == null, "Cannot already be in foreign call.");
    vm.apiStack = fiber.stackTop - numArgs;

    foreign(vm);

    // Discard the stack slots for the arguments and temporaries but leave one
    // for the result.
    fiber.stackTop = vm.apiStack + 1;

    vm.apiStack = null;
}

// Handles the current fiber having aborted because of an error.
//
// Walks the call chain of fibers, aborting each one until it hits a fiber that
// handles the error. If none do, tells the VM to stop.
static void runtimeError(WrenVM* vm)
{
    assert(wrenHasError(vm.fiber), "Should only call this after an error.");

    ObjFiber* current = vm.fiber;
    Value error = current.error;
    
    while (current != null)
    {
        // Every fiber along the call chain gets aborted with the same error.
        current.error = error;

        // If the caller ran this fiber using "try", give it the error and stop.
        if (current.state == FiberState.FIBER_TRY)
        {
            // Make the caller's try method return the error message.
            current.caller.stackTop[-1] = vm.fiber.error;
            vm.fiber = current.caller;
            return;
        }
        
        // Otherwise, unhook the caller since we will never resume and return to it.
        ObjFiber* caller = current.caller;
        current.caller = null;
        current = caller;
    }

    // If we got here, nothing caught the error, so show the stack trace.
    import wren.dbg : wrenDebugPrintStackTrace;
    wrenDebugPrintStackTrace(vm);
    vm.fiber = null;
    vm.apiStack = null;
}

// Aborts the current fiber with an appropriate method not found error for a
// method with [symbol] on [classObj].
static void methodNotFound(WrenVM* vm, ObjClass* classObj, int symbol)
{
    vm.fiber.error = wrenStringFormat(vm, "@ does not implement '$'.".ptr,
        OBJ_VAL(classObj.name), vm.methodNames.data[symbol].value.ptr);
}

// Looks up the previously loaded module with [name].
//
// Returns `null` if no module with that name has been loaded.
static ObjModule* getModule(WrenVM* vm, Value name)
{
    Value moduleValue = wrenMapGet(vm.modules, name);
    return !IS_UNDEFINED(moduleValue) ? AS_MODULE(moduleValue) : null;
}

static ObjClosure* compileInModule(WrenVM* vm, Value name, const char* source,
                                   bool isExpression, bool printErrors)
{
    // See if the module has already been loaded.
    ObjModule* module_ = getModule(vm, name);
    if (module_ == null)
    {
        module_ = wrenNewModule(vm, AS_STRING(name));

        // It's possible for the wrenMapSet below to resize the modules map,
        // and trigger a GC while doing so. When this happens it will collect
        // the module we've just created. Once in the map it is safe.
        wrenPushRoot(vm, cast(Obj*)module_);

        // Store it in the VM's module registry so we don't load the same module
        // multiple times.
        wrenMapSet(vm, vm.modules, name, OBJ_VAL(module_));

        wrenPopRoot(vm);

        // Implicitly import the core module.
        ObjModule* coreModule = getModule(vm, NULL_VAL);
        for (int i = 0; i < coreModule.variables.count; i++)
        {
            wrenDefineVariable(vm, module_,
                                coreModule.variableNames.data[i].value.ptr,
                                coreModule.variableNames.data[i].length,
                                coreModule.variables.data[i], null);
        }
    }

    import wren.compiler : wrenCompile;
    ObjFn* fn = wrenCompile(vm, module_, source, isExpression, printErrors);
    if (fn == null)
    {
        // TODO: Should we still store the module even if it didn't compile?
        return null;
    }

    // Functions are always wrapped in closures.
    wrenPushRoot(vm, cast(Obj*)fn);
    ObjClosure* closure = wrenNewClosure(vm, fn);
    wrenPopRoot(vm); // fn.

    return closure;
}

// Verifies that [superclassValue] is a valid object to inherit from. That
// means it must be a class and cannot be the class of any built-in type.
//
// Also validates that it doesn't result in a class with too many fields and
// the other limitations foreign classes have.
//
// If successful, returns `null`. Otherwise, returns a string for the runtime
// error message.
static Value validateSuperclass(WrenVM* vm, Value name, Value superclassValue,
                                int numFields)
{
  // Make sure the superclass is a class.
  if (!IS_CLASS(superclassValue))
  {
    return wrenStringFormat(vm,
        "Class '@' cannot inherit from a non-class object.".ptr,
        name);
  }

  // Make sure it doesn't inherit from a sealed built-in type. Primitive methods
  // on these classes assume the instance is one of the other Obj___ types and
  // will fail horribly if it's actually an ObjInstance.
  ObjClass* superclass = AS_CLASS(superclassValue);
  if (superclass == vm.classClass ||
      superclass == vm.fiberClass ||
      superclass == vm.fnClass || // Includes OBJ_CLOSURE.
      superclass == vm.listClass ||
      superclass == vm.mapClass ||
      superclass == vm.rangeClass ||
      superclass == vm.stringClass ||
      superclass == vm.boolClass ||
      superclass == vm.nullClass ||
      superclass == vm.numClass)
  {
    return wrenStringFormat(vm,
        "Class '@' cannot inherit from built-in class '@'.",
        name, OBJ_VAL(superclass.name));
  }

  if (superclass.numFields == -1)
  {
    return wrenStringFormat(vm,
        "Class '@' cannot inherit from foreign class '@'.",
        name, OBJ_VAL(superclass.name));
  }

  if (numFields == -1 && superclass.numFields > 0)
  {
    return wrenStringFormat(vm,
        "Foreign class '@' may not inherit from a class with fields.",
        name);
  }

  if (superclass.numFields + numFields > MAX_FIELDS)
  {
    return wrenStringFormat(vm,
        "Class '@' may not have more than 255 fields, including inherited "
        ~ "ones.", name);
  }

  return NULL_VAL;
}

static void bindForeignClass(WrenVM* vm, ObjClass* classObj, ObjModule* module_)
{
    WrenForeignClassMethods methods;
    methods.allocate = null;
    methods.finalize = null;
    
    // Check the optional built-in module first so the host can override it.
    
    if (vm.config.bindForeignClassFn != null)
    {
        methods = vm.config.bindForeignClassFn(vm, module_.name.value.ptr,
                                                classObj.name.value.ptr);
    }

    // If the host didn't provide it, see if it's a built in optional module.
    if (cast(Value)methods.allocate == NULL_VAL && methods.finalize == null)
    {
    // #if WREN_OPT_RANDOM
        static if (false) {
            if (strcmp(module_.name.value, "random") == 0)
            {
                methods = wrenRandomBindForeignClass(vm, module_.name.value,
                                                classObj.name.value);
            }
        }
    }
    
    Method method;
    method.type = MethodType.METHOD_FOREIGN;

    // Add the symbol even if there is no allocator so we can ensure that the
    // symbol itself is always in the symbol table.
    int symbol = wrenSymbolTableEnsure(vm, &vm.methodNames, "<allocate>", 10);
    if (methods.allocate != null)
    {
        method.as.foreign = methods.allocate;
        wrenBindMethod(vm, classObj, symbol, method);
    }
    
    // Add the symbol even if there is no finalizer so we can ensure that the
    // symbol itself is always in the symbol table.
    symbol = wrenSymbolTableEnsure(vm, &vm.methodNames, "<finalize>", 10);
    if (methods.finalize != null)
    {
        method.as.foreign = cast(WrenForeignMethodFn)methods.finalize;
        wrenBindMethod(vm, classObj, symbol, method);
    }
}

// Completes the process for creating a new class.
//
// The class attributes instance and the class itself should be on the 
// top of the fiber's stack. 
//
// This process handles moving the attribute data for a class from
// compile time to runtime, since it now has all the attributes associated
// with a class, including for methods.
static void endClass(WrenVM* vm) 
{
  // Pull the attributes and class off the stack
  Value attributes = vm.fiber.stackTop[-2];
  Value classValue = vm.fiber.stackTop[-1];

  // Remove the stack items
  vm.fiber.stackTop -= 2;

  ObjClass* classObj = AS_CLASS(classValue);
    classObj.attributes = attributes;
}

// Creates a new class.
//
// If [numFields] is -1, the class is a foreign class. The name and superclass
// should be on top of the fiber's stack. After calling this, the top of the
// stack will contain the new class.
//
// Aborts the current fiber if an error occurs.
static void createClass(WrenVM* vm, int numFields, ObjModule* module_)
{
    // Pull the name and superclass off the stack.
    Value name = vm.fiber.stackTop[-2];
    Value superclass = vm.fiber.stackTop[-1];

    // We have two values on the stack and we are going to leave one, so discard
    // the other slot.
    vm.fiber.stackTop--;

    vm.fiber.error = validateSuperclass(vm, name, superclass, numFields);
    if (wrenHasError(vm.fiber)) return;

    ObjClass* classObj = wrenNewClass(vm, AS_CLASS(superclass), numFields,
                                        AS_STRING(name));
    vm.fiber.stackTop[-1] = OBJ_VAL(classObj);

    if (numFields == -1) bindForeignClass(vm, classObj, module_);
}

static void createForeign(WrenVM* vm, ObjFiber* fiber, Value* stack)
{
    ObjClass* classObj = AS_CLASS(stack[0]);
    assert(classObj.numFields == -1, "Class must be a foreign class.");

    // TODO: Don't look up every time.
    int symbol = wrenSymbolTableFind(&vm.methodNames, "<allocate>", 10);
    assert(symbol != -1, "Should have defined <allocate> symbol.");

    assert(classObj.methods.count > symbol, "Class should have allocator.");
    Method* method = &classObj.methods.data[symbol];
    assert(method.type == MethodType.METHOD_FOREIGN, "Allocator should be foreign.");

    // Pass the constructor arguments to the allocator as well.
    assert(vm.apiStack == null, "Cannot already be in foreign call.");
    vm.apiStack = stack;

    method.as.foreign(vm);

    vm.apiStack = null;
}

void wrenFinalizeForeign(WrenVM* vm, ObjForeign* foreign)
{
    // TODO: Don't look up every time.
    int symbol = wrenSymbolTableFind(&vm.methodNames, "<finalize>", 10);
    assert(symbol != -1, "Should have defined <finalize> symbol.");

    // If there are no finalizers, don't finalize it.
    if (symbol == -1) return;

    // If the class doesn't have a finalizer, bail out.
    ObjClass* classObj = foreign.obj.classObj;
    if (symbol >= classObj.methods.count) return;

    Method* method = &classObj.methods.data[symbol];
    if (method.type == MethodType.METHOD_NONE) return;

    assert(method.type == MethodType.METHOD_FOREIGN, "Finalizer should be foreign.");

    WrenFinalizerFn finalizer = cast(WrenFinalizerFn)method.as.foreign;
    finalizer(foreign.data.ptr);
}

// Let the host resolve an imported module name if it wants to.
static Value resolveModule(WrenVM* vm, Value name)
{
    // If the host doesn't care to resolve, leave the name alone.
    if (vm.config.resolveModuleFn == null) return name;

    ObjFiber* fiber = vm.fiber;
    ObjFn* fn = fiber.frames[fiber.numFrames - 1].closure.fn;
    ObjString* importer = fn.module_.name;
    
    const(char)* resolved = vm.config.resolveModuleFn(vm, importer.value.ptr,
                                                        AS_CSTRING(name));
    if (resolved == null)
    {
        vm.fiber.error = wrenStringFormat(vm,
            "Could not resolve module '@' imported from '@'.",
            name, OBJ_VAL(importer));
        return NULL_VAL;
    }
    
    // If they resolved to the exact same string, we don't need to copy it.
    if (resolved == AS_CSTRING(name)) return name;

    // Copy the string into a Wren String object.
    name = wrenNewString(vm, resolved);
    DEALLOCATE(vm, cast(char*)resolved);
    return name;
}

static Value importModule(WrenVM* vm, Value name)
{
    name = resolveModule(vm, name);
    
    // If the module is already loaded, we don't need to do anything.
    Value existing = wrenMapGet(vm.modules, name);
    if (!IS_UNDEFINED(existing)) return existing;

    wrenPushRoot(vm, AS_OBJ(name));

    WrenLoadModuleResult result = WrenLoadModuleResult(null, null, null);
    const(char)* source = null;
    
    // Let the host try to provide the module.
    if (vm.config.loadModuleFn != null)
    {
        result = vm.config.loadModuleFn(vm, AS_CSTRING(name));
    }
    
    // If the host didn't provide it, see if it's a built in optional module.
    if (result.source == null)
    {
        import core.stdc.string : strcmp;
        result.onComplete = null;
        ObjString* nameString = AS_STRING(name);
        static if (false) {
            if (strcmp(nameString.value, "meta") == 0) result.source = wrenMetaSource();
        }
        static if (false) {
            if (strcmp(nameString.value, "random") == 0) result.source = wrenRandomSource();
        }
    }
    
    if (result.source == null)
    {
        vm.fiber.error = wrenStringFormat(vm, "Could not load module '@'.", name);
        wrenPopRoot(vm); // name.
        return NULL_VAL;
    }
    
    ObjClosure* moduleClosure = compileInModule(vm, name, result.source, false, true);
    
    // Now that we're done, give the result back in case there's cleanup to do.
    if(result.onComplete) result.onComplete(vm, AS_CSTRING(name), result);
    
    if (moduleClosure == null)
    {
        vm.fiber.error = wrenStringFormat(vm,
                                            "Could not compile module '@'.", name);
        wrenPopRoot(vm); // name.
        return NULL_VAL;
    }

    wrenPopRoot(vm); // name.

    // Return the closure that executes the module.
    return OBJ_VAL(moduleClosure);
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

static bool checkArity(WrenVM* vm, Value value, int numArgs)
{
    assert(IS_CLOSURE(value), "Receiver must be a closure.");
    ObjFn* fn = AS_CLOSURE(value).fn;

    // We only care about missing arguments, not extras. The "- 1" is because
    // numArgs includes the receiver, the function itself, which we don't want to
    // count.
    if (numArgs - 1 >= fn.arity) return true;

    vm.fiber.error = CONST_STRING(vm, "Function expects more arguments.");
    return false;
}

// The main bytecode interpreter loop. This is where the magic happens. It is
// also, as you can imagine, highly performance critical.
// Arg... thar be dragons here.
static WrenInterpretResult runInterpreter(WrenVM* vm, ObjFiber* fiber)
{
    // Remember the current fiber so we can find it if a GC happens.
    vm.fiber = fiber;
    fiber.state = FiberState.FIBER_ROOT;

    // Hoist these into local variables. They are accessed frequently in the loop
    // but assigned less frequently. Keeping them in locals and updating them when
    // a call frame has been pushed or popped gives a large speed boost.
    CallFrame* frame;
    Value* stackStart;
    ubyte* ip;
    ObjFn* fn;

    // These are a part of the CALL args,
    // but cannot be defined within the switch statement itself.
    int numArgs;
    int symbol;
    Value* args;
    ObjClass* classObj;
    Method* method;

    // These macros are designed to only be invoked within this function.
    void PUSH(Value value) {
        *fiber.stackTop++ = value;
    }

    Value POP() {
        return (*(--fiber.stackTop));
    }

    void DROP() {
        fiber.stackTop--;
    }

    Value PEEK() {
        return (*(fiber.stackTop - 1));
    }

    Value PEEK2() {
        return (*(fiber.stackTop - 2));
    }

    ubyte READ_BYTE() {
        return (*ip++);
    }

    ushort READ_SHORT() {
        ip += 2;
        return cast(ushort)((ip[-2] << 8) | ip[-1]);
    }

    // Use this before a CallFrame is pushed to store the local variables back
    // into the current one.
    void STORE_FRAME() {
        frame.ip = ip;
    }

    // Use this after a CallFrame has been pushed or popped to refresh the local
    // variables.
    void LOAD_FRAME() {
        frame = &fiber.frames[fiber.numFrames - 1];
        stackStart = frame.stackStart;
        ip = frame.ip;
        fn = frame.closure.fn;
    }

    // Terminates the current fiber with error string [error]. If another calling
    // fiber is willing to catch the error, transfers control to it, otherwise
    // exits the interpreter.
    string RUNTIME_ERROR() {
        return q{
            STORE_FRAME();
            runtimeError(vm);
            if (vm.fiber == null) return WrenInterpretResult.WREN_RESULT_RUNTIME_ERROR;
            fiber = vm.fiber;
            LOAD_FRAME();
            goto loop;
        };
    }

    LOAD_FRAME();
    Code instruction;
loop:
    switch (instruction = cast(Code)READ_BYTE()) with(Code)
    {
        case CODE_LOAD_LOCAL_0:
        case CODE_LOAD_LOCAL_1:
        case CODE_LOAD_LOCAL_2:
        case CODE_LOAD_LOCAL_3:
        case CODE_LOAD_LOCAL_4:
        case CODE_LOAD_LOCAL_5:
        case CODE_LOAD_LOCAL_6:
        case CODE_LOAD_LOCAL_7:
        case CODE_LOAD_LOCAL_8:
            PUSH(stackStart[instruction - CODE_LOAD_LOCAL_0]);
            goto loop;
        
        case CODE_LOAD_LOCAL:
            PUSH(stackStart[READ_BYTE()]);
            goto loop;

        case CODE_LOAD_FIELD_THIS: {
            ubyte field = READ_BYTE();
            Value receiver = stackStart[0];
            assert(IS_INSTANCE(receiver), "Receiver should be instance.");
            ObjInstance* instance = AS_INSTANCE(receiver);
            assert(field < instance.obj.classObj.numFields, "Out of bounds field.");
            PUSH(instance.fields[field]);
            goto loop;
        }
        
        case CODE_POP:
            DROP();
            goto loop;
        
        case CODE_NULL:
            PUSH(NULL_VAL);
            goto loop;

        case CODE_FALSE:
            PUSH(FALSE_VAL);
            goto loop;
        
        case CODE_TRUE:
            PUSH(TRUE_VAL);
            goto loop;

        case CODE_STORE_LOCAL:
            stackStart[READ_BYTE()] = PEEK();
            goto loop;
        
        case CODE_CONSTANT:
            PUSH(fn.constants.data[READ_SHORT()]);
            goto loop;

        // The opcodes for doing method and superclass calls share a lot of code.
        // However, doing an if() test in the middle of the instruction sequence
        // to handle the bit that is special to super calls makes the non-super
        // call path noticeably slower.
        //
        // Instead, we do this old school using an explicit goto to share code for
        // everything at the tail end of the call-handling code that is the same
        // between normal and superclass calls.

        case CODE_CALL_0:
        case CODE_CALL_1:
        case CODE_CALL_2:
        case CODE_CALL_3:
        case CODE_CALL_4:
        case CODE_CALL_5:
        case CODE_CALL_6:
        case CODE_CALL_7:
        case CODE_CALL_8:
        case CODE_CALL_9:
        case CODE_CALL_10:
        case CODE_CALL_11:
        case CODE_CALL_12:
        case CODE_CALL_13:
        case CODE_CALL_14:
        case CODE_CALL_15:
        case CODE_CALL_16:
            // Add one for the implicit receiver argument.
            numArgs = instruction - CODE_CALL_0 + 1;
            symbol = READ_SHORT();
            
            // The receiver is the first argument.
            args = fiber.stackTop - numArgs;
            classObj = wrenGetClassInline(vm, args[0]);
            goto completeCall;

        case CODE_SUPER_0:
        case CODE_SUPER_1:
        case CODE_SUPER_2:
        case CODE_SUPER_3:
        case CODE_SUPER_4:
        case CODE_SUPER_5:
        case CODE_SUPER_6:
        case CODE_SUPER_7:
        case CODE_SUPER_8:
        case CODE_SUPER_9:
        case CODE_SUPER_10:
        case CODE_SUPER_11:
        case CODE_SUPER_12:
        case CODE_SUPER_13:
        case CODE_SUPER_14:
        case CODE_SUPER_15:
        case CODE_SUPER_16:
        {
            // Add one for the implicit receiver argument.
            numArgs = instruction - CODE_SUPER_0 + 1;
            symbol = READ_SHORT();

            // The receiver is the first argument.
            args = fiber.stackTop - numArgs;

            // The superclass is stored in a constant.
            classObj = AS_CLASS(fn.constants.data[READ_SHORT()]);
            goto completeCall;

        completeCall:
            {
                // If the class's method table doesn't include the symbol, bail.
                if (symbol >= classObj.methods.count ||
                    (method = &classObj.methods.data[symbol]).type == MethodType.METHOD_NONE)
                    {
                        methodNotFound(vm, classObj, symbol);
                        mixin(RUNTIME_ERROR);
                    }

                switch (method.type) with(MethodType) {
                    case METHOD_PRIMITIVE: {
                        if (method.as.primitive(vm, args))
                        {
                            // The result is now in the first arg slot. Discard the other
                            // stack slots.
                            fiber.stackTop -= numArgs - 1;
                        } else {
                            // An error, fiber switch, or call frame change occurred.
                            STORE_FRAME();

                            // If we don't have a fiber to switch to, stop interpreting.
                            fiber = vm.fiber;
                            if (fiber == null) return WrenInterpretResult.WREN_RESULT_SUCCESS;
                            if (wrenHasError(fiber)) RUNTIME_ERROR();
                            LOAD_FRAME();
                        }
                        break;
                    }

                    case METHOD_FUNCTION_CALL: {
                        if (!checkArity(vm, args[0], numArgs)) {
                            mixin(RUNTIME_ERROR);
                        }

                        STORE_FRAME();
                        method.as.primitive(vm, args);
                        LOAD_FRAME();
                        break;
                    }

                    case METHOD_FOREIGN: {
                        callForeign(vm, fiber, method.as.foreign, numArgs);
                        if (wrenHasError(fiber)) {
                            mixin(RUNTIME_ERROR);
                        }
                        break;
                    }

                    case METHOD_BLOCK: {
                        STORE_FRAME();
                        wrenCallFunction(vm, fiber, cast(ObjClosure*)method.as.closure, numArgs);
                        LOAD_FRAME();
                        break;
                    }
                    default:
                        assert(0, "Unreachable");

                }
                goto loop;
            }
        }

        case CODE_LOAD_UPVALUE:
        {
            ObjUpvalue** upvalues = frame.closure.upvalues.ptr;
            PUSH(*upvalues[READ_BYTE()].value);
            goto loop;
        }

        case CODE_STORE_UPVALUE:
        {
            ObjUpvalue** upvalues = frame.closure.upvalues.ptr;
            *upvalues[READ_BYTE()].value = PEEK();
            goto loop;
        }

        case CODE_LOAD_MODULE_VAR:
            PUSH(fn.module_.variables.data[READ_SHORT()]);
            goto loop;

        case CODE_STORE_MODULE_VAR:
            fn.module_.variables.data[READ_SHORT()] = PEEK();
            goto loop;

        case CODE_STORE_FIELD_THIS:
        {
            ubyte field = READ_BYTE();
            Value receiver = stackStart[0];
            assert(IS_INSTANCE(receiver), "Receiver should be instance.");
            ObjInstance* instance = AS_INSTANCE(receiver);
            assert(field < instance.obj.classObj.numFields, "Out of bounds field.");
            instance.fields[field] = PEEK();
            goto loop;
        }

        case CODE_LOAD_FIELD:
        {
            ubyte field = READ_BYTE();
            Value receiver = POP();
            assert(IS_INSTANCE(receiver), "Receiver should be instance.");
            ObjInstance* instance = AS_INSTANCE(receiver);
            assert(field < instance.obj.classObj.numFields, "Out of bounds field.");
            PUSH(instance.fields[field]);
            goto loop;
        }

        case CODE_STORE_FIELD:
        {
            ubyte field = READ_BYTE();
            Value receiver = POP();
            assert(IS_INSTANCE(receiver), "Receiver should be instance.");
            ObjInstance* instance = AS_INSTANCE(receiver);
            assert(field < instance.obj.classObj.numFields, "Out of bounds field.");
            instance.fields[field] = PEEK();
            goto loop;
        }

        case CODE_JUMP:
        {
            ushort offset = READ_SHORT();
            ip += offset;
            goto loop;
        }

        case CODE_LOOP:
        {
            // Jump back to the top of the loop.
            ushort offset = READ_SHORT();
            ip -= offset;
            goto loop;
        }

        case CODE_JUMP_IF:
        {
            ushort offset = READ_SHORT();
            Value condition = POP();

            if (wrenIsFalsyValue(condition)) ip += offset;
            goto loop;
        }

        case CODE_AND:
        {
            ushort offset = READ_SHORT();
            Value condition = PEEK();

            if (wrenIsFalsyValue(condition))
            {
                // Short-circuit the right hand side.
                ip += offset;
            }
            else
            {
                // Discard the condition and evaluate the right hand side.
                DROP();
            }
            goto loop;
        }

        case CODE_OR:
        {
            ushort offset = READ_SHORT();
            Value condition = PEEK();

            if (wrenIsFalsyValue(condition))
            {
                // Discard the condition and evaluate the right hand side.
                DROP();
            }
            else
            {
                // Short-circuit the right hand side.
                ip += offset;
            }
            goto loop;
        }

        case CODE_RETURN:
        {
            Value result = POP();
            fiber.numFrames--;

            // Close any upvalues still in scope.
            closeUpvalues(fiber, stackStart);

            // If the fiber is complete, end it.
            if (fiber.numFrames == 0)
            {
                // See if there's another fiber to return to. If not, we're done.
                if (fiber.caller == null)
                {
                    // Store the final result value at the beginning of the stack so the
                    // C API can get it.
                    fiber.stack[0] = result;
                    fiber.stackTop = fiber.stack + 1;
                    return WrenInterpretResult.WREN_RESULT_SUCCESS;
                }

                ObjFiber* resumingFiber = fiber.caller;
                fiber.caller = null;
                fiber = resumingFiber;
                vm.fiber = resumingFiber;

                // Store the result in the resuming fiber.
                fiber.stackTop[-1] = result;
            }
            else
            {
                // Store the result of the block in the first slot, which is where
                // the caller expects it.
                stackStart[0] = result;

                // Discard the stack slots for the call frame (leaving one slot for the
                // result).
                fiber.stackTop = frame.stackStart + 1;
            }

            LOAD_FRAME();
            goto loop;
        }

        case CODE_CONSTRUCT:
            assert(IS_CLASS(stackStart[0]), "'this' should be a class.");
            stackStart[0] = wrenNewInstance(vm, AS_CLASS(stackStart[0]));
            goto loop;

        case CODE_FOREIGN_CONSTRUCT:
            assert(IS_CLASS(stackStart[0]), "'this' should be a class.");
            createForeign(vm, fiber, stackStart);
            if (wrenHasError(fiber)) {
                mixin(RUNTIME_ERROR);
            }
            goto loop;

        case CODE_CLOSURE:
        {
            // Create the closure and push it on the stack before creating upvalues
            // so that it doesn't get collected.
            ObjFn* fnC = AS_FN(fn.constants.data[READ_SHORT()]);
            ObjClosure* closure = wrenNewClosure(vm, fnC);
            PUSH(OBJ_VAL(closure));

            // Capture upvalues, if any.
            for (int i = 0; i < fnC.numUpvalues; i++)
            {
                ubyte isLocal = READ_BYTE();
                ubyte index = READ_BYTE();
                if (isLocal)
                {
                    // Make an new upvalue to close over the parent's local variable.
                    closure.upvalues[i] = captureUpvalue(vm, fiber, frame.stackStart + index);
                }
                else
                {
                    // Use the same upvalue as the current call frame.
                    closure.upvalues[i] = frame.closure.upvalues[index];
                }
            }
            goto loop;
        }

        case CODE_END_CLASS:
        {
            endClass(vm);
            if (wrenHasError(fiber))
            {
                mixin(RUNTIME_ERROR);
            }
            goto loop;
        }

        case CODE_CLASS:
        {
            createClass(vm, READ_BYTE(), null);
            if (wrenHasError(fiber))
            {
                mixin(RUNTIME_ERROR);
            }
            goto loop;
        }

        case CODE_FOREIGN_CLASS:
        {
            createClass(vm, -1, fn.module_);
            if (wrenHasError(fiber)) {
                mixin(RUNTIME_ERROR);
            }
            goto loop;
        }

        case CODE_METHOD_INSTANCE:
        case CODE_METHOD_STATIC:
        {
            ushort methodSymbol = READ_SHORT();
            ObjClass* methodClassObj = AS_CLASS(PEEK());
            Value methodValue = PEEK2();
            bindMethod(vm, instruction, methodSymbol, fn.module_, methodClassObj, methodValue);
            if (wrenHasError(fiber)) {
                mixin(RUNTIME_ERROR);
            }
            DROP();
            DROP();
            goto loop;
        }

        case CODE_END_MODULE:
        {
            vm.lastModule = fn.module_;
            PUSH(NULL_VAL);
            goto loop;
        }

        case CODE_IMPORT_MODULE:
        {
            // Make a slot on the stack for the module's fiber to place the return
            // value. It will be popped after this fiber is resumed. Store the
            // imported module's closure in the slot in case a GC happens when
            // invoking the closure.
            PUSH(importModule(vm, fn.constants.data[READ_SHORT()]));
            if (wrenHasError(fiber)) {
                mixin(RUNTIME_ERROR);
            }

            // If we get a closure, call it to execute the module body.
            if (IS_CLOSURE(PEEK()))
            {
                STORE_FRAME();
                ObjClosure* closure = AS_CLOSURE(PEEK());
                wrenCallFunction(vm, fiber, closure, 1);
                LOAD_FRAME();
            }
            else
            {
                // The module has already been loaded. Remember it so we can import
                // variables from it if needed.
                vm.lastModule = AS_MODULE(PEEK());
            }

            goto loop;
        }

        case CODE_IMPORT_VARIABLE:
        {
            Value variable = fn.constants.data[READ_SHORT()];
            assert(vm.lastModule != null, "Should have already imported module.");
            Value result = getModuleVariable(vm, vm.lastModule, variable);
            if (wrenHasError(fiber)) {
                mixin(RUNTIME_ERROR);
            }

            PUSH(result);
            goto loop;
        }

        case CODE_END:
            assert(0, "Unreachable");

        default:
            assert(0, "Unhandled instruction");
    }
}

WrenHandle* wrenMakeCallHandle(WrenVM* vm, const(char)* signature)
{
    import core.stdc.string : strlen;
    assert(signature != null, "Signature cannot be NULL.");
    
    int signatureLength = cast(int)strlen(signature);
    assert(signatureLength > 0, "Signature cannot be empty.");
    
    // Count the number parameters the method expects.
    int numParams = 0;
    if (signature[signatureLength - 1] == ')')
    {
        for (int i = signatureLength - 1; i > 0 && signature[i] != '('; i--)
        {
            if (signature[i] == '_') numParams++;
        }
    }
    
    // Count subscript arguments.
    if (signature[0] == '[')
    {
        for (int i = 0; i < signatureLength && signature[i] != ']'; i++)
        {
            if (signature[i] == '_') numParams++;
        }
    }
    
    // Add the signatue to the method table.
    int method =  wrenSymbolTableEnsure(vm, &vm.methodNames,
                                        signature, signatureLength);
    
    // Create a little stub function that assumes the arguments are on the stack
    // and calls the method.
    ObjFn* fn = wrenNewFunction(vm, null, numParams + 1);
    
    // Wrap the function in a closure and then in a handle. Do this here so it
    // doesn't get collected as we fill it in.
    WrenHandle* value = wrenMakeHandle(vm, OBJ_VAL(fn));
    value.value = OBJ_VAL(wrenNewClosure(vm, fn));
    
    wrenByteBufferWrite(vm, &fn.code, cast(ubyte)(Code.CODE_CALL_0 + numParams));
    wrenByteBufferWrite(vm, &fn.code, (method >> 8) & 0xff);
    wrenByteBufferWrite(vm, &fn.code, method & 0xff);
    wrenByteBufferWrite(vm, &fn.code, Code.CODE_RETURN);
    wrenByteBufferWrite(vm, &fn.code, Code.CODE_END);
    wrenIntBufferFill(vm, &fn.debug_.sourceLines, 0, 5);
    wrenFunctionBindName(vm, fn, signature, signatureLength);

    return value;
}

WrenInterpretResult wrenCall(WrenVM* vm, WrenHandle* method)
{
    assert(method != null, "Method cannot be NULL.");
    assert(IS_CLOSURE(method.value), "Method must be a method handle.");
    assert(vm.fiber != null, "Must set up arguments for call first.");
    assert(vm.apiStack != null, "Must set up arguments for call first.");
    assert(vm.fiber.numFrames == 0, "Can not call from a foreign method.");
    
    ObjClosure* closure = AS_CLOSURE(method.value);
    
    assert(vm.fiber.stackTop - vm.fiber.stack >= closure.fn.arity,
            "Stack must have enough arguments for method.");
    
    // Clear the API stack. Now that wrenCall() has control, we no longer need
    // it. We use this being non-null to tell if re-entrant calls to foreign
    // methods are happening, so it's important to clear it out now so that you
    // can call foreign methods from within calls to wrenCall().
    vm.apiStack = null;

    // Discard any extra temporary slots. We take for granted that the stub
    // function has exactly one slot for each argument.
    vm.fiber.stackTop = &vm.fiber.stack[closure.fn.maxSlots];
    
    wrenCallFunction(vm, vm.fiber, closure, 0);
    WrenInterpretResult result = runInterpreter(vm, vm.fiber);
    
    // If the call didn't abort, then set up the API stack to point to the
    // beginning of the stack so the host can access the call's return value.
    if (vm.fiber != null) vm.apiStack = vm.fiber.stack;
    
    return result;
}

WrenHandle* wrenMakeHandle(WrenVM* vm, Value value)
{
    if (IS_OBJ(value)) wrenPushRoot(vm, AS_OBJ(value));
    
    // Make a handle for it.
    WrenHandle* handle = ALLOCATE!(WrenVM, WrenHandle)(vm);
    handle.value = value;

    if (IS_OBJ(value)) wrenPopRoot(vm);

    // Add it to the front of the linked list of handles.
    if (vm.handles != null) vm.handles.prev = handle;
    handle.prev = null;
    handle.next = vm.handles;
    vm.handles = handle;
    
    return handle;
}

void wrenReleaseHandle(WrenVM* vm, WrenHandle* handle)
{
    assert(handle != null, "Handle cannot be NULL.");

    // Update the VM's head pointer if we're releasing the first handle.
    if (vm.handles == handle) vm.handles = handle.next;

    // Unlink it from the list.
    if (handle.prev != null) handle.prev.next = handle.next;
    if (handle.next != null) handle.next.prev = handle.prev;

    // Clear it out. This isn't strictly necessary since we're going to free it,
    // but it makes for easier debugging.
    handle.prev = null;
    handle.next = null;
    handle.value = NULL_VAL;
    DEALLOCATE(vm, handle);
}

WrenInterpretResult wrenInterpret(WrenVM* vm, const(char)* module_,
                                  const(char)* source)
{
    ObjClosure* closure = wrenCompileSource(vm, module_, source, false, true);
    if (closure == null) return WrenInterpretResult.WREN_RESULT_COMPILE_ERROR;
    
    wrenPushRoot(vm, cast(Obj*)closure);
    ObjFiber* fiber = wrenNewFiber(vm, closure);
    wrenPopRoot(vm); // closure.
    vm.apiStack = null;

    return runInterpreter(vm, fiber);
}

ObjClosure* wrenCompileSource(WrenVM* vm, const(char)* module_, const(char)* source,
                            bool isExpression, bool printErrors)
{
    Value nameValue = NULL_VAL;
    if (module_ != null)
    {
        nameValue = wrenNewString(vm, module_);
        wrenPushRoot(vm, AS_OBJ(nameValue));
    }
    
    ObjClosure* closure = compileInModule(vm, nameValue, source,
                                            isExpression, printErrors);

    if (module_ != null) wrenPopRoot(vm); // nameValue.
    return closure;
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

static void wrenCallFunction(WrenVM* vm, ObjFiber* fiber,
                                    ObjClosure* closure, int numArgs)
{
    // Grow the call frame array if needed.
    if (fiber.numFrames + 1 > fiber.frameCapacity)
    {
        int max = fiber.frameCapacity * 2;
        fiber.frames = cast(CallFrame*)wrenReallocate(vm, fiber.frames,
            CallFrame.sizeof * fiber.frameCapacity, CallFrame.sizeof * max);
        fiber.frameCapacity = max;
    }
    
    // Grow the stack if needed.
    int stackSize = cast(int)(fiber.stackTop - fiber.stack);
    int needed = stackSize + closure.fn.maxSlots;
    wrenEnsureStack(vm, fiber, needed);
    
    wrenAppendCallFrame(vm, fiber, closure, fiber.stackTop - numArgs);
}

// TODO: Inline?
void wrenPushRoot(WrenVM* vm, Obj* obj)
{
    assert(obj != null, "Cannot root null");
    assert(vm.numTempRoots < WREN_MAX_TEMP_ROOTS, "Too many temporary roots.");

    vm.tempRoots[vm.numTempRoots++] = obj;
}

void wrenPopRoot(WrenVM* vm)
{
    assert(vm.numTempRoots > 0, "No temporary roots to release.");
    vm.numTempRoots--;
}

ObjClass* wrenGetClass(WrenVM* vm, Value value)
{
    return wrenGetClassInline(vm, value);
}

// Returns the class of [value].
//
// Defined here instead of in wren_value.h because it's critical that this be
// inlined. That means it must be defined in the header, but the wren_value.h
// header doesn't have a full definitely of WrenVM yet.
static ObjClass* wrenGetClassInline(WrenVM* vm, Value value)
{
    if (IS_NUM(value)) return vm.numClass;
    if (IS_OBJ(value)) return AS_OBJ(value).classObj;

    static if (WREN_NAN_TAGGING) {
        switch (GET_TAG(value))
        {
            case TAG_FALSE:     return vm.boolClass;
            case TAG_NAN:       return vm.numClass;
            case TAG_NULL:      return vm.nullClass;
            case TAG_TRUE:      return vm.boolClass;
            case TAG_UNDEFINED: assert(0, "Unreachable");
            default: assert(0, "Unhandled tag?");
        }
    } else { 
        switch (value.type)
        {
            case VAL_FALSE:     return vm.boolClass;
            case VAL_NULL:      return vm.nullClass;
            case VAL_NUM:       return vm.numClass;
            case VAL_TRUE:      return vm.boolClass;
            case VAL_OBJ:       return AS_OBJ(value).classObj;
            case VAL_UNDEFINED: assert(0, "Unreachable");
        }
    }
    assert(0, "Unreachable");
}

int wrenGetSlotCount(WrenVM* vm)
{
    if (vm.apiStack == null) return 0;
  
    return cast(int)(vm.fiber.stackTop - vm.apiStack);
}

void wrenEnsureSlots(WrenVM* vm, int numSlots)
{
    // If we don't have a fiber accessible, create one for the API to use.
    if (vm.apiStack == null)
    {
        vm.fiber = wrenNewFiber(vm, null);
        vm.apiStack = vm.fiber.stack;
    }
    
    int currentSize = cast(int)(vm.fiber.stackTop - vm.apiStack);
    if (currentSize >= numSlots) return;
    
    // Grow the stack if needed.
    int needed = cast(int)(vm.apiStack - vm.fiber.stack) + numSlots;
    wrenEnsureStack(vm, vm.fiber, needed);
    
    vm.fiber.stackTop = vm.apiStack + numSlots;
}

// Ensures that [slot] is a valid index into the API's stack of slots.
static void validateApiSlot(WrenVM* vm, int slot)
{
    assert(slot >= 0, "Slot cannot be negative.");
    assert(slot < wrenGetSlotCount(vm), "Not that many slots.");
}

// Gets the type of the object in [slot].
WrenType wrenGetSlotType(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    if (IS_BOOL(vm.apiStack[slot])) return WrenType.WREN_TYPE_BOOL;
    if (IS_NUM(vm.apiStack[slot])) return WrenType.WREN_TYPE_NUM;
    if (IS_FOREIGN(vm.apiStack[slot])) return WrenType.WREN_TYPE_FOREIGN;
    if (IS_LIST(vm.apiStack[slot])) return WrenType.WREN_TYPE_LIST;
    if (IS_MAP(vm.apiStack[slot])) return WrenType.WREN_TYPE_MAP;
    if (IS_NULL(vm.apiStack[slot])) return WrenType.WREN_TYPE_NULL;
    if (IS_STRING(vm.apiStack[slot])) return WrenType.WREN_TYPE_STRING;
    
    return WrenType.WREN_TYPE_UNKNOWN;
}

bool wrenGetSlotBool(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    assert(IS_BOOL(vm.apiStack[slot]), "Slot must hold a bool.");

    return AS_BOOL(vm.apiStack[slot]);
}

const(char)* wrenGetSlotBytes(WrenVM* vm, int slot, int* length)
{
    validateApiSlot(vm, slot);
    assert(IS_STRING(vm.apiStack[slot]), "Slot must hold a string.");
    
    ObjString* string_ = AS_STRING(vm.apiStack[slot]);
    *length = string_.length;
    return string_.value.ptr;
}

double wrenGetSlotDouble(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    assert(IS_NUM(vm.apiStack[slot]), "Slot must hold a number.");

    return AS_NUM(vm.apiStack[slot]);
}

void* wrenGetSlotForeign(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    assert(IS_FOREIGN(vm.apiStack[slot]),
            "Slot must hold a foreign instance.");

    return AS_FOREIGN(vm.apiStack[slot]).data.ptr;
}

const(char)* wrenGetSlotString(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    assert(IS_STRING(vm.apiStack[slot]), "Slot must hold a string.");

    return AS_CSTRING(vm.apiStack[slot]);
}

WrenHandle* wrenGetSlotHandle(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    return wrenMakeHandle(vm, vm.apiStack[slot]);
}

// Stores [value] in [slot] in the foreign call stack.
static void setSlot(WrenVM* vm, int slot, Value value)
{
    validateApiSlot(vm, slot);
    vm.apiStack[slot] = value;
}

void wrenSetSlotBool(WrenVM* vm, int slot, bool value)
{
    setSlot(vm, slot, BOOL_VAL(value));
}

void wrenSetSlotBytes(WrenVM* vm, int slot, const char* bytes, size_t length)
{
    assert(bytes != null, "Byte array cannot be NULL.");
    setSlot(vm, slot, wrenNewStringLength(vm, bytes, length));
}

void wrenSetSlotDouble(WrenVM* vm, int slot, double value)
{
    setSlot(vm, slot, NUM_VAL(value));
}

void* wrenSetSlotNewForeign(WrenVM* vm, int slot, int classSlot, size_t size)
{
    validateApiSlot(vm, slot);
    validateApiSlot(vm, classSlot);
    assert(IS_CLASS(vm.apiStack[classSlot]), "Slot must hold a class.");
    
    ObjClass* classObj = AS_CLASS(vm.apiStack[classSlot]);
    assert(classObj.numFields == -1, "Class must be a foreign class.");
    
    ObjForeign* foreign = wrenNewForeign(vm, classObj, size);
    vm.apiStack[slot] = OBJ_VAL(foreign);
    
    return cast(void*)foreign.data;
}

void wrenSetSlotNewList(WrenVM* vm, int slot)
{
    setSlot(vm, slot, OBJ_VAL(wrenNewList(vm, 0)));
}

void wrenSetSlotNewMap(WrenVM* vm, int slot)
{
    setSlot(vm, slot, OBJ_VAL(wrenNewMap(vm)));
}

void wrenSetSlotNull(WrenVM* vm, int slot)
{
    setSlot(vm, slot, NULL_VAL);
}

void wrenSetSlotString(WrenVM* vm, int slot, const char* text)
{
    assert(text != null, "String cannot be NULL.");
    
    setSlot(vm, slot, wrenNewString(vm, text));
}

void wrenSetSlotHandle(WrenVM* vm, int slot, WrenHandle* handle)
{
    assert(handle != null, "Handle cannot be NULL.");

    setSlot(vm, slot, handle.value);
}

int wrenGetListCount(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    assert(IS_LIST(vm.apiStack[slot]), "Slot must hold a list.");
    
    ValueBuffer elements = AS_LIST(vm.apiStack[slot]).elements;
    return elements.count;
}

void wrenGetListElement(WrenVM* vm, int listSlot, int index, int elementSlot)
{
    validateApiSlot(vm, listSlot);
    validateApiSlot(vm, elementSlot);
    assert(IS_LIST(vm.apiStack[listSlot]), "Slot must hold a list.");

    ValueBuffer elements = AS_LIST(vm.apiStack[listSlot]).elements;

    uint usedIndex = wrenValidateIndex(elements.count, index);
    assert(usedIndex != uint.max, "Index out of bounds.");

    vm.apiStack[elementSlot] = elements.data[usedIndex];
}

void wrenSetListElement(WrenVM* vm, int listSlot, int index, int elementSlot)
{
    validateApiSlot(vm, listSlot);
    validateApiSlot(vm, elementSlot);
    assert(IS_LIST(vm.apiStack[listSlot]), "Slot must hold a list.");

    ObjList* list = AS_LIST(vm.apiStack[listSlot]);

    uint usedIndex = wrenValidateIndex(list.elements.count, index);
    assert(usedIndex != uint.max, "Index out of bounds.");
    
    list.elements.data[usedIndex] = vm.apiStack[elementSlot];
}

void wrenInsertInList(WrenVM* vm, int listSlot, int index, int elementSlot)
{
    validateApiSlot(vm, listSlot);
    validateApiSlot(vm, elementSlot);
    assert(IS_LIST(vm.apiStack[listSlot]), "Must insert into a list.");
    
    ObjList* list = AS_LIST(vm.apiStack[listSlot]);
    
    // Negative indices count from the end. 
    // We don't use wrenValidateIndex here because insert allows 1 past the end.
    if (index < 0) index = list.elements.count + 1 + index;
    
    assert(index <= list.elements.count, "Index out of bounds.");
    
    wrenListInsert(vm, list, vm.apiStack[elementSlot], index);
}

int wrenGetMapCount(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    assert(IS_MAP(vm.apiStack[slot]), "Slot must hold a map.");

    ObjMap* map = AS_MAP(vm.apiStack[slot]);
    return map.count;
}

bool wrenGetMapContainsKey(WrenVM* vm, int mapSlot, int keySlot)
{
    import wren.primitive : validateKey;
    validateApiSlot(vm, mapSlot);
    validateApiSlot(vm, keySlot);
    assert(IS_MAP(vm.apiStack[mapSlot]), "Slot must hold a map.");

    Value key = vm.apiStack[keySlot];
    assert(wrenMapIsValidKey(key), "Key must be a value type");
    if (!validateKey(vm, key)) return false;

    ObjMap* map = AS_MAP(vm.apiStack[mapSlot]);
    Value value = wrenMapGet(map, key);

    return !IS_UNDEFINED(value);
}

void wrenGetMapValue(WrenVM* vm, int mapSlot, int keySlot, int valueSlot)
{
    validateApiSlot(vm, mapSlot);
    validateApiSlot(vm, keySlot);
    validateApiSlot(vm, valueSlot);
    assert(IS_MAP(vm.apiStack[mapSlot]), "Slot must hold a map.");

    ObjMap* map = AS_MAP(vm.apiStack[mapSlot]);
    Value value = wrenMapGet(map, vm.apiStack[keySlot]);
    if (IS_UNDEFINED(value)) {
        value = NULL_VAL;
    }

    vm.apiStack[valueSlot] = value;
}

void wrenSetMapValue(WrenVM* vm, int mapSlot, int keySlot, int valueSlot)
{
    import wren.primitive : validateKey;
    validateApiSlot(vm, mapSlot);
    validateApiSlot(vm, keySlot);
    validateApiSlot(vm, valueSlot);
    assert(IS_MAP(vm.apiStack[mapSlot]), "Must insert into a map.");
    
    Value key = vm.apiStack[keySlot];
    assert(wrenMapIsValidKey(key), "Key must be a value type");

    if (!validateKey(vm, key)) {
        return;
    }

    Value value = vm.apiStack[valueSlot];
    ObjMap* map = AS_MAP(vm.apiStack[mapSlot]);
    
    wrenMapSet(vm, map, key, value);
}

void wrenRemoveMapValue(WrenVM* vm, int mapSlot, int keySlot, 
                        int removedValueSlot)
{
    import wren.primitive : validateKey;
    validateApiSlot(vm, mapSlot);
    validateApiSlot(vm, keySlot);
    assert(IS_MAP(vm.apiStack[mapSlot]), "Slot must hold a map.");

    Value key = vm.apiStack[keySlot];
    if (!validateKey(vm, key)) {
        return;
    }

    ObjMap* map = AS_MAP(vm.apiStack[mapSlot]);
    Value removed = wrenMapRemoveKey(vm, map, key);
    setSlot(vm, removedValueSlot, removed);
}

void wrenGetVariable(WrenVM* vm, const(char)* module_, const(char)* name,
                     int slot)
{
    import core.stdc.string : strlen;

    assert(module_ != null, "Module cannot be NULL.");
    assert(name != null, "Variable name cannot be NULL.");  

    Value moduleName = wrenStringFormat(vm, "$", module_);
    wrenPushRoot(vm, AS_OBJ(moduleName));
    
    ObjModule* moduleObj = getModule(vm, moduleName);
    assert(moduleObj != null, "Could not find module.");
    
    wrenPopRoot(vm); // moduleName.

    int variableSlot = wrenSymbolTableFind(&moduleObj.variableNames,
                                            name, strlen(name));
    assert(variableSlot != -1, "Could not find variable.");
    
    setSlot(vm, slot, moduleObj.variables.data[variableSlot]);
}

bool wrenHasVariable(WrenVM* vm, const(char)* module_, const(char)* name)
{
    import core.stdc.string : strlen;

    assert(module_ != null, "Module cannot be NULL.");
    assert(name != null, "Variable name cannot be NULL.");

    Value moduleName = wrenStringFormat(vm, "$", module_);
    wrenPushRoot(vm, AS_OBJ(moduleName));

    //We don't use wrenHasModule since we want to use the module object.
    ObjModule* moduleObj = getModule(vm, moduleName);
    assert(moduleObj != null, "Could not find module.");

    wrenPopRoot(vm); // moduleName.

    int variableSlot = wrenSymbolTableFind(&moduleObj.variableNames,
        name, strlen(name));

    return variableSlot != -1;
}

bool wrenHasModule(WrenVM* vm, const(char)* module_)
{
    assert(module_ != null, "Module cannot be NULL.");
    
    Value moduleName = wrenStringFormat(vm, "$", module_);
    wrenPushRoot(vm, AS_OBJ(moduleName));

    ObjModule* moduleObj = getModule(vm, moduleName);
    
    wrenPopRoot(vm); // moduleName.

    return moduleObj != null;
}

void wrenAbortFiber(WrenVM* vm, int slot)
{
    validateApiSlot(vm, slot);
    vm.fiber.error = vm.apiStack[slot];
}

void* wrenGetUserData(WrenVM* vm)
{
	return vm.config.userData;
}

void wrenSetUserData(WrenVM* vm, void* userData)
{
	vm.config.userData = userData;
}

static bool wrenIsLocalName(const(char)* name)
{
    return name[0] >= 'a' && name[0] <= 'z';
}

static bool wrenIsFalsyValue(Value value)
{
  return IS_FALSE(value) || IS_NULL(value);
}