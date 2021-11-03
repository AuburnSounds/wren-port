module wren.dbg;
import core.stdc.stdio : printf;
import wren.common;
import wren.value;
import wren.vm;

void wrenDebugPrintStackTrace(WrenVM* vm)
{
    // Bail if the host doesn't enable printing errors.
    if (vm.config.errorFn == null) return;

    ObjFiber* fiber = vm.fiber;
    if (IS_STRING(fiber.error))
    {
        vm.config.errorFn(vm, WrenErrorType.WREN_ERROR_RUNTIME,
                        null, -1, AS_CSTRING(fiber.error));
    }
    else
    {
        // TODO: Print something a little useful here. Maybe the name of the error's
        // class?
        vm.config.errorFn(vm, WrenErrorType.WREN_ERROR_RUNTIME,
                        null, -1, "[error object]");
    }

    for (int i = fiber.numFrames - 1; i >= 0; i--)
    {
        CallFrame* frame = &fiber.frames[i];
        ObjFn* fn = frame.closure.fn;

        // Skip over stub functions for calling methods from the C API.
        if (fn.module_ == null) continue;
        
        // The built-in core module has no name. We explicitly omit it from stack
        // traces since we don't want to highlight to a user the implementation
        // detail of what part of the core module is written in C and what is Wren.
        if (fn.module_.name == null) continue;
        
        // -1 because IP has advanced past the instruction that it just executed.
        int line = fn.debug_.sourceLines.data[frame.ip - fn.code.data - 1];
        vm.config.errorFn(vm, WrenErrorType.WREN_ERROR_STACK_TRACE,
                        fn.module_.name.value.ptr, line,
                        fn.debug_.name);
    }
}

static void dumpObject(Obj* obj)
{
    switch (obj.type) with(ObjType)
    {
        case OBJ_CLASS:
            printf("[class %s %p]", (cast(ObjClass*)obj).name.value.ptr, obj);
            break;
        case OBJ_CLOSURE: printf("[closure %p]", obj); break;
        case OBJ_FIBER: printf("[fiber %p]", obj); break;
        case OBJ_FN: printf("[fn %p]", obj); break;
        case OBJ_FOREIGN: printf("[foreign %p]", obj); break;
        case OBJ_INSTANCE: printf("[instance %p]", obj); break;
        case OBJ_LIST: printf("[list %p]", obj); break;
        case OBJ_MAP: printf("[map %p]", obj); break;
        case OBJ_MODULE: printf("[module %p]", obj); break;
        case OBJ_RANGE: printf("[range %p]", obj); break;
        case OBJ_STRING: printf("%s", (cast(ObjString*)obj).value.ptr); break;
        case OBJ_UPVALUE: printf("[upvalue %p]", obj); break;
        default: printf("[unknown object %d]", obj.type); break;
    }

}

void wrenDumpValue(Value value)
{
    static if (WREN_NAN_TAGGING)
    {
        if (IS_NUM(value))
        {
            printf("%.14g", AS_NUM(value));
        }
        else if (IS_OBJ(value))
        {
            dumpObject(AS_OBJ(value));
        }
        else
        {
            switch (GET_TAG(value))
            {
                case TAG_FALSE:     printf("false"); break;
                case TAG_NAN:       printf("NaN"); break;
                case TAG_NULL:      printf("null"); break;
                case TAG_TRUE:      printf("true"); break;
                case TAG_UNDEFINED: assert(0, "Unreachable");
                default: assert(0, "Unexpected tag");
            }
        }
    }
    else
    {
        switch (value.type)
        {
            case VAL_FALSE:     printf("false"); break;
            case VAL_NULL:      printf("null"); break;
            case VAL_NUM:       printf("%.14g", AS_NUM(value)); break;
            case VAL_TRUE:      printf("true"); break;
            case VAL_OBJ:       dumpObject(AS_OBJ(value)); break;
            case VAL_UNDEFINED: assert(0, "Unreachable");
            default: assert(0, "Unexpected type");
        }
    }

}

static int dumpInstruction(WrenVM* vm, ObjFn* fn, int i, int* lastLine)
{
    assert(0, "stub");
}

int wrenDumpInstruction(WrenVM* vm, ObjFn* fn, int i)
{
    return dumpInstruction(vm, fn, i, null);
}

void wrenDumpCode(WrenVM* vm, ObjFn* fn)
{
    printf("%s: %s\n",
        fn.module_.name == null ? "<core>" : fn.module_.name.value.ptr,
        fn.debug_.name);

    int i = 0;
    int lastLine = -1;
    for (;;)
    {
        int offset = dumpInstruction(vm, fn, i, &lastLine);
        if (offset == -1) break;
        i += offset;
    }

    printf("\n");
}

void wrenDumpStack(ObjFiber* fiber)
{
    printf("(fiber %p) ", fiber);
    for (Value* slot = fiber.stack; slot < fiber.stackTop; slot++)
    {
        wrenDumpValue(*slot);
        printf(" | ");
    }
    printf("\n");
}
