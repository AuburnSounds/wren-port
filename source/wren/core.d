module wren.core;
import wren.math;
import wren.primitive;
import wren.value;
import wren.vm;

nothrow @nogc:

// The core module source that is interpreted whenever core is initialized.
static immutable string coreModuleSource = import("wren_core.wren");

/++ Boolean primitives +/
@WrenPrimitive("Bool", "!") 
bool bool_not(WrenVM* vm, Value* args) @nogc
{
    return RETURN_BOOL(args, !AS_BOOL(args[0]));
}

@WrenPrimitive("Bool", "toString")
bool bool_toString(WrenVM* vm, Value* args) @nogc
{
    if (AS_BOOL(args[0]))
    {
        return RETURN_VAL(args, CONST_STRING(vm, "true"));
    }
    else
    {
        return RETURN_VAL(args, CONST_STRING(vm, "false"));
    }
}

/++ Class primitives +/
@WrenPrimitive("Class", "name")
bool class_name(WrenVM* vm, Value* args) @nogc
{
    return RETURN_OBJ(args, AS_CLASS(args[0]).name);
}

@WrenPrimitive("Class", "supertype")
bool class_supertype(WrenVM* vm, Value* args) @nogc
{
    ObjClass* classObj = AS_CLASS(args[0]);
    
    // Object has no superclass.
    if (classObj.superclass == null) return RETURN_NULL(args);

    return RETURN_OBJ(args, classObj.superclass);        
}

@WrenPrimitive("Class", "toString")
bool class_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_OBJ(args, AS_CLASS(args[0]).name);
}

@WrenPrimitive("Class", "attributes")
bool class_attributes(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, AS_CLASS(args[0]).attributes);
}

/++ Fiber primitives +/
@WrenPrimitive("Fiber", "new(_)", MethodType.METHOD_PRIMITIVE, true)
bool fiber_new(WrenVM* vm, Value* args) @nogc
{
    if (!validateFn(vm, args[1], "Argument")) return false;

    ObjClosure* closure = AS_CLOSURE(args[1]);
    if (closure.fn.arity > 1)
    {
        return RETURN_ERROR(vm, "Function cannot take more than one parameter.");
    }

    return RETURN_OBJ(args, wrenNewFiber(vm, closure));
}

@WrenPrimitive("Fiber", "abort(_)", MethodType.METHOD_PRIMITIVE, true)
bool fiber_abort(WrenVM* vm, Value* args) @nogc
{
    vm.fiber.error = args[1];

    // If the error is explicitly null, it's not really an abort.
    return IS_NULL(args[1]);
}

@WrenPrimitive("Fiber", "current", MethodType.METHOD_PRIMITIVE, true)
bool fiber_current(WrenVM* vm, Value* args) @nogc
{
    return RETURN_OBJ(args, vm.fiber);
}

@WrenPrimitive("Fiber", "suspend()", MethodType.METHOD_PRIMITIVE, true)
bool fiber_suspend(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, AS_FIBER(args[0]).error);
}

@WrenPrimitive("Fiber", "yield()", MethodType.METHOD_PRIMITIVE, true)
bool fiber_yield(WrenVM* vm, Value* args) @nogc
{
    ObjFiber* current = vm.fiber;
    vm.fiber = current.caller;

    // Unhook this fiber from the one that called it.
    current.caller = null;
    current.state = FiberState.FIBER_OTHER;

    if (vm.fiber != null)
    {
        // Make the caller's run method return null.
        vm.fiber.stackTop[-1] = NULL_VAL;
    }

    return false;
}

@WrenPrimitive("Fiber", "yield(_)", MethodType.METHOD_PRIMITIVE, true)
bool fiber_yield1(WrenVM* vm, Value* args) @nogc
{
    ObjFiber* current = vm.fiber;
    vm.fiber = current.caller;

    // Unhook this fiber from the one that called it.
    current.caller = null;
    current.state = FiberState.FIBER_OTHER;

    if (vm.fiber != null)
    {
        // Make the caller's run method return the argument passed to yield.
        vm.fiber.stackTop[-1] = args[1];

        // When the yielding fiber resumes, we'll store the result of the yield
        // call in its stack. Since Fiber.yield(value) has two arguments (the Fiber
        // class and the value) and we only need one slot for the result, discard
        // the other slot now.
        current.stackTop--;
    }

    return false;
}

// Transfer execution to [fiber] coming from the current fiber whose stack has
// [args].
//
// [isCall] is true if [fiber] is being called and not transferred.
//
// [hasValue] is true if a value in [args] is being passed to the new fiber.
// Otherwise, `null` is implicitly being passed.
bool runFiber(WrenVM* vm, ObjFiber* fiber, Value* args, bool isCall, bool hasValue, const(char)* verb) @nogc
{
    if (wrenHasError(fiber))
    {
       return RETURN_ERROR(vm, "Cannot $ an aborted fiber.", verb);
    }

    if (isCall)
    {
        // You can't call a called fiber, but you can transfer directly to it,
        // which is why this check is gated on `isCall`. This way, after resuming a
        // suspended fiber, it will run and then return to the fiber that called it
        // and so on.
        if (fiber.caller != null) return RETURN_ERROR(vm, "Fiber has already been called.");

        if (fiber.state == FiberState.FIBER_ROOT) return RETURN_ERROR(vm, "Cannot call root fiber.");
        
        // Remember who ran it.
        fiber.caller = vm.fiber;
    }

    if (fiber.numFrames == 0)
    {
        return RETURN_ERROR(vm, "Cannot $ a finished fiber.", verb);
    }

    // When the calling fiber resumes, we'll store the result of the call in its
    // stack. If the call has two arguments (the fiber and the value), we only
    // need one slot for the result, so discard the other slot now.
    if (hasValue) vm.fiber.stackTop--;

    if (fiber.numFrames == 1 &&
        fiber.frames[0].ip == fiber.frames[0].closure.fn.code.data)
    {
        // The fiber is being started for the first time. If its function takes a
        // parameter, bind an argument to it.
        if (fiber.frames[0].closure.fn.arity == 1)
        {
            fiber.stackTop[0] = hasValue ? args[1] : NULL_VAL;
            fiber.stackTop++;
        }
    }
    else
    {
        // The fiber is being resumed, make yield() or transfer() return the result.
        fiber.stackTop[-1] = hasValue ? args[1] : NULL_VAL;
    }

    vm.fiber = fiber;
    return false;
}

@WrenPrimitive("Fiber", "call()")
bool fiber_call(WrenVM* vm, Value* args) @nogc
{
    return runFiber(vm, AS_FIBER(args[0]), args, true, false, "call");
}

@WrenPrimitive("Fiber", "call(_)")
bool fiber_call1(WrenVM* vm, Value* args) @nogc
{
    return runFiber(vm, AS_FIBER(args[0]), args, true, true, "call");
}

@WrenPrimitive("Fiber", "error")
bool fiber_error(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, AS_FIBER(args[0]).error);
}

