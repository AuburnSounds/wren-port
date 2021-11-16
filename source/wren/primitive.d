module wren.primitive;
import wren.value;
import wren.vm : WrenVM;

@nogc:

// Validates that [value] is an integer within `[0, count)`. Also allows
// negative indices which map backwards from the end. Returns the valid positive
// index value. If invalid, reports an error and returns `UINT32_MAX`.
uint validateIndexValue(WrenVM* vm, uint count, double value,
                        const(char)* argName)
{
    if (!validateIntValue(vm, value, argName)) return uint.max;

    return uint.max;
}

bool validateFn(WrenVM* vm, Value arg, const(char)* argName)
{
    if (IS_CLOSURE(arg)) return true;
    return RETURN_ERROR(vm, "$ must be a function.", argName);
}

bool validateNum(WrenVM* vm, Value arg, const(char)* argName)
{
    if (IS_NUM(arg)) return true;
    return RETURN_ERROR(vm, "$ must be a number.", argName);
}

bool validateIntValue(WrenVM* vm, double value, const(char)* argName)
{
    import core.stdc.math : trunc;
    if (trunc(value) == value) return true;
    return RETURN_ERROR(vm, "$ must be a number.", argName);
}

bool validateInt(WrenVM* vm, Value arg, const(char)* argName)
{
    // Make sure it's a number first.
    if (!validateNum(vm, arg, argName)) return false;
    return validateIntValue(vm, AS_NUM(arg), argName);
}

bool validateKey(WrenVM* vm, Value arg)
{
    if (wrenMapIsValidKey(arg)) return true;

    return RETURN_ERROR(vm, "Key must be a value type.");
}


uint validateIndex(WrenVM* vm, Value arg, uint count,
                       const(char)* argName)
{
    if (!validateNum(vm, arg, argName)) return uint.max;
    return validateIndexValue(vm, count, AS_NUM(arg), argName);
}

bool validateString(WrenVM* vm, Value arg, const(char)* argName)
{
    if (IS_STRING(arg)) return true;
    return RETURN_ERROR(vm, "$ must be a string.", argName);
}

uint calculateRange(WrenVM* vm, ObjRange* range, uint* length,
                        int* step)
{
    *step = 0;

    // Edge case: an empty range is allowed at the end of a sequence. This way,
    // list[0..-1] and list[0...list.count] can be used to copy a list even when
    // empty.
    if (range.from == *length &&
        range.to == (range.isInclusive ? -1.0 : cast(double)*length))
    {
        *length = 0;
        return 0;
    }

    uint from = validateIndexValue(vm, *length, range.from, "Range start");
    if (from == uint.max) return uint.max;

    // Bounds check the end manually to handle exclusive ranges.
    double value = range.to;
    if (!validateIntValue(vm, value, "Range end")) return uint.max;

    // Negative indices count from the end.
    if (value < 0) value = *length + value;

    // Convert the exclusive range to an inclusive one.
    if (!range.isInclusive)
    {
        // An exclusive range with the same start and end points is empty.
        if (value == from)
        {
        *length = 0;
        return from;
        }

        // Shift the endpoint to make it inclusive, handling both increasing and
        // decreasing ranges.
        value += value >= from ? -1 : 1;
    }

    // Check bounds.
    if (value < 0 || value >= *length)
    {
        vm.fiber.error = CONST_STRING(vm, "Range end out of bounds.");
        return uint.max;
    }

    uint to = cast(uint)value;
    import wren.math : abs;
    *length = abs(cast(int)(from - to)) + 1;
    *step = from < to ? 1 : -1;
    return from;
}

import wren.value : MethodType;

struct WrenPrimitive
{
    import wren.value : MethodType;
    string className;
    string primitiveName;
    MethodType methodType = MethodType.METHOD_PRIMITIVE;
    bool registerToSuperClass = false;
}

template PRIMITIVE(alias name,
                   alias func,
                   MethodType methodType = MethodType.METHOD_PRIMITIVE,
                   bool registerToSuperClass = false)
{
    import wren.value : ObjClass, wrenSymbolTableEnsure, wrenBindMethod, Method;
    void PRIMITIVE(WrenVM* vm, ObjClass* cls) {
        import core.stdc.string : strlen;
        int symbol = wrenSymbolTableEnsure(vm,
            &vm.methodNames, name, strlen(name));
        Method method;
        method.type = methodType;
        method.as.primitive = &func;

        static if (registerToSuperClass) {
            wrenBindMethod(vm, cls.obj.classObj, symbol, method);
        } else {
            wrenBindMethod(vm, cls, symbol, method);
        }
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