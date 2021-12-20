module wren.dbg;
import core.stdc.stdio : printf;
import wren.common;
import wren.opcodes;
import wren.value;
import wren.vm;

@nogc:

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

void dumpObject(Obj* obj)
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
        switch (value.type) with(ValueType)
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

int dumpInstruction(WrenVM* vm, ObjFn* fn, int i, int* lastLine)
{
    int start = i;
    ubyte* bytecode = fn.code.data;
    Code code = cast(Code)bytecode[i];

    int line = fn.debug_.sourceLines.data[i];
    if (lastLine == null || *lastLine != line)
    {
        printf("%4d:", line);
        if (lastLine != null) *lastLine = line;
    }
    else
    {
        printf("     ");
    }

    printf(" %04d  ", i++);

    ubyte READ_BYTE() {
        return bytecode[i++];
    }

    ushort READ_SHORT() {
        i += 2;
        return (bytecode[i - 2] << 8 | bytecode[i - 1]);
    }

    switch (code) with (Code)
    {
        case CODE_CONSTANT:
        {
            int constant = READ_SHORT();
            printf("%-16s %5d '", "CONSTANT".ptr, constant);
            wrenDumpValue(fn.constants.data[constant]);
            printf("'\n");
            break;
        }

        case CODE_NULL:  printf("NULL\n"); break;
        case CODE_FALSE: printf("FALSE\n"); break;
        case CODE_TRUE:  printf("TRUE\n"); break;

        case CODE_LOAD_LOCAL_0: printf("LOAD_LOCAL_0\n"); break;
        case CODE_LOAD_LOCAL_1: printf("LOAD_LOCAL_1\n"); break;
        case CODE_LOAD_LOCAL_2: printf("LOAD_LOCAL_2\n"); break;
        case CODE_LOAD_LOCAL_3: printf("LOAD_LOCAL_3\n"); break;
        case CODE_LOAD_LOCAL_4: printf("LOAD_LOCAL_4\n"); break;
        case CODE_LOAD_LOCAL_5: printf("LOAD_LOCAL_5\n"); break;
        case CODE_LOAD_LOCAL_6: printf("LOAD_LOCAL_6\n"); break;
        case CODE_LOAD_LOCAL_7: printf("LOAD_LOCAL_7\n"); break;
        case CODE_LOAD_LOCAL_8: printf("LOAD_LOCAL_8\n"); break;

        case CODE_LOAD_LOCAL: {
            printf("%-16s %5d\n", "LOAD_LOCAL".ptr, READ_BYTE()); break;
        }

        case CODE_STORE_LOCAL: printf("%-16s %5d\n", "STORE_LOCAL".ptr, READ_BYTE()); break;
        case CODE_LOAD_UPVALUE: printf("%-16s %5d\n", "LOAD_UPVALUE".ptr, READ_BYTE()); break;
        case CODE_STORE_UPVALUE: printf("%-16s %5d\n", "STORE_UPVALUE".ptr, READ_BYTE()); break;

        case CODE_LOAD_MODULE_VAR:
        {
            int slot = READ_SHORT();
            printf("%-16s %5d '%s'\n", "LOAD_MODULE_VAR".ptr, slot,
                    fn.module_.variableNames.data[slot].value.ptr);
            break;
        }

        case CODE_STORE_MODULE_VAR:
        {
            int slot = READ_SHORT();
            printf("%-16s %5d '%s'\n", "STORE_MODULE_VAR".ptr, slot,
                    fn.module_.variableNames.data[slot].value.ptr);
            break;
        }            

        case CODE_LOAD_FIELD_THIS: printf("%-16s %5d\n", "LOAD_FIELD_THIS".ptr, READ_BYTE()); break;       
        case CODE_STORE_FIELD_THIS:  printf("%-16s %5d\n", "STORE_FIELD_THIS".ptr, READ_BYTE()); break;        
        case CODE_LOAD_FIELD: printf("%-16s %5d\n", "LOAD_FIELD".ptr, READ_BYTE()); break;        
        case CODE_STORE_FIELD: printf("%-16s %5d\n", "STORE_FIELD".ptr, READ_BYTE()); break;

        case CODE_POP: printf("POP\n"); break;

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
        {
            int numArgs = bytecode[i - 1] - CODE_CALL_0;
            int symbol = READ_SHORT();
            printf("CALL_%-11d %5d '%s'\n", numArgs, symbol,
                    vm.methodNames.data[symbol].value.ptr);
            break;
        }

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
            int numArgs = bytecode[i - 1] - CODE_SUPER_0;
            int symbol = READ_SHORT();
            int superclass = READ_SHORT();
            printf("SUPER_%-10d %5d '%s' %5d\n", numArgs, symbol,
                    vm.methodNames.data[symbol].value.ptr, superclass);
            break;
        }

        case CODE_JUMP:
        {
            int offset = READ_SHORT();
            printf("%-16s %5d to %d\n", "JUMP".ptr, offset, i + offset);
            break;
        }

        case CODE_LOOP:
        {
            int offset = READ_SHORT();
            printf("%-16s %5d to %d\n", "LOOP".ptr, offset, i - offset);
            break;
        }

        case CODE_JUMP_IF:
        {
            int offset = READ_SHORT();
            printf("%-16s %5d to %d\n", "JUMP_IF".ptr, offset, i + offset);
            break;
        }

        case CODE_AND:
        {
            int offset = READ_SHORT();
            printf("%-16s %5d to %d\n", "AND".ptr, offset, i + offset);
            break;
        }

        case CODE_OR:
        {
            int offset = READ_SHORT();
            printf("%-16s %5d to %d\n", "OR".ptr, offset, i + offset);
            break;
        }

        case CODE_CLOSE_UPVALUE: printf("CLOSE_UPVALUE\n"); break;
        case CODE_RETURN:        printf("RETURN\n"); break;

        case CODE_CLOSURE:
        {
            int constant = READ_SHORT();
            printf("%-16s %5d ", "CLOSURE".ptr, constant);
            wrenDumpValue(fn.constants.data[constant]);
            printf(" ");
            ObjFn* loadedFn = AS_FN(fn.constants.data[constant]);
            for (int j = 0; j < loadedFn.numUpvalues; j++)
            {
                int isLocal = READ_BYTE();
                int index = READ_BYTE();
                if (j > 0) printf(", ");
                printf("%s %d", isLocal ? "local".ptr : "upvalue".ptr, index);
            }
            printf("\n");
            break;
        }

        case CODE_CONSTRUCT:         printf("CONSTRUCT\n"); break;
        case CODE_FOREIGN_CONSTRUCT: printf("FOREIGN_CONSTRUCT\n"); break;
        
        case CODE_CLASS:
        {
            int numFields = READ_BYTE();
            printf("%-16s %5d fields\n", "CLASS".ptr, numFields);
            break;
        }

        case CODE_FOREIGN_CLASS: printf("FOREIGN_CLASS\n"); break;
        case CODE_END_CLASS: printf("END_CLASS\n"); break;

        case CODE_METHOD_INSTANCE:
        {
            int symbol = READ_SHORT();
            printf("%-16s %5d '%s'\n", "METHOD_INSTANCE".ptr, symbol,
                    vm.methodNames.data[symbol].value.ptr);
            break;
        }

        case CODE_METHOD_STATIC:
        {
            int symbol = READ_SHORT();
            printf("%-16s %5d '%s'\n", "METHOD_STATIC".ptr, symbol,
                    vm.methodNames.data[symbol].value.ptr);
            break;
        }
        
        case CODE_END_MODULE:
            printf("END_MODULE\n");
            break;
        
        case CODE_IMPORT_MODULE:
        {
            int name = READ_SHORT();
            printf("%-16s %5d '", "IMPORT_MODULE".ptr, name);
            wrenDumpValue(fn.constants.data[name]);
            printf("'\n");
            break;
        }
        
        case CODE_IMPORT_VARIABLE:
        {
            int variable = READ_SHORT();
            printf("%-16s %5d '", "IMPORT_VARIABLE".ptr, variable);
            wrenDumpValue(fn.constants.data[variable]);
            printf("'\n");
            break;
        }
        
        case CODE_END:
            printf("END\n");
            break;

        default:
            printf("UKNOWN! [%d]\n", bytecode[i - 1]);
            break;
    }

    // Return how many bytes this instruction takes, or -1 if it's an END.
    if (code == Code.CODE_END) return -1;
    return i - start;
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
