module wren.core;
import wren.primitive;
import wren.value;
import wren.vm;

// Throwing exception support
import dplug.core : mallocNew;
// The core module source
static const(char)[] coreModuleSource = import("wren_core.wren");

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
static bool runFiber(WrenVM* vm, ObjFiber* fiber, Value* args, bool isCall,
                     bool hasValue, const(char)* verb) @nogc
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

static void call_fn(WrenVM* vm, Value* args, int numArgs) @nogc
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

// This mixin is a mess, but we need to generate the primitives
// to allow a user to call a function with up to 16 arguments.
// This is the cleanest that I could make it, but it's still definitely a mess.
mixin(() {
    import std.format : format;
    import std.range : repeat, join;

    string ret = ""; 

    // Build up our argument array here
    foreach(i; 1 .. 17) {
        string args = "_" ~ ",_".repeat(i - 1).join;
        // God have mercy on my soul for this format string
        ret ~= format!q{
            @WrenPrimitive("Fn", "call(%1$s)", MethodType.METHOD_FUNCTION_CALL)
            bool fn_call%2$d(WrenVM* vm, Value* args) @nogc
            {
                call_fn(vm, args, %2$d);
                return false;
            }
        }(args, i);
    }

    return ret;
}());

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

@WrenPrimitive("Num", "toString")
bool num_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, wrenNumToString(vm, AS_NUM(args[0])));   
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
    if (!IS_OBJ(args[0]))
        throw mallocNew!Error("Received `this` which is not an object for Object.toString");

    Obj* obj = AS_OBJ(args[0]);
    Value name = OBJ_VAL(obj.classObj.name);
    return RETURN_VAL(args, wrenStringFormat(vm, "instance of @", name));
}

@WrenPrimitive("Object", "type")
bool object_type(WrenVM* vm, Value* args) @nogc
{
    return RETURN_OBJ(args, wrenGetClass(vm, args[0]));
}

@WrenPrimitive("String", "toString")
bool string_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, args[0]);
}

@WrenPrimitive("System", "clock")
bool system_clock(WrenVM* vm, Value* args) @nogc
{
    import core.sys.posix.stdc.time : clock, CLOCKS_PER_SEC;
    return RETURN_NUM(args, cast(double)clock / CLOCKS_PER_SEC);
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

// Creates either the Object or Class class in the core module with [name].
static ObjClass* defineClass(WrenVM* vm, ObjModule* module_, const(char)* name) @nogc
{
  ObjString* nameString = AS_STRING(wrenNewString(vm, name));
  wrenPushRoot(vm, cast(Obj*)nameString);

  ObjClass* classObj = wrenNewSingleClass(vm, 0, nameString);

  wrenDefineVariable(vm, module_, name, nameString.length, OBJ_VAL(classObj), null);

  wrenPopRoot(vm);
  return classObj;
}

private void registerPrimitives(string className)(WrenVM* vm, ObjClass* classObj) {
    static foreach(_mem; __traits(allMembers, mixin(__MODULE__)))
    {{
        import std.traits : getUDAs, hasUDA;
        alias member = __traits(getMember, mixin(__MODULE__), _mem);
        static if (hasUDA!(member, WrenPrimitive)) {
            enum primDef = getUDAs!(member, WrenPrimitive)[0];
            static if (primDef.className == className) {
                PRIMITIVE!(primDef.primitiveName, member, primDef.methodType, primDef.registerToSuperClass)(vm, classObj);
            }
        }
    }}
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
    registerPrimitives!("Object")(vm, vm.objectClass);

    // Now we can define Class, which is a subclass of Object.
    vm.classClass = defineClass(vm, coreModule, "Class");
    wrenBindSuperclass(vm, vm.classClass, vm.objectClass);
    // TODO: define primitives

    // Finally, we can define Object's metaclass which is a subclass of Class.
    ObjClass* objectMetaclass = defineClass(vm, coreModule, "Object metaclass");

    // Wire up the metaclass relationships now that all three classes are built.
    vm.objectClass.obj.classObj = objectMetaclass;
    objectMetaclass.obj.classObj = vm.classClass;
    vm.classClass.obj.classObj = vm.classClass;

    // Do this after wiring up the metaclasses so objectMetaclass doesn't get
    // collected.
    wrenBindSuperclass(vm, objectMetaclass, vm.classClass);
    registerPrimitives!("Object metaclass")(vm, objectMetaclass);

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
    registerPrimitives!("Bool")(vm, vm.boolClass);

    vm.fiberClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Fiber"));
    registerPrimitives!("Fiber")(vm, vm.fiberClass);

    vm.fnClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Fn"));
    registerPrimitives!("Fn")(vm, vm.fnClass);

    vm.nullClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Null"));
    registerPrimitives!("Null")(vm, vm.nullClass);

    vm.numClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Num"));
    registerPrimitives!("Num")(vm, vm.numClass);

    vm.stringClass = AS_CLASS(wrenFindVariable(vm, coreModule, "String"));
    registerPrimitives!("String")(vm, vm.stringClass);

    vm.listClass = AS_CLASS(wrenFindVariable(vm, coreModule, "List"));
    registerPrimitives!("List")(vm, vm.listClass);

    vm.mapClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Map"));
    registerPrimitives!("Map")(vm, vm.mapClass);

    vm.rangeClass = AS_CLASS(wrenFindVariable(vm, coreModule, "Range"));
    registerPrimitives!("Range")(vm, vm.rangeClass);

    ObjClass* systemClass = AS_CLASS(wrenFindVariable(vm, coreModule, "System"));
    registerPrimitives!("System")(vm, systemClass.obj.classObj);


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