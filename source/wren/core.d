module wren.core;
import wren.primitive;
import wren.value;
import wren.vm;

// The core module source
static const(char)[] coreModuleSource = import("wren_core.wren");

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
///
unittest
{
    import core.stdc.string : strcmp;
    WrenVM* vm = wrenNewVM(null);
    // Test toString for true booleans
    {
        Value[] args = [BOOL_VAL(true)];
        assert(bool_toString(vm, args.ptr));
        assert(AS_CSTRING(args[0]));
        assert(strcmp(AS_CSTRING(args[0]), "true") == 0);
    }
    // Test toString for false booleans
    {
        Value[] args = [BOOL_VAL(false)];
        assert(bool_toString(vm, args.ptr));
        assert(AS_CSTRING(args[0]));
        assert(strcmp(AS_CSTRING(args[0]), "false") == 0);
    }

    wrenFreeVM(vm);
}

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

@WrenPrimitive("String", "toString")
bool string_toString(WrenVM* vm, Value* args) @nogc
{
    return RETURN_VAL(args, args[0]);
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
                PRIMITIVE!(primDef.primitiveName, member)(vm, classObj);
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

    vm.stringClass = AS_CLASS(wrenFindVariable(vm, coreModule, "String"));
    registerPrimitives!("String")(vm, vm.stringClass);

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