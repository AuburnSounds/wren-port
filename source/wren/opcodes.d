module wren.opcodes;

// This defines the bytecode instructions used by the VM. 
// The first argument is the name of the opcode. The second is its "stack
// effect" -- the amount that the op code changes the size of the stack. A
// stack effect of 1 means it pushes a value and the stack grows one larger.
// -2 means it pops two values, etc.
struct WrenOpcode 
{
    string name;
    int stackEffects;
}

static immutable WREN_OPCODE_FULL_TABLE =
[
    // Load the constant at index [arg].
    WrenOpcode("CONSTANT", 1),

    // Push null onto the stack.
    WrenOpcode("NULL", 1),

    // Push false onto the stack.
    WrenOpcode("FALSE", 1),

    // Push true onto the stack.
    WrenOpcode("TRUE", 1),

    // Pushes the value in the given local slot.
    WrenOpcode("LOAD_LOCAL_0", 1),
    WrenOpcode("LOAD_LOCAL_1", 1),
    WrenOpcode("LOAD_LOCAL_2", 1),
    WrenOpcode("LOAD_LOCAL_3", 1),
    WrenOpcode("LOAD_LOCAL_4", 1),
    WrenOpcode("LOAD_LOCAL_5", 1),
    WrenOpcode("LOAD_LOCAL_6", 1),
    WrenOpcode("LOAD_LOCAL_7", 1),
    WrenOpcode("LOAD_LOCAL_8", 1),

    // Note: The compiler assumes the following _STORE instructions always
    // immediately follow their corresponding _LOAD ones.

    // Pushes the value in local slot [arg].
    WrenOpcode("LOAD_LOCAL", 1),

    // Stores the top of stack in local slot [arg]. Does not pop it.
    WrenOpcode("STORE_LOCAL", 0),

    // Pushes the value in upvalue [arg].
    WrenOpcode("LOAD_UPVALUE", 1),

    // Stores the top of stack in upvalue [arg]. Does not pop it.
    WrenOpcode("STORE_UPVALUE", 0),

    // Pushes the value of the top-level variable in slot [arg].
    WrenOpcode("LOAD_MODULE_VAR", 1),

    // Stores the top of stack in top-level variable slot [arg]. Does not pop it.
    WrenOpcode("STORE_MODULE_VAR", 0),

    // Pushes the value of the field in slot [arg] of the receiver of the current
    // function. This is used for regular field accesses on "this" directly in
    // methods. This instruction is faster than the more general CODE_LOAD_FIELD
    // instruction.
    WrenOpcode("LOAD_FIELD_THIS", 1),

    // Stores the top of the stack in field slot [arg] in the receiver of the
    // current value. Does not pop the value. This instruction is faster than the
    // more general CODE_LOAD_FIELD instruction.
    WrenOpcode("STORE_FIELD_THIS", 0),

    // Pops an instance and pushes the value of the field in slot [arg] of it.
    WrenOpcode("LOAD_FIELD", 0),

    // Pops an instance and stores the subsequent top of stack in field slot
    // [arg] in it. Does not pop the value.
    WrenOpcode("STORE_FIELD", -1),

    // Pop and discard the top of stack.
    WrenOpcode("POP", -1),

    // Invoke the method with symbol [arg]. The number indicates the number of
    // arguments (not including the receiver).
    WrenOpcode("CALL_0", 0),
    WrenOpcode("CALL_1", -1),
    WrenOpcode("CALL_2", -2),
    WrenOpcode("CALL_3", -3),
    WrenOpcode("CALL_4", -4),
    WrenOpcode("CALL_5", -5),
    WrenOpcode("CALL_6", -6),
    WrenOpcode("CALL_7", -7),
    WrenOpcode("CALL_8", -8),
    WrenOpcode("CALL_9", -9),
    WrenOpcode("CALL_10", -10),
    WrenOpcode("CALL_11", -11),
    WrenOpcode("CALL_12", -12),
    WrenOpcode("CALL_13", -13),
    WrenOpcode("CALL_14", -14),
    WrenOpcode("CALL_15", -15),
    WrenOpcode("CALL_16", -16),

    // Invoke a superclass method with symbol [arg]. The number indicates the
    // number of arguments (not including the receiver).
    WrenOpcode("SUPER_0", 0),
    WrenOpcode("SUPER_1", -1),
    WrenOpcode("SUPER_2", -2),
    WrenOpcode("SUPER_3", -3),
    WrenOpcode("SUPER_4", -4),
    WrenOpcode("SUPER_5", -5),
    WrenOpcode("SUPER_6", -6),
    WrenOpcode("SUPER_7", -7),
    WrenOpcode("SUPER_8", -8),
    WrenOpcode("SUPER_9", -9),
    WrenOpcode("SUPER_10", -10),
    WrenOpcode("SUPER_11", -11),
    WrenOpcode("SUPER_12", -12),
    WrenOpcode("SUPER_13", -13),
    WrenOpcode("SUPER_14", -14),
    WrenOpcode("SUPER_15", -15),
    WrenOpcode("SUPER_16", -16),

    // Jump the instruction pointer [arg] forward.
    WrenOpcode("JUMP", 0),

    // Jump the instruction pointer [arg] backward.
    WrenOpcode("LOOP", 0),

    // Pop and if not truthy then jump the instruction pointer [arg] forward.
    WrenOpcode("JUMP_IF", -1),

    // If the top of the stack is false, jump [arg] forward. Otherwise, pop and
    // continue.
    WrenOpcode("AND", -1),

    // If the top of the stack is non-false, jump [arg] forward. Otherwise, pop
    // and continue.
    WrenOpcode("OR", -1),

    // Close the upvalue for the local on the top of the stack, then pop it.
    WrenOpcode("CLOSE_UPVALUE", -1),

    // Exit from the current function and return the value on the top of the
    // stack.
    WrenOpcode("RETURN", 0),

    // Creates a closure for the function stored at [arg] in the constant table.
    //
    // Following the function argument is a number of arguments, two for each
    // upvalue. The first is true if the variable being captured is a local (as
    // opposed to an upvalue), and the second is the index of the local or
    // upvalue being captured.
    //
    // Pushes the created closure.
    WrenOpcode("CLOSURE", 1),

    // Creates a new instance of a class.
    //
    // Assumes the class object is in slot zero, and replaces it with the new
    // uninitialized instance of that class. This opcode is only emitted by the
    // compiler-generated constructor metaclass methods.
    WrenOpcode("CONSTRUCT", 0),

    // Creates a new instance of a foreign class.
    //
    // Assumes the class object is in slot zero, and replaces it with the new
    // uninitialized instance of that class. This opcode is only emitted by the
    // compiler-generated constructor metaclass methods.
    WrenOpcode("FOREIGN_CONSTRUCT", 0),

    // Creates a class. Top of stack is the superclass. Below that is a string for
    // the name of the class. Byte [arg] is the number of fields in the class.
    WrenOpcode("CLASS", -1),

    // Ends a class. 
    // Atm the stack contains the class and the ClassAttributes (or null).
    WrenOpcode("END_CLASS", -2),

    // Creates a foreign class. Top of stack is the superclass. Below that is a
    // string for the name of the class.
    WrenOpcode("FOREIGN_CLASS", -1),

    // Define a method for symbol [arg]. The class receiving the method is popped
    // off the stack, then the function defining the body is popped.
    //
    // If a foreign method is being defined, the "function" will be a string
    // identifying the foreign method. Otherwise, it will be a function or
    // closure.
    WrenOpcode("METHOD_INSTANCE", -2),

    // Define a method for symbol [arg]. The class whose metaclass will receive
    // the method is popped off the stack, then the function defining the body is
    // popped.
    //
    // If a foreign method is being defined, the "function" will be a string
    // identifying the foreign method. Otherwise, it will be a function or
    // closure.
    WrenOpcode("METHOD_STATIC", -2),

    // This is executed at the end of the module's body. Pushes NULL onto the stack
    // as the "return value" of the import statement and stores the module as the
    // most recently imported one.
    WrenOpcode("END_MODULE", 1),

    // Import a module whose name is the string stored at [arg] in the constant
    // table.
    //
    // Pushes null onto the stack so that the fiber for the imported module can
    // replace that with a dummy value when it returns. (Fibers always return a
    // value when resuming a caller.)
    WrenOpcode("IMPORT_MODULE", 1),

    // Import a variable from the most recently imported module. The name of the
    // variable to import is at [arg] in the constant table. Pushes the loaded
    // variable's value.
    WrenOpcode("IMPORT_VARIABLE", 1),

    // This pseudo-instruction indicates the end of the bytecode. It should
    // always be preceded by a `CODE_RETURN`, so is never actually executed.
    WrenOpcode("END", 0),
];