@WrenPrimitive("Fiber", "isDone")
bool fiber_isDone(WrenVM* vm, Value* args) @nogc
{
    ObjFiber* runFiber = AS_FIBER(args[0]);
    return RETURN_BOOL(args, runFiber.numFrames == 0 || wrenHasError(runFiber));
}

@WrenPrimitive("Fiber", "transfer()")
bool fiber_transfer(WrenVM* vm, Value* args) @nogc
{
    return runFiber(vm, AS_FIBER(args[0]), args, false, false, "transfer to");
}

@WrenPrimitive("Fiber", "transfer(_)")
bool fiber_transfer1(WrenVM* vm, Value* args) @nogc
{
    return runFiber(vm, AS_FIBER(args[0]), args, false, true, "transfer to");
}

@WrenPrimitive("Fiber", "transferError(_)")
bool fiber_transferError(WrenVM* vm, Value* args) @nogc
{
    runFiber(vm, AS_FIBER(args[0]), args, false, true, "transfer to");
    vm.fiber.error = args[1];
    return false;
}

@WrenPrimitive("Fiber", "try()")
bool fiber_try(WrenVM* vm, Value* args) @nogc
{
    runFiber(vm, AS_FIBER(args[0]), args, true, false, "try");

    // If we're switching to a valid fiber to try, remember that we're trying it.
    if (!wrenHasError(vm.fiber)) vm.fiber.state = FiberState.FIBER_TRY;
    return false;
}

@WrenPrimitive("Fiber", "try(_)")
bool fiber_try1(WrenVM* vm, Value* args) @nogc
{
    runFiber(vm, AS_FIBER(args[0]), args, true, true, "try");

    // If we're switching to a valid fiber to try, remember that we're trying it.
    if (!wrenHasError(vm.fiber)) vm.fiber.state = FiberState.FIBER_TRY;
    return false;
}

/++ Fn primitives +/

@WrenPrimitive("Fn", "new(_)", MethodType.METHOD_PRIMITIVE, true)
bool fn_new(WrenVM* vm, Value* args) @nogc
{
    if (!validateFn(vm, args[1], "Argument")) return false;

    // The block argument is already a function, so just return it.
    return RETURN_VAL(args, args[1]);
}

@WrenPrimitive("Fn", "arity")
bool fn_arity(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, AS_CLOSURE(args[0]).fn.arity);
}

void call_fn(WrenVM* vm, Value* args, int numArgs) @nogc
{
    // +1 to include the function itself.
    wrenCallFunction(vm, vm.fiber, AS_CLOSURE(args[0]), numArgs + 1);
}

@WrenPrimitive("Fn", "call()", MethodType.METHOD_FUNCTION_CALL)
bool fn_call0(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 0);
    return false;
}

// Note: all these call(_) function were a string mixin, but this would make 120 template instantiations.

@WrenPrimitive("Fn", "call(_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call1(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 1);
    return false;
}

@WrenPrimitive("Fn", "call(_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call2(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 2);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call3(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 3);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call4(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 4);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call5(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 5);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call6(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 6);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call7(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 7);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call8(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 8);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call9(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 9);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call10(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 10);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call11(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 11);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call12(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 12);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call13(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 13);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call14(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 14);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call15(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 15);
    return false;
}

@WrenPrimitive("Fn", "call(_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_)", MethodType.METHOD_FUNCTION_CALL)
bool fn_call16(WrenVM* vm, Value* args) @nogc
{
    call_fn(vm, args, 16);
    return false;
}

@WrenPrimitive("Fn", "toString")
bool fn_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, CONST_STRING(vm, "<fn>"));
}

/++ List primitives +/
@WrenPrimitive("List", "filled(_,_)", MethodType.METHOD_PRIMITIVE, true)
bool list_filled(WrenVM* vm, Value* args) @nogc
{
    if (!validateInt(vm, args[1], "Size")) return false;
    if (AS_NUM(args[1]) < 0) return RETURN_ERROR(vm, "Size cannot be negative.");

    uint size = cast(uint)AS_NUM(args[1]);
    ObjList* list = wrenNewList(vm, size);

    for (uint i = 0; i < size; i++)
    {
        list.elements.data[i] = args[2];
    }

    return RETURN_OBJ(args, list);
}

@WrenPrimitive("List", "new()", MethodType.METHOD_PRIMITIVE, true)
bool list_new(WrenVM* vm, Value* args) @nogc
{
    return RETURN_OBJ(args, wrenNewList(vm, 0));
}

@WrenPrimitive("List", "[_]")
bool list_subscript(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);

    if (IS_NUM(args[1]))
    {
        uint index = validateIndex(vm, args[1], list.elements.count,
                                    "Subscript");
        if (index == uint.max) return false;

        return RETURN_VAL(args, list.elements.data[index]);
    }

    if (!IS_RANGE(args[1]))
    {
        return RETURN_ERROR(vm, "Subscript must be a number or a range.");
    }

    int step;
    uint count = list.elements.count;
    uint start = calculateRange(vm, AS_RANGE(args[1]), &count, &step);
    if (start == uint.max) return false;

    ObjList* result = wrenNewList(vm, count);
    for (uint i = 0; i < count; i++)
    {
        result.elements.data[i] = list.elements.data[start + i * step];
    }

    return RETURN_OBJ(args, result);
}

@WrenPrimitive("List", "[_]=(_)")
bool list_subscriptSetter(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);
    uint index = validateIndex(vm, args[1], list.elements.count,
                                    "Subscript");
    if (index == uint.max) return false;

    list.elements.data[index] = args[2];
    return RETURN_VAL(args, args[2]);
}

@WrenPrimitive("List", "add(_)")
bool list_add(WrenVM* vm, Value* args) @nogc
{
    wrenValueBufferWrite(vm, &AS_LIST(args[0]).elements, args[1]);
    return RETURN_VAL(args, args[1]);
}

// Adds an element to the list and then returns the list itself. This is called
// by the compiler when compiling list literals instead of using add() to
// minimize stack churn.
@WrenPrimitive("List", "addCore_(_)")
bool list_addCore(WrenVM* vm, Value* args) @nogc
{
    wrenValueBufferWrite(vm, &AS_LIST(args[0]).elements, args[1]);

    // Return the list.
    return RETURN_VAL(args, args[0]);
}

@WrenPrimitive("List", "clear()")
bool list_clear(WrenVM* vm, Value* args) @nogc
{
    wrenValueBufferClear(vm, &AS_LIST(args[0]).elements);
    return RETURN_NULL(args);
}

@WrenPrimitive("List", "count")
bool list_count(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, AS_LIST(args[0]).elements.count);
}

@WrenPrimitive("List", "insert(_,_)")
bool list_insert(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);

    // count + 1 here so you can "insert" at the very end.
    uint index = validateIndex(vm, args[1], list.elements.count + 1, "Index");
    if (index == uint.max) return false;

    wrenListInsert(vm, list, args[2], index);
    return RETURN_VAL(args, args[2]);
}

