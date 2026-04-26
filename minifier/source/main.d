module main;

import std.stdio;
import std.file  : exists, readText, write, FileException;
import std.path  : extension;

import lexer;
import ast;
import parser;
import optimizer;
import printer;

version (unittest)
{
    void main() {}
}
else
{
    int main(string[] args)
    {
        if (args.length < 3)
        {
            stderr.writefln("Usage: %s <input.wren> <output.wren>", args[0]);
            return 1;
        }
        string inputPath  = args[1];
        string outputPath = args[2];
        if (extension(inputPath) != ".wren" || extension(outputPath) != ".wren")
        {
            stderr.writeln("Error: both input and output must be .wren files");
            return 1;
        }
        if (!exists(inputPath))
        {
            stderr.writefln("Error: input file not found: %s", inputPath);
            return 1;
        }
        try
        {
            string source = readText(inputPath);
            Token[] tokens = tokenize(source);
            WrenModule mod = parseModule(tokens);
            optimizeModule(mod);
            string output = printModule(mod);
            write(outputPath, output);
            return 0;
        }
        catch (LexError e)      { stderr.writeln(e.msg); return 1; }
        catch (ParseError e)    { stderr.writeln(e.msg); return 1; }
        catch (FileException e) { stderr.writeln(e.msg); return 1; }
    }
}

unittest
{
    import std.file      : remove;
    import std.algorithm : canFind;
    import std.exception : collectException;

    string inp = `class Counter {
  construct new(start) {
    _value = start
  }
  increment {
    var step = 1
    _value = _value + step
  }
  value { _value }
}
`;
    write("_test_input.wren", inp);
    scope(exit) collectException(remove("_test_input.wren"));
    scope(exit) collectException(remove("_test_output.wren"));

    auto tokens = tokenize(readText("_test_input.wren"));
    auto mod    = parseModule(tokens);
    optimizeModule(mod);
    string out_ = printModule(mod);
    write("_test_output.wren", out_);

    string result = readText("_test_output.wren");
    assert(result.canFind("_value+1"), result);  // step=1 folded
    assert(!result.canFind("step"),    result);  // dead var removed
    assert(result.canFind("new(a)"),   result);  // start → a
}
