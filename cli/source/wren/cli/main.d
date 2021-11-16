module wren.cli.main;
import std.getopt;
import std.stdio;
import wren.cli.vm;
import wren.vm;

int main(string[] args)
{
	bool version_ = false;
	auto info = getopt(args,
						std.getopt.config.passThrough,
						"version|v", &version_);

	if (info.helpWanted)
	{
		defaultGetoptPrinter("Wren CLI", info.options);
		return 0;
	}

	if (version_)
	{
		import wren.common : WREN_VERSION_STRING;
		writefln("wren %s", WREN_VERSION_STRING);
		return 0;
	}

	WrenInterpretResult result;
	if (args.length == 1)
	{
		result = runRepl();
	}
	else
	{
		import std.string : toStringz;
		result = runFile(args[1].toStringz);
	}

	// Exit with an error code if the script failed.
	if (result == WrenInterpretResult.WREN_RESULT_COMPILE_ERROR) return 65; // EX_DATAERR.
	if (result == WrenInterpretResult.WREN_RESULT_RUNTIME_ERROR) return 70; // EX_SOFTWARE.
	
	return 0;
}