@WrenPrimitive("List", "iterate(_)")
bool list_iterate(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);

    // If we're starting the iteration, return the first index.
    if (IS_NULL(args[1]))
    {
        if (list.elements.count == 0) return RETURN_FALSE(args);
        return RETURN_NUM(args, 0);
    }

    if (!validateInt(vm, args[1], "Iterator")) return false;

    // Stop if we're out of bounds.
    double index = AS_NUM(args[1]);
    if (index < 0 || index >= list.elements.count - 1) return RETURN_FALSE(args);

    // Otherwise, move to the next index.
    return RETURN_NUM(args, index + 1);
}

@WrenPrimitive("List", "iteratorValue(_)")
bool list_iteratorValue(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);
    uint index = validateIndex(vm, args[1], list.elements.count, "Iterator");
    if (index == uint.max) return false;

    return RETURN_VAL(args, list.elements.data[index]);
}

@WrenPrimitive("List", "removeAt(_)")
bool list_removeAt(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);
    uint index = validateIndex(vm, args[1], list.elements.count, "Index");
    if (index == uint.max) return false;

    return RETURN_VAL(args, wrenListRemoveAt(vm, list, index));
}

@WrenPrimitive("List", "remove(_)")
bool list_removeValue(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);
    int index = wrenListIndexOf(vm, list, args[1]);
    if (index == -1) return RETURN_NULL(args);
    return RETURN_VAL(args, wrenListRemoveAt(vm, list, index));
}

@WrenPrimitive("List", "indexOf(_)")
bool list_indexOf(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);
    return RETURN_NUM(args, wrenListIndexOf(vm, list, args[1]));
}

@WrenPrimitive("List", "swap(_,_)")
bool list_swap(WrenVM* vm, Value* args) @nogc
{
    ObjList* list = AS_LIST(args[0]);
    uint indexA = validateIndex(vm, args[1], list.elements.count, "Index 0");
    if (indexA == uint.max) return false;
    uint indexB = validateIndex(vm, args[2], list.elements.count, "Index 1");
    if (indexB == uint.max) return false;

    Value a = list.elements.data[indexA];
    list.elements.data[indexA] = list.elements.data[indexB];
    list.elements.data[indexB] = a;

    return RETURN_NULL(args);
}
/++ Map primitives +/
bool map_new(WrenVM* vm, Value* args) @nogc
{
    return RETURN_OBJ(args, wrenNewMap(vm));
}

bool map_subscript(WrenVM* vm, Value* args) @nogc
{
    if (!validateKey(vm, args[1])) return false;
    ObjMap* map = AS_MAP(args[0]);
    Value value = wrenMapGet(map, args[1]);
    if (IS_UNDEFINED(value)) 
        return RETURN_NULL(args);
    return RETURN_VAL(args, value);
}

bool map_subscriptSetter(WrenVM* vm, Value* args) @nogc
{
    if (!validateKey(vm, args[1])) return false;
    wrenMapSet(vm, AS_MAP(args[0]), args[1], args[2]);
    return RETURN_VAL(args, args[2]);
}

// Adds an entry to the map and then returns the map itself. This is called by
// the compiler when compiling map literals instead of using [_]=(_) to
// minimize stack churn.
bool map_addCore(WrenVM* vm, Value* args) @nogc
{
    if (!validateKey(vm, args[1])) return false;

    wrenMapSet(vm, AS_MAP(args[0]), args[1], args[2]);

    // Return the map itself.
    return RETURN_VAL(args, args[0]);
}

bool map_clear(WrenVM* vm, Value* args) @nogc
{
    wrenMapClear(vm, AS_MAP(args[0]));
    return RETURN_NULL(args);
}

bool map_containsKey(WrenVM* vm, Value* args) @nogc
{
    if (!validateKey(vm, args[1])) return false;

    return RETURN_BOOL(args, !IS_UNDEFINED(wrenMapGet(AS_MAP(args[0]), args[1])));
}

bool map_count(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, AS_MAP(args[0]).count);
}

bool map_iterate(WrenVM* vm, Value* args) @nogc
{
    ObjMap* map = AS_MAP(args[0]);

    if (map.count == 0) return RETURN_FALSE(args);

    // If we're starting the iteration, start at the first used entry.
    uint index = 0;

    // Otherwise, start one past the last entry we stopped at.
    if (!IS_NULL(args[1]))
    {
        if (!validateInt(vm, args[1], "Iterator")) return false;

        if (AS_NUM(args[1]) < 0) return RETURN_FALSE(args);
        index = cast(uint)AS_NUM(args[1]);

        if (index >= map.capacity) return RETURN_FALSE(args);

        // Advance the iterator.
        index++;
    }

    // Find a used entry, if any.
    for (; index < map.capacity; index++)
    {
        if (!IS_UNDEFINED(map.entries[index].key)) return RETURN_NUM(args, index);
    }

    // If we get here, walked all of the entries.
    return RETURN_FALSE(args);
}

bool map_remove(WrenVM* vm, Value* args) @nogc
{
    if (!validateKey(vm, args[1])) return false;
    return RETURN_VAL(args, wrenMapRemoveKey(vm, AS_MAP(args[0]), args[1]));
}

bool map_keyIteratorValue(WrenVM* vm, Value* args) @nogc
{
    ObjMap* map = AS_MAP(args[0]);
    uint index = validateIndex(vm, args[1], map.capacity, "Iterator");
    if (index == uint.max) return false;

    MapEntry* entry = &map.entries[index];
    if (IS_UNDEFINED(entry.key))
    {
        return RETURN_ERROR(vm, "Invalid map iterator.");
    }
    return RETURN_VAL(args, entry.key);
}

bool map_valueIteratorValue(WrenVM* vm, Value* args) @nogc
{
    ObjMap* map = AS_MAP(args[0]);
    uint index = validateIndex(vm, args[1], map.capacity, "Iterator");
    if (index == uint.max) return false;

    MapEntry* entry = &map.entries[index];
    if (IS_UNDEFINED(entry.key))
    {
        return RETURN_ERROR(vm, "Invalid map iterator.");
    }

    return RETURN_VAL(args, entry.value);
}

/++ Null primitives +/
@WrenPrimitive("Null", "!")
bool null_not(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, TRUE_VAL);
}

@WrenPrimitive("Null", "toString")
bool null_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, CONST_STRING(vm, "null"));
}

/++ Num primitives +/

// Porting over macros is always a joy.
@WrenPrimitive("Num", "infinity", MethodType.METHOD_PRIMITIVE, true)
bool num_infinity(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, double.infinity);
}

@WrenPrimitive("Num", "nan", MethodType.METHOD_PRIMITIVE, true)
bool num_nan(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, WREN_DOUBLE_NAN);
}

@WrenPrimitive("Num", "pi", MethodType.METHOD_PRIMITIVE, true)
bool num_pi(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, 3.14159265358979323846264338327950288);
}

@WrenPrimitive("Num", "tau", MethodType.METHOD_PRIMITIVE, true)
bool num_tau(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, 6.28318530717958647692528676655900577);
}

