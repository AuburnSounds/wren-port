import core.stdc.stdio;
import wren.compiler;
import wren.vm;

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

void main()
{
	WrenConfiguration config;
	wrenInitConfiguration(&config);
	config.writeFn = &writeFn;
	config.errorFn = &errorFn;
	
	WrenVM* vm = wrenNewVM(&config);

	const(char)* module_ = "main";
	const(char)* script = "System.print(\"I am running in a VM!\")";

	WrenInterpretResult result = wrenInterpret(vm, module_, script);
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