// Enum table for opcodes
enum Code {CODE_CONSTANT, CODE_NULL, CODE_FALSE, CODE_TRUE, CODE_LOAD_LOCAL_0, CODE_LOAD_LOCAL_1, CODE_LOAD_LOCAL_2, CODE_LOAD_LOCAL_3, CODE_LOAD_LOCAL_4, CODE_LOAD_LOCAL_5, CODE_LOAD_LOCAL_6, CODE_LOAD_LOCAL_7, CODE_LOAD_LOCAL_8, CODE_LOAD_LOCAL, CODE_STORE_LOCAL, CODE_LOAD_UPVALUE, CODE_STORE_UPVALUE, CODE_LOAD_MODULE_VAR, CODE_STORE_MODULE_VAR, CODE_LOAD_FIELD_THIS, CODE_STORE_FIELD_THIS, CODE_LOAD_FIELD, CODE_STORE_FIELD, CODE_POP, CODE_CALL_0, CODE_CALL_1, CODE_CALL_2, CODE_CALL_3, CODE_CALL_4, CODE_CALL_5, CODE_CALL_6, CODE_CALL_7, CODE_CALL_8, CODE_CALL_9, CODE_CALL_10, CODE_CALL_11, CODE_CALL_12, CODE_CALL_13, CODE_CALL_14, CODE_CALL_15, CODE_CALL_16, CODE_SUPER_0, CODE_SUPER_1, CODE_SUPER_2, CODE_SUPER_3, CODE_SUPER_4, CODE_SUPER_5, CODE_SUPER_6, CODE_SUPER_7, CODE_SUPER_8, CODE_SUPER_9, CODE_SUPER_10, CODE_SUPER_11, CODE_SUPER_12, CODE_SUPER_13, CODE_SUPER_14, CODE_SUPER_15, CODE_SUPER_16, CODE_JUMP, CODE_LOOP, CODE_JUMP_IF, CODE_AND, CODE_OR, CODE_CLOSE_UPVALUE, CODE_RETURN, CODE_CLOSURE, CODE_CONSTRUCT, CODE_FOREIGN_CONSTRUCT, CODE_CLASS, CODE_END_CLASS, CODE_FOREIGN_CLASS, CODE_METHOD_INSTANCE, CODE_METHOD_STATIC, CODE_END_MODULE, CODE_IMPORT_MODULE, CODE_IMPORT_VARIABLE, CODE_END, }

// Generate the stack effects table for opcodes
// PERF: byte or int for interpreter perf?
static immutable stackEffects = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, -1, -1, 0, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12, -13, -14, -15, -16, 0, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12, -13, -14, -15, -16, 0, 0, -1, -1, -1, -1, 0, 1, 0, 0, -1, -2, -1, -2, -2, 1, 1, 1, 0, ];