@WrenPrimitive("Num", "largest", MethodType.METHOD_PRIMITIVE, true)
bool num_largest(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, double.max);
}

@WrenPrimitive("Num", "smallest", MethodType.METHOD_PRIMITIVE, true)
bool num_smallest(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, double.min_normal);
}

@WrenPrimitive("Num", "maxSafeInteger", MethodType.METHOD_PRIMITIVE, true)
bool num_maxSafeInteger(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, 9007199254740991.0);
}

@WrenPrimitive("Num", "minSafeInteger", MethodType.METHOD_PRIMITIVE, true)
bool num_minSafeInteger(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, -9007199254740991.0);
}

@WrenPrimitive("Num", "-(_)")
bool num_minus(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_NUM(args, AS_NUM(args[0]) - AS_NUM(args[1]));
}

@WrenPrimitive("Num", "+(_)")
bool num_plus(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_NUM(args, AS_NUM(args[0]) + AS_NUM(args[1]));
}

@WrenPrimitive("Num", "*(_)")
bool num_multiply(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_NUM(args, AS_NUM(args[0]) * AS_NUM(args[1]));
}

@WrenPrimitive("Num", "/(_)")
bool num_divide(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_NUM(args, AS_NUM(args[0]) / AS_NUM(args[1]));
}

@WrenPrimitive("Num", "<(_)")
bool num_lt(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_BOOL(args, AS_NUM(args[0]) < AS_NUM(args[1]));
}

@WrenPrimitive("Num", ">(_)")
bool num_gt(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_BOOL(args, AS_NUM(args[0]) > AS_NUM(args[1]));
}

@WrenPrimitive("Num", "<=(_)")
bool num_lte(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_BOOL(args, AS_NUM(args[0]) <= AS_NUM(args[1]));
}

@WrenPrimitive("Num", ">=(_)")
bool num_gte(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_BOOL(args, AS_NUM(args[0]) >= AS_NUM(args[1]));
}

@WrenPrimitive("Num", "&(_)")
bool num_bitwiseAnd(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    uint left = cast(uint)AS_NUM(args[0]);
    uint right = cast(uint)AS_NUM(args[1]);
    return RETURN_NUM(args, left & right);
}

@WrenPrimitive("Num", "|(_)")
bool num_bitwiseOr(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    uint left = cast(uint)AS_NUM(args[0]);
    uint right = cast(uint)AS_NUM(args[1]);
    return RETURN_NUM(args, left | right);
}

@WrenPrimitive("Num", "^(_)")
bool num_bitwiseXor(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    uint left = cast(uint)AS_NUM(args[0]);
    uint right = cast(uint)AS_NUM(args[1]);
    return RETURN_NUM(args, left ^ right);
}

@WrenPrimitive("Num", "<<(_)")
bool num_bitwiseLeftShift(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    uint left = cast(uint)AS_NUM(args[0]);
    uint right = cast(uint)AS_NUM(args[1]);
    return RETURN_NUM(args, left << right);
}

@WrenPrimitive("Num", ">>(_)")
bool num_bitwiseRightShift(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right operand")) return false;
    uint left = cast(uint)AS_NUM(args[0]);
    uint right = cast(uint)AS_NUM(args[1]);
    return RETURN_NUM(args, left >> right);
}

// Numeric functions

