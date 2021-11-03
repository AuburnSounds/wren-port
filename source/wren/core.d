module wren.core;
import wren.primitive;
import wren.value;
import wren.vm;

// The core module source
static immutable const(char)[] coreModuleSource = import("wren_core.wren");

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
    static foreach(_mem; __traits(allMembers, wren.core))
    {{
        import std.traits : getUDAs, hasUDA;
        alias member = __traits(getMember, wren.core, _mem);
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

}