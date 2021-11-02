module wren.primitive;
import wren.value;
import wren.vm : WrenVM;

@nogc:

struct WrenPrimitive
{
    string className;
    string primitiveName;
}

template PRIMITIVE(alias name, alias func)
{
    import wren.value : ObjClass, wrenSymbolTableEnsure, wrenBindMethod, Method, MethodType;
    void PRIMITIVE(WrenVM* vm, ObjClass* cls) {
        import core.stdc.string : strlen;
        int symbol = wrenSymbolTableEnsure(vm,
            &vm.methodNames, name, strlen(name));
        Method method;
        method.type = MethodType.METHOD_PRIMITIVE;
        method.as.primitive = &func;
        wrenBindMethod(vm, cls, symbol, method);
    }
}

bool RETURN_VAL(Value* args, Value v)
{
    args[0] = v;
    return true;
}

bool RETURN_OBJ(T)(Value* args, T* obj)
{
    return RETURN_VAL(args, OBJ_VAL(obj));
}

bool RETURN_BOOL(Value* args, bool val)
{
    return RETURN_VAL(args, BOOL_VAL(val));
}

bool RETURN_FALSE(Value* args)
{
    return RETURN_VAL(args, FALSE_VAL);
}

bool RETURN_NULL(Value* args)
{
    return RETURN_VAL(args, NULL_VAL);
}

bool RETURN_NUM(N)(Value* args, N val)
{
    return RETURN_VAL(args, NUM_VAL(val));
}

bool RETURN_TRUE(Value* args)
{
    return RETURN_VAL(args, TRUE_VAL);
}

bool RETURN_ERROR(WrenVM* vm, const(char)* msg)
{
    import core.stdc.string : strlen;
    vm.fiber.error = wrenNewStringLength(vm, msg, strlen(msg));
    return false;    
}

bool RETURN_ERROR(WrenVM* vm, const(char)* fmt, ...)
{
    import core.stdc.stdarg;
    va_list args;
    va_start!(const(char)*)(args, fmt);
    vm.fiber.error = wrenStringFormat(vm, fmt, args);
    va_end(args);
    return false;
}