@WrenPrimitive("Num", "abs")
bool num_abs(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : fabs;
    return RETURN_NUM(args, fabs(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "acos")
bool num_acos(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : acos;
    return RETURN_NUM(args, acos(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "asin")
bool num_asin(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : asin;
    return RETURN_NUM(args, asin(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "atan")
bool num_atan(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : atan;
    return RETURN_NUM(args, atan(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "cbrt")
bool num_cbrt(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : cbrt;
    return RETURN_NUM(args, cbrt(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "ceil")
bool num_ceil(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : ceil;
    return RETURN_NUM(args, ceil(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "cos")
bool num_cos(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : cos;
    return RETURN_NUM(args, cos(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "floor")
bool num_floor(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : floor;
    return RETURN_NUM(args, floor(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "round")
bool num_round(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : round;
    return RETURN_NUM(args, round(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "sin")
bool num_sin(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : sin;
    return RETURN_NUM(args, sin(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "sqrt")
bool num_sqrt(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : sqrt;
    return RETURN_NUM(args, sqrt(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "tan")
bool num_tan(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : tan;
    return RETURN_NUM(args, tan(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "log")
bool num_log(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : log;
    return RETURN_NUM(args, log(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "log2")
bool num_log2(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : log2;
    return RETURN_NUM(args, log2(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "exp")
bool num_exp(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : exp;
    return RETURN_NUM(args, exp(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "-")
bool num_negate(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, -AS_NUM(args[0]));
}

@WrenPrimitive("Num", "%(_)")
bool num_mod(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : fmod;
    if (!validateNum(vm, args[1], "Right operand")) return false;
    return RETURN_NUM(args, fmod(AS_NUM(args[0]), AS_NUM(args[1])));
}

@WrenPrimitive("Num", "==(_)")
bool num_eqeq(WrenVM* vm, Value* args) @nogc
{
    if (!IS_NUM(args[1])) return RETURN_FALSE(args);
    return RETURN_BOOL(args, AS_NUM(args[0]) == AS_NUM(args[1]));
}

@WrenPrimitive("Num", "!=(_)")
bool num_bangeq(WrenVM* vm, Value* args) @nogc
{
    if (!IS_NUM(args[1])) return RETURN_TRUE(args);
    return RETURN_BOOL(args, AS_NUM(args[0]) != AS_NUM(args[1]));
}

@WrenPrimitive("Num", "~")
bool num_bitwiseNot(WrenVM* vm, Value* args) @nogc
{
    // Bitwise operators always work on 32-bit unsigned ints.
    return RETURN_NUM(args, ~cast(uint)(AS_NUM(args[0])));
}

@WrenPrimitive("Num", "..(_)")
bool num_dotDot(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right hand side of range")) return false;

    double from = AS_NUM(args[0]);
    double to = AS_NUM(args[1]);
    return RETURN_VAL(args, wrenNewRange(vm, from, to, true));
}

@WrenPrimitive("Num", "...(_)")
bool num_dotDotDot(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Right hand side of range")) return false;

    double from = AS_NUM(args[0]);
    double to = AS_NUM(args[1]);
    return RETURN_VAL(args, wrenNewRange(vm, from, to, false));
}

@WrenPrimitive("Num", "atan2(_)")
bool num_atan2(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : atan2;
    if (!validateNum(vm, args[1], "x value")) return false;

    return RETURN_NUM(args, atan2(AS_NUM(args[0]), AS_NUM(args[1])));
}

@WrenPrimitive("Num", "min(_)")
bool num_min(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Other value")) return false;

    double value = AS_NUM(args[0]);
    double other = AS_NUM(args[1]);
    return RETURN_NUM(args, value <= other ? value : other);
}

@WrenPrimitive("Num", "max(_)")
bool num_max(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Other value")) return false;

    double value = AS_NUM(args[0]);
    double other = AS_NUM(args[1]);
    return RETURN_NUM(args, value > other ? value : other);
}

@WrenPrimitive("Num", "clamp(_,_)")
bool num_clamp(WrenVM* vm, Value* args) @nogc
{
    if (!validateNum(vm, args[1], "Min value")) return false;
    if (!validateNum(vm, args[2], "Max value")) return false;

    double value = AS_NUM(args[0]);
    double min = AS_NUM(args[1]);
    double max = AS_NUM(args[2]);
    double result = (value < min) ? min : ((value > max) ? max : value);
    return RETURN_NUM(args, result);
}

@WrenPrimitive("Num", "pow(_)")
bool num_pow(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : pow;
    if (!validateNum(vm, args[1], "Power value")) return false;

    return RETURN_NUM(args, pow(AS_NUM(args[0]), AS_NUM(args[1])));
}

@WrenPrimitive("Num", "fraction")
bool num_fraction(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : modf;

    double unused;
    return RETURN_NUM(args, modf(AS_NUM(args[0]), &unused));
}

@WrenPrimitive("Num", "isInfinity")
bool num_isInfinity(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : isinf;
    return RETURN_BOOL(args, isinf(AS_NUM(args[0])) == 1);
}

@WrenPrimitive("Num", "isNan")
bool num_isNan(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : isnan;
    return RETURN_BOOL(args, isnan(AS_NUM(args[0])) == 1);
}

@WrenPrimitive("Num", "sign")
bool num_sign(WrenVM* vm, Value* args) @nogc
{
    double value = AS_NUM(args[0]);
    if (value > 0) 
    {
        return RETURN_NUM(args, 1);
    }
    else if (value < 0)
    {
        return RETURN_NUM(args, -1);
    }
    else
    {
        return RETURN_NUM(args, 0);
    }
}

@WrenPrimitive("Num", "toString")
bool num_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, wrenNumToString(vm, AS_NUM(args[0])));   
}

@WrenPrimitive("Num", "truncate")
bool num_truncate(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : modf;
    double integer;
    modf(AS_NUM(args[0]), &integer);
    return RETURN_NUM(args, integer);
}

/++ Object primitives +/
@WrenPrimitive("Object metaclass", "same(_,_)")
bool object_same(WrenVM* vm, Value* args) @nogc
{
    return RETURN_BOOL(args, wrenValuesEqual(args[1], args[2]));
}

@WrenPrimitive("Object", "!")
bool object_not(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, FALSE_VAL);
}

@WrenPrimitive("Object", "==(_)")
bool object_eqeq(WrenVM* vm, Value* args) @nogc
{
    return RETURN_BOOL(args, wrenValuesEqual(args[0], args[1]));
}

@WrenPrimitive("Object", "!=(_)")
bool object_bangeq(WrenVM* vm, Value* args) @nogc
{
    return RETURN_BOOL(args, !wrenValuesEqual(args[0], args[1]));
}

@WrenPrimitive("Object", "is(_)")
bool object_is(WrenVM* vm, Value* args) @nogc
{
    if (!IS_CLASS(args[1]))
    {
        return RETURN_ERROR(vm, "Right operand must be a class.");
    }

    ObjClass *classObj = wrenGetClass(vm, args[0]);
    ObjClass *baseClassObj = AS_CLASS(args[1]);

    // Walk the superclass chain looking for the class.
    do
    {
        if (baseClassObj == classObj) {
            return RETURN_BOOL(args, true);
        }

        classObj = classObj.superclass;
    }
    while (classObj != null);

    return RETURN_BOOL(args, false);
}

@WrenPrimitive("Object", "toString")
bool object_toString(WrenVM* vm, Value* args) @nogc
{
    Obj* obj = AS_OBJ(args[0]);
    Value name = OBJ_VAL(obj.classObj.name);
    return RETURN_VAL(args, wrenStringFormat(vm, "instance of @", name));
}

@WrenPrimitive("Object", "type")
bool object_type(WrenVM* vm, Value* args) @nogc
{
    return RETURN_OBJ(args, wrenGetClass(vm, args[0]));
}

/++ Range primitives +/

@WrenPrimitive("Range", "from")
bool range_from(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, AS_RANGE(args[0]).from);
}

@WrenPrimitive("Range", "to")
bool range_to(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, AS_RANGE(args[0]).to);
}

@WrenPrimitive("Range", "min")
bool range_min(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : fmin;
    ObjRange* range = AS_RANGE(args[0]);
    return RETURN_NUM(args, fmin(range.from, range.to));
}

@WrenPrimitive("Range", "max")
bool range_max(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.math : fmax;
    ObjRange* range = AS_RANGE(args[0]);
    return RETURN_NUM(args, fmax(range.from, range.to));
}

@WrenPrimitive("Range", "isInclusive")
bool range_isInclusive(WrenVM* vm, Value* args) @nogc
{
    return RETURN_BOOL(args, AS_RANGE(args[0]).isInclusive);
}

@WrenPrimitive("Range", "iterate(_)")
bool range_iterate(WrenVM* vm, Value* args) @nogc
{
    ObjRange* range = AS_RANGE(args[0]);

    // Special case: empty range.
    if (range.from == range.to && !range.isInclusive) return RETURN_FALSE(args);

    // Start the iteration.
    if (IS_NULL(args[1])) return RETURN_NUM(args, range.from);

    if (!validateNum(vm, args[1], "Iterator")) return false;

    double iterator = AS_NUM(args[1]);

    // Iterate towards [to] from [from].
    if (range.from < range.to)
    {
        iterator++;
        if (iterator > range.to) return RETURN_FALSE(args);
    }
    else
    {
        iterator--;
        if (iterator < range.to) return RETURN_FALSE(args);
    }

    if (!range.isInclusive && iterator == range.to) return RETURN_FALSE(args);

    return RETURN_NUM(args, iterator);
}

@WrenPrimitive("Range", "iteratorValue(_)")
bool range_iteratorValue(WrenVM* vm, Value* args) @nogc
{
    // Assume the iterator is a number so that is the value of the range.
    return RETURN_VAL(args, args[1]);
}

@WrenPrimitive("Range", "toString")
bool range_toString(WrenVM* vm, Value* args) @nogc
{
    ObjRange* range = AS_RANGE(args[0]);

    Value from = wrenNumToString(vm, range.from);
    wrenPushRoot(vm, AS_OBJ(from));

    Value to = wrenNumToString(vm, range.to);
    wrenPushRoot(vm, AS_OBJ(to));

    Value result = wrenStringFormat(vm, "@$@", from,
                                    range.isInclusive ? "..".ptr : "...".ptr, to);

    wrenPopRoot(vm);
    wrenPopRoot(vm);
    return RETURN_VAL(args, result);
}

/++ String primitives +/

@WrenPrimitive("String", "fromCodePoint(_)", MethodType.METHOD_PRIMITIVE, true)
bool string_fromCodePoint(WrenVM* vm, Value* args) @nogc
{
    if (!validateInt(vm, args[1], "Code point")) return false;

    int codePoint = cast(int)AS_NUM(args[1]);
    if (codePoint < 0)
    {
        return RETURN_ERROR(vm, "Code point cannot be negative.");
    }
    else if (codePoint > 0x10ffff)
    {
        return RETURN_ERROR(vm, "Code point cannot be greater than 0x10ffff.");
    }

    return RETURN_VAL(args, wrenStringFromCodePoint(vm, codePoint));
}

@WrenPrimitive("String", "fromByte(_)", MethodType.METHOD_PRIMITIVE, true)
bool string_fromByte(WrenVM* vm, Value* args) @nogc
{
    if (!validateInt(vm, args[1], "Byte")) return false;
    int byte_ = cast(int) AS_NUM(args[1]);
    if (byte_ < 0)
    {
        return RETURN_ERROR(vm, "Byte cannot be negative.");
    }
    else if (byte_ > 0xff)
    {
        return RETURN_ERROR(vm, "Byte cannot be greater than 0xff.");
    }
    return RETURN_VAL(args, wrenStringFromByte(vm, cast(ubyte)byte_));
}

@WrenPrimitive("String", "byteAt(_)")
bool string_byteAt(WrenVM* vm, Value* args) @nogc
{
    ObjString* string_ = AS_STRING(args[0]);

    uint index = validateIndex(vm, args[1], string_.length, "Index");
    if (index == uint.max) return false;

    return RETURN_NUM(args, cast(ubyte)string_.value[index]);
}

@WrenPrimitive("String", "byteCount")
bool string_byteCount(WrenVM* vm, Value* args) @nogc
{
    return RETURN_NUM(args, AS_STRING(args[0]).length);
}

@WrenPrimitive("String", "codePointAt(_)")
bool string_codePointAt(WrenVM* vm, Value* args) @nogc
{
    import wren.utils : wrenUtf8Decode;
    ObjString* string_ = AS_STRING(args[0]);

    uint index = validateIndex(vm, args[1], string_.length, "Index");
    if (index == uint.max) return false;

    // If we are in the middle of a UTF-8 sequence, indicate that.
    const(ubyte)* bytes = cast(ubyte*)string_.value.ptr;
    if ((bytes[index] & 0xc0) == 0x80) return RETURN_NUM(args, -1);

    // Decode the UTF-8 sequence.
    return RETURN_NUM(args, wrenUtf8Decode(cast(ubyte*)string_.value + index,
                                string_.length - index));
}

@WrenPrimitive("String", "contains(_)")
bool string_contains(WrenVM* vm, Value* args) @nogc
{
    if (!validateString(vm, args[1], "Argument")) return false;

    ObjString* string_ = AS_STRING(args[0]);
    ObjString* search = AS_STRING(args[1]);

    return RETURN_BOOL(args, wrenStringFind(string_, search, 0) != uint.max);
}

@WrenPrimitive("String", "endsWith(_)")
bool string_endsWith(WrenVM* vm, Value* args) @nogc
{
    import core.stdc.string : memcmp;
    if (!validateString(vm, args[1], "Argument")) return false;

    ObjString* string_ = AS_STRING(args[0]);
    ObjString* search = AS_STRING(args[1]);

    // Edge case: If the search string is longer then return false right away.
    if (search.length > string_.length) return RETURN_FALSE(args);

    return RETURN_BOOL(args, memcmp(string_.value.ptr + string_.length - search.length,
                        search.value.ptr, search.length) == 0);
}

@WrenPrimitive("String", "indexOf(_)")
bool string_indexOf1(WrenVM* vm, Value* args) @nogc
{
    if (!validateString(vm, args[1], "Argument")) return false;

    ObjString* string_ = AS_STRING(args[0]);
    ObjString* search = AS_STRING(args[1]);

    uint index = wrenStringFind(string_, search, 0);
    return RETURN_NUM(args, index == uint.max ? -1 : cast(int)index);
}

@WrenPrimitive("String", "indexOf(_,_)")
bool string_indexOf2(WrenVM* vm, Value* args) @nogc
{
    if (!validateString(vm, args[1], "Argument")) return false;

    ObjString* string_ = AS_STRING(args[0]);
    ObjString* search = AS_STRING(args[1]);
    uint start = validateIndex(vm, args[2], string_.length, "Start");
    if (start == uint.max) return false;
    
    uint index = wrenStringFind(string_, search, start);
    return RETURN_NUM(args, index == uint.max ? -1 : cast(int)index);   
}

@WrenPrimitive("String", "iterate(_)")
bool string_iterate(WrenVM* vm, Value* args) @nogc
{
    ObjString* string_ = AS_STRING(args[0]);

    // If we're starting the iteration, return the first index.
    if (IS_NULL(args[1]))
    {
        if (string_.length == 0) return RETURN_FALSE(args);
        return RETURN_NUM(args, 0);
    }

    if (!validateInt(vm, args[1], "Iterator")) return false;

    if (AS_NUM(args[1]) < 0) return RETURN_FALSE(args);
    uint index = cast(uint)AS_NUM(args[1]);

    // Advance to the beginning of the next UTF-8 sequence.
    do
    {
        index++;
        if (index >= string_.length) return RETURN_FALSE(args);
    } while ((string_.value[index] & 0xc0) == 0x80);

    return RETURN_NUM(args, index);   
}

@WrenPrimitive("String", "iterateByte(_)")
bool string_iterateByte(WrenVM* vm, Value* args) @nogc
{
    ObjString* string_ = AS_STRING(args[0]);

    // If we're starting the iteration, return the first index.
    if (IS_NULL(args[1]))
    {
        if (string_.length == 0) return RETURN_FALSE(args);
        return RETURN_NUM(args, 0);
    }

    if (!validateInt(vm, args[1], "Iterator")) return false;

    if (AS_NUM(args[1]) < 0) return RETURN_FALSE(args);
    uint index = cast(uint)AS_NUM(args[1]);

    // Advance to the next byte.
    index++;
    if (index >= string_.length) return RETURN_FALSE(args);

    return RETURN_NUM(args, index);   
}

@WrenPrimitive("String", "iteratorValue(_)")
bool string_iteratorValue(WrenVM* vm, Value* args) @nogc
{
    ObjString* string_ = AS_STRING(args[0]);
    uint index = validateIndex(vm, args[1], string_.length, "Iterator");
    if (index == uint.max) return false;

    return RETURN_VAL(args, wrenStringCodePointAt(vm, string_, index));
}

@WrenPrimitive("String", "$")
bool string_dollar(WrenVM* vm, Value* args) @nogc
{
    if (vm.config.dollarOperatorFn)
        return vm.config.dollarOperatorFn(vm, args);

    // By default, return null, however can be set by the host to mean anything.
    return RETURN_NULL(args);
}

@WrenPrimitive("String", "+(_)")
bool string_plus(WrenVM* vm, Value* args) @nogc
{
    if (!validateString(vm, args[1], "Right operand")) return false;
    return RETURN_VAL(args, wrenStringFormat(vm, "@@", args[0], args[1]));
}

@WrenPrimitive("String", "[_]")
bool string_subscript(WrenVM* vm, Value* args) @nogc
{
    ObjString* string_ = AS_STRING(args[0]);

    if (IS_NUM(args[1]))
    {
        int index = validateIndex(vm, args[1], string_.length, "Subscript");
        if (index == -1) return false;

        return RETURN_VAL(args, wrenStringCodePointAt(vm, string_, index));
    }

    if (!IS_RANGE(args[1]))
    {
        return RETURN_ERROR(vm, "Subscript must be a number or a range.");
    }

    int step;
    uint count = string_.length;
    int start = calculateRange(vm, AS_RANGE(args[1]), &count, &step);
    if (start == -1) return false;

    return RETURN_VAL(args, wrenNewStringFromRange(vm, string_, start, count, step));
}

@WrenPrimitive("String", "toString")
bool string_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, args[0]);
}

@WrenPrimitive("System", "clock")
bool system_clock(WrenVM* vm, Value* args) @nogc
{
    version (Posix) {
        import core.sys.posix.stdc.time : clock, CLOCKS_PER_SEC;
        return RETURN_NUM(args, cast(double)clock / CLOCKS_PER_SEC);
    } else {
        import core.time : convClockFreq, MonoTime;
        double t = convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000_000) * 0.000001;
        return RETURN_NUM(args, t);
    }
}

@WrenPrimitive("System", "gc()")
bool system_gc(WrenVM* vm, Value* args) @nogc
{
    wrenCollectGarbage(vm);
    return RETURN_NULL(args);
}

@WrenPrimitive("System", "writeString_(_)")
bool system_writeString(WrenVM* vm, Value* args) @nogc
{
    if (vm.config.writeFn != null)
    {
        vm.config.writeFn(vm, AS_CSTRING(args[1]));
    }

    return RETURN_VAL(args, args[1]);
}

// Wren addition for D embedding
@WrenPrimitive("System", "isDebugBuild")
bool system_is_debug_build(WrenVM* vm, Value* args) @nogc
{
    debug
    {    
        return RETURN_BOOL(args, true);
    }
    else
    {
        return RETURN_BOOL(args, false);
    }
}

// Creates either the Object or Class class in the core module with [name].
ObjClass* defineClass(WrenVM* vm, ObjModule* module_, const(char)* name) @nogc
{
  ObjString* nameString = AS_STRING(wrenNewString(vm, name));
  wrenPushRoot(vm, cast(Obj*)nameString);

  ObjClass* classObj = wrenNewSingleClass(vm, 0, nameString);

  wrenDefineVariable(vm, module_, name, nameString.length, OBJ_VAL(classObj), null);

  wrenPopRoot(vm);
  return classObj;
}


void wrenInitializeCore(WrenVM* vm) @nogc
{
    ObjModule* coreModule = wrenNewModule(vm, null);
    wrenPushRoot(vm, cast(Obj*)coreModule);
    
    // The core module's key is null in the module map.
    wrenMapSet(vm, vm.modules, NULL_VAL, OBJ_VAL(coreModule));
    wrenPopRoot(vm); // coreModule.

    // Define the root Object class. This has to be done a little specially
    // because it has no superclass.
    vm.objectClass = defineClass(vm, coreModule, "Object");

    //registerPrimitives!("Object")(vm, vm.objectClass);
    addPrimitive(vm, vm.objectClass, "!"        , &object_not     , MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.objectClass, "==(_)"    , &object_eqeq    , MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.objectClass, "!=(_)"    , &object_bangeq  , MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.objectClass, "is(_)"    , &object_is      , MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.objectClass, "toString" , &object_toString, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.objectClass, "type"     , &object_type    , MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.objectClass, "same(_,_)", &object_same    , MethodType.METHOD_PRIMITIVE, false);

    // Now we can define Class, which is a subclass of Object.
    vm.classClass = defineClass(vm, coreModule, "Class");
    wrenBindSuperclass(vm, vm.classClass, vm.objectClass);

    // Finally, we can define Object's metaclass which is a subclass of Class.
    ObjClass* objectMetaclass = defineClass(vm, coreModule, "Object metaclass");

    // Wire up the metaclass relationships now that all three classes are built.
    vm.objectClass.obj.classObj = objectMetaclass;
    objectMetaclass.obj.classObj = vm.classClass;
    vm.classClass.obj.classObj = vm.classClass;

    // Do this after wiring up the metaclasses so objectMetaclass doesn't get
    // collected.
    wrenBindSuperclass(vm, objectMetaclass, vm.classClass);
    addPrimitive(vm, objectMetaclass, "same(_,_)", &object_same, MethodType.METHOD_PRIMITIVE, false);

    // The core class diagram ends up looking like this, where single lines point
    // to a class's superclass, and double lines point to its metaclass:
    //
    //        .------------------------------------. .====.
    //        |                  .---------------. | #    #
    //        v                  |               v | v    #
    //   .---------.   .-------------------.   .-------.  #
    //   | Object  |==>| Object metaclass  |==>| Class |=="
    //   '---------'   '-------------------'   '-------'
    //        ^                                 ^ ^ ^ ^
    //        |                  .--------------' # | #
    //        |                  |                # | #
    //   .---------.   .-------------------.      # | # -.
    //   |  Base   |==>|  Base metaclass   |======" | #  |
    //   '---------'   '-------------------'        | #  |
    //        ^                                     | #  |
    //        |                  .------------------' #  | Example classes
    //        |                  |                    #  |
    //   .---------.   .-------------------.          #  |
    //   | Derived |==>| Derived metaclass |=========="  |
    //   '---------'   '-------------------'            -'

    // The rest of the classes can now be defined normally.
    wrenInterpret(vm, null, coreModuleSource.ptr);

    vm.boolClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Bool"));
    addPrimitive(vm, vm.boolClass, "!", &bool_not, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.boolClass, "toString", &bool_toString, MethodType.METHOD_PRIMITIVE, false);

    vm.fiberClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Fiber"));
    addPrimitive(vm, vm.fiberClass, "new(_)", &fiber_new, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.fiberClass, "abort(_)", &fiber_abort, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.fiberClass, "current", &fiber_current, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.fiberClass, "suspend()", &fiber_suspend, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.fiberClass, "yield()", &fiber_yield, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.fiberClass, "yield(_)", &fiber_yield1, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.fiberClass, "call()", &fiber_call, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "call(_)", &fiber_call1, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "error", &fiber_error, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "isDone", &fiber_isDone, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "transfer()", &fiber_transfer, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "transfer(_)", &fiber_transfer1, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "transferError(_)", &fiber_transferError, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "try()", &fiber_try, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fiberClass, "try(_)", &fiber_try1, MethodType.METHOD_PRIMITIVE, false);

    vm.fnClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Fn"));
    addPrimitive(vm, vm.fnClass, "new(_)", &fn_new, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.fnClass, "arity", &fn_arity, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.fnClass, "call()", &fn_call0, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_)", &fn_call1, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_)", &fn_call2, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_)", &fn_call3, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_)", &fn_call4, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_)", &fn_call5, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_)", &fn_call6, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_)", &fn_call7, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_)", &fn_call8, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_)", &fn_call9, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_,_)", &fn_call10, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_,_,_)", &fn_call11, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_,_,_,_)", &fn_call12, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_,_,_,_,_)", &fn_call13, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_,_,_,_,_,_)", &fn_call14, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_,_,_,_,_,_,_)", &fn_call15, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "call(_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_)", &fn_call16, MethodType.METHOD_FUNCTION_CALL, false);
    addPrimitive(vm, vm.fnClass, "toString", &fn_toString, MethodType.METHOD_PRIMITIVE, false);

    vm.nullClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Null"));
    addPrimitive(vm, vm.nullClass, "!", &null_not, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.nullClass, "toString", &null_toString, MethodType.METHOD_PRIMITIVE, false);

    vm.numClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Num"));
    addPrimitive(vm, vm.numClass, "infinity", &num_infinity, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "nan", &num_nan, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "pi", &num_pi, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "tau", &num_tau, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "largest", &num_largest, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "smallest", &num_smallest, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "maxSafeInteger", &num_maxSafeInteger, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "minSafeInteger", &num_minSafeInteger, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.numClass, "-(_)", &num_minus, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "+(_)", &num_plus, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "*(_)", &num_multiply, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "/(_)", &num_divide, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "<(_)", &num_lt, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, ">(_)", &num_gt, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "<=(_)", &num_lte, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, ">=(_)", &num_gte, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "&(_)", &num_bitwiseAnd, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "|(_)", &num_bitwiseOr, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "^(_)", &num_bitwiseXor, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "<<(_)", &num_bitwiseLeftShift, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, ">>(_)", &num_bitwiseRightShift, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "abs", &num_abs, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "acos", &num_acos, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "asin", &num_asin, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "atan", &num_atan, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "cbrt", &num_cbrt, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "ceil", &num_ceil, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "cos", &num_cos, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "floor", &num_floor, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "round", &num_round, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "sin", &num_sin, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "sqrt", &num_sqrt, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "tan", &num_tan, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "log", &num_log, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "log2", &num_log2, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "exp", &num_exp, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "-", &num_negate, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "%(_)", &num_mod, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "==(_)", &num_eqeq, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "!=(_)", &num_bangeq, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "~", &num_bitwiseNot, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "..(_)", &num_dotDot, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "...(_)", &num_dotDotDot, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "atan2(_)", &num_atan2, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "min(_)", &num_min, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "max(_)", &num_max, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "clamp(_,_)", &num_clamp, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "pow(_)", &num_pow, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "fraction", &num_fraction, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "isInfinity", &num_isInfinity, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "isNan", &num_isNan, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "sign", &num_sign, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "toString", &num_toString, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.numClass, "truncate", &num_truncate, MethodType.METHOD_PRIMITIVE, false);

    vm.stringClass = AS_CLASS(wrenFindVariable(vm, coreModule, "String"));
    addPrimitive(vm, vm.stringClass, "fromCodePoint(_)", &string_fromCodePoint, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.stringClass, "fromByte(_)", &string_fromByte, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.stringClass, "byteAt(_)", &string_byteAt, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "byteCount", &string_byteCount, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "codePointAt(_)", &string_codePointAt, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "contains(_)", &string_contains, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "endsWith(_)", &string_endsWith, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "indexOf(_)", &string_indexOf1, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "indexOf(_,_)", &string_indexOf2, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "iterate(_)", &string_iterate, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "iterateByte(_)", &string_iterateByte, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "iteratorValue(_)", &string_iteratorValue, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "$", &string_dollar, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "+(_)", &string_plus, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "[_]", &string_subscript, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.stringClass, "toString", &string_toString, MethodType.METHOD_PRIMITIVE, false);

    vm.listClass = AS_CLASS(wrenFindVariable(vm, coreModule, "List"));
    addPrimitive(vm, vm.listClass, "filled(_,_)", &list_filled, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.listClass, "new()", &list_new, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.listClass, "[_]", &list_subscript, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "[_]=(_)", &list_subscriptSetter, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "add(_)", &list_add, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "addCore_(_)", &list_addCore, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "clear()", &list_clear, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "count", &list_count, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "insert(_,_)", &list_insert, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "iterate(_)", &list_iterate, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "iteratorValue(_)", &list_iteratorValue, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "removeAt(_)", &list_removeAt, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "remove(_)", &list_removeValue, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "indexOf(_)", &list_indexOf, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.listClass, "swap(_,_)", &list_swap, MethodType.METHOD_PRIMITIVE, false);

    vm.mapClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Map"));
    addPrimitive(vm, vm.mapClass, "new()", &map_new, MethodType.METHOD_PRIMITIVE, true);
    addPrimitive(vm, vm.mapClass, "[_]", &map_subscript, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "[_]=(_)", &map_subscriptSetter, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "addCore_(_,_)", &map_addCore, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "clear()", &map_clear, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "containsKey(_)", &map_containsKey, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "count", &map_count, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "remove(_)", &map_remove, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "iterate(_)", &map_iterate, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "keyIteratorValue_(_)", &map_keyIteratorValue, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.mapClass, "valueIteratorValue_(_)", &map_valueIteratorValue, MethodType.METHOD_PRIMITIVE, false);

    vm.rangeClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Range"));
    addPrimitive(vm, vm.rangeClass, "from", &range_from, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.rangeClass, "to", &range_to, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.rangeClass, "min", &range_min, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.rangeClass, "max", &range_max, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.rangeClass, "isInclusive", &range_isInclusive, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.rangeClass, "iterate(_)", &range_iterate, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.rangeClass, "iteratorValue(_)", &range_iteratorValue, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, vm.rangeClass, "toString", &range_toString, MethodType.METHOD_PRIMITIVE, false);

    ObjClass* systemClass = AS_CLASS(wrenFindVariable(vm, coreModule, "System"));
    addPrimitive(vm, systemClass.obj.classObj, "clock", &system_clock, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, systemClass.obj.classObj, "gc()", &system_gc, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, systemClass.obj.classObj, "writeString_(_)", &system_writeString, MethodType.METHOD_PRIMITIVE, false);
    addPrimitive(vm, systemClass.obj.classObj, "isDebugBuild", &system_is_debug_build, MethodType.METHOD_PRIMITIVE, false);


    // While bootstrapping the core types and running the core module, a number
    // of string objects have been created, many of which were instantiated
    // before stringClass was stored in the VM. Some of them *must* be created
    // first -- the ObjClass for string itself has a reference to the ObjString
    // for its name.
    //
    // These all currently have a NULL classObj pointer, so go back and assign
    // them now that the string class is known.
    for (Obj* obj = vm.first; obj != null; obj = obj.next)
    {
        if (obj.type == ObjType.OBJ_STRING) obj.classObj = vm.stringClass;
    }
}