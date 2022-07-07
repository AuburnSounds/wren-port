import core.stdc.stdio;
import core.stdc.string;
import wren.compiler;
import wren.vm;

// Show how to do simple foreign functions.
// (you can go further and do "foreign classes", which are a bit different).
void main()
{
	WrenConfiguration config;
	wrenInitConfiguration(&config);
	config.writeFn = &writeFn;
	config.errorFn = &errorFn;
    config.bindForeignMethodFn = &bindForeignMethod;
	
	WrenVM* vm = wrenNewVM(&config);

	const(char)* module_ = "main";
    string script = import("script.wren");

	/*const(char)* script = 
        "class Test {\n" ~
        "    construct new() {\n" ~
        "    }\n" ~
        "    foreign myfun_(a, b, c)" ~
        "}\n"~
        "class Test2 {\n" ~
        "    construct new(e) {\n" ~
        "        _e = e\n" ~
        "    }\n" ~
        "    myprop=(x) {\n" ~
        "        _e.myfun_(0, 1, x)\n" ~
        "    }\n" ~
        "}\n"~
        "var c = Test.new()\n" ~
        "var b = Test2.new(c)\n" ~
        "b.myprop = 0.65\n";*/

	WrenInterpretResult result = wrenInterpret(vm, module_, script.ptr);
	switch (result) with(WrenInterpretResult)
	{
		case WREN_RESULT_COMPILE_ERROR:
		{ printf("Compile Error!\n"); } break;
		case WREN_RESULT_RUNTIME_ERROR:
		{ printf("Runtime Error!\n"); } break;
		case WREN_RESULT_SUCCESS:
		{ printf("Success!\n"); } break;
		default:
			assert(0);
	}

	wrenFreeVM(vm);
}

static void writeFn(WrenVM* vm, const(char)* text) @nogc
{
	printf("%s", text);
}

static void errorFn(WrenVM* vm, WrenErrorType errorType,
					const(char)* module_, int line,
					const(char)* msg) @nogc
{
    switch (errorType) with(WrenErrorType)
    {
        case WREN_ERROR_COMPILE:
            {
                printf("[%s line %d] [Error] %s\n", module_, line, msg);
                break;
            } 
        case WREN_ERROR_STACK_TRACE:
            {
                printf("[%s line %d] in %s\n", module_, line, msg);
                break;
            }
        case WREN_ERROR_RUNTIME:
            {
                printf("[Runtime Error] %s\n", msg);
                break;
            }
        default:
            {
                printf("Unknown Error\n");
                break;
            }
    }
}

WrenForeignMethodFn bindForeignMethod(WrenVM* vm, const(char)* module_, 
                                      const(char)* className, bool isStatic, const(char)* signature) @nogc
{
    printf("sig = %s\n", signature);     
    if (strcmp(signature, "myfun_(_,_,_)") == 0)
        return &myFun;
    return null;
}

void myFun(WrenVM* vm) @nogc
{
    double a = wrenGetSlotDouble(vm, 1);
    double b = wrenGetSlotDouble(vm, 2);
    double c = wrenGetSlotDouble(vm, 3);

    printf("Called with %f, %f, %f\n", a, b, c);
}
