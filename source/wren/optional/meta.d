module wren.optional.meta;
import wren.value;
import wren.vm;

private static const(char)[] metaModuleSource = import("optional/wren_opt_meta.wren");

void metaCompile(WrenVM* vm) @nogc
{
    const(char)* source = wrenGetSlotString(vm, 1);
    bool isExpression = wrenGetSlotBool(vm, 2);
    bool printErrors = wrenGetSlotBool(vm, 3);

    // TODO: Allow passing in module?
    // Look up the module surrounding the callsite. This is brittle. The -2 walks
    // up the callstack assuming that the meta module has one level of
    // indirection before hitting the user's code. Any change to meta may require
    // this constant to be tweaked.
    ObjFiber* currentFiber = vm.fiber;
    ObjFn* fn = currentFiber.frames[currentFiber.numFrames - 2].closure.fn;
    ObjString* module_ = fn.module_.name;

    ObjClosure* closure = wrenCompileSource(vm, module_.value.ptr, source,
                                            isExpression, printErrors);
    
    // Return the result. We can't use the public API for this since we have a
    // bare ObjClosure*.
    if (closure == null)
    {
        vm.apiStack[0] = NULL_VAL;
    }
    else
    {
        vm.apiStack[0] = OBJ_VAL(closure);
    }
}

void metaGetModuleVariables(WrenVM* vm) @nogc
{
    wrenEnsureSlots(vm, 3);
    
    Value moduleValue = wrenMapGet(vm.modules, vm.apiStack[1]);
    if (IS_UNDEFINED(moduleValue))
    {
        vm.apiStack[0] = NULL_VAL;
        return;
    }
        
    ObjModule* module_ = AS_MODULE(moduleValue);
    ObjList* names = wrenNewList(vm, module_.variableNames.count);
    vm.apiStack[0] = OBJ_VAL(names);

    // Initialize the elements to null in case a collection happens when we
    // allocate the strings below.
    for (int i = 0; i < names.elements.count; i++)
    {
        names.elements.data[i] = NULL_VAL;
    }
    
    for (int i = 0; i < names.elements.count; i++)
    {
        names.elements.data[i] = OBJ_VAL(module_.variableNames.data[i]);
    }
}

const(char)[] wrenMetaSource() @nogc {
    return metaModuleSource;
}

WrenForeignMethodFn wrenMetaBindForeignMethod(WrenVM* vm,
                                              const(char)* className,
                                              bool isStatic,
                                              const(char)* signature) @nogc
{
    import core.stdc.string : strcmp;
    // There is only one foreign method in the meta module.
    assert(strcmp(className, "Meta") == 0, "Should be in Meta class.");
    assert(isStatic, "Should be static.");
    
    if (strcmp(signature, "compile_(_,_,_)") == 0)
    {
        return &metaCompile;
    }
    
    if (strcmp(signature, "getModuleVariables_(_)") == 0)
    {
        return &metaGetModuleVariables;
    }
    
    assert(false, "Unknown method.");
}
