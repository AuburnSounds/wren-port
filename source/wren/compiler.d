module wren.compiler;
import wren.common;
import wren.dbg;
import wren.utils;
import wren.value;
import wren.vm;

@nogc:
// This is written in bottom-up order, so the tokenization comes first, then
// parsing/code generation. This minimizes the number of explicit forward
// declarations needed.

// The maximum number of local (i.e. not module level) variables that can be
// declared in a single function, method, or chunk of top level code. This is
// the maximum number of variables in scope at one time, and spans block scopes.
//
// Note that this limitation is also explicit in the bytecode. Since
// `CODE_LOAD_LOCAL` and `CODE_STORE_LOCAL` use a single argument byte to
// identify the local, only 256 can be in scope at one time.
enum MAX_LOCALS = 256;

// The maximum number of upvalues (i.e. variables from enclosing functions)
// that a function can close over.
enum MAX_UPVALUES = 256;

// The maximum number of distinct constants that a function can contain. This
// value is explicit in the bytecode since `CODE_CONSTANT` only takes a single
// two-byte argument.
enum MAX_CONSTANTS = (1 << 16);

// The maximum distance a CODE_JUMP or CODE_JUMP_IF instruction can move the
// instruction pointer.
enum MAX_JUMP = (1 << 16);

// The maximum depth that interpolation can nest. For example, this string has
// three levels:
//
//      "outside %(one + "%(two + "%(three)")")"
enum MAX_INTERPOLATION_NESTING = 8;

// The buffer size used to format a compile error message, excluding the header
// with the module name and error location. Using a hardcoded buffer for this
// is kind of hairy, but fortunately we can control what the longest possible
// message is and handle that. Ideally, we'd use `snprintf()`, but that's not
// available in standard C++98.
enum ERROR_MESSAGE_SIZE = 80 + MAX_VARIABLE_NAME + 15;

enum TokenType
{
    TOKEN_LEFT_PAREN,
    TOKEN_RIGHT_PAREN,
    TOKEN_LEFT_BRACKET,
    TOKEN_RIGHT_BRACKET,
    TOKEN_LEFT_BRACE,
    TOKEN_RIGHT_BRACE,
    TOKEN_COLON,
    TOKEN_DOT,
    TOKEN_DOTDOT,
    TOKEN_DOTDOTDOT,
    TOKEN_COMMA,
    TOKEN_STAR,
    TOKEN_SLASH,
    TOKEN_PERCENT,
    TOKEN_HASH,
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_LTLT,
    TOKEN_GTGT,
    TOKEN_PIPE,
    TOKEN_PIPEPIPE,
    TOKEN_CARET,
    TOKEN_AMP,
    TOKEN_AMPAMP,
    TOKEN_BANG,
    TOKEN_TILDE,
    TOKEN_QUESTION,
    TOKEN_EQ,
    TOKEN_LT,
    TOKEN_GT,
    TOKEN_LTEQ,
    TOKEN_GTEQ,
    TOKEN_EQEQ,
    TOKEN_BANGEQ,

    TOKEN_BREAK,
    TOKEN_CONTINUE,
    TOKEN_CLASS,
    TOKEN_CONSTRUCT,
    TOKEN_ELSE,
    TOKEN_FALSE,
    TOKEN_FOR,
    TOKEN_FOREIGN,
    TOKEN_IF,
    TOKEN_IMPORT,
    TOKEN_AS,
    TOKEN_IN,
    TOKEN_IS,
    TOKEN_NULL,
    TOKEN_RETURN,
    TOKEN_STATIC,
    TOKEN_SUPER,
    TOKEN_THIS,
    TOKEN_TRUE,
    TOKEN_VAR,
    TOKEN_WHILE,

    TOKEN_FIELD,
    TOKEN_STATIC_FIELD,
    TOKEN_NAME,
    TOKEN_NUMBER,
    
    // A string literal without any interpolation, or the last section of a
    // string following the last interpolated expression.
    TOKEN_STRING,
    
    // A portion of a string literal preceding an interpolated expression. This
    // string:
    //
    //     "a %(b) c %(d) e"
    //
    // is tokenized to:
    //
    //     TOKEN_INTERPOLATION "a "
    //     TOKEN_NAME          b
    //     TOKEN_INTERPOLATION " c "
    //     TOKEN_NAME          d
    //     TOKEN_STRING        " e"
    TOKEN_INTERPOLATION,

    TOKEN_LINE,

    TOKEN_ERROR,
    TOKEN_EOF
}

struct Token
{
    TokenType type;

    // The beginning of the token, pointing directly into the source.
    const(char)* start;

    // The length of the token in characters.
    int length;

    // The 1-based line where the token appears.
    int line;
  
    // The parsed value if the token is a literal.
    Value value;
}

struct Parser
{
    WrenVM* vm;

    // The module being parsed.
    ObjModule* module_;

    // The source code being parsed.
    const(char)* source;

    // The beginning of the currently-being-lexed token in [source].
    const(char)* tokenStart;

    // The current character being lexed in [source].
    const(char)* currentChar;

    // The 1-based line number of [currentChar].
    int currentLine;

    // The upcoming token.
    Token next;

    // The most recently lexed token.
    Token current;

    // The most recently consumed/advanced token.
    Token previous;
    
    // Tracks the lexing state when tokenizing interpolated strings.
    //
    // Interpolated strings make the lexer not strictly regular: we don't know
    // whether a ")" should be treated as a RIGHT_PAREN token or as ending an
    // interpolated expression unless we know whether we are inside a string
    // interpolation and how many unmatched "(" there are. This is particularly
    // complex because interpolation can nest:
    //
    //     " %( " %( inner ) " ) "
    //
    // This tracks that state. The parser maintains a stack of ints, one for each
    // level of current interpolation nesting. Each value is the number of
    // unmatched "(" that are waiting to be closed.
    int[MAX_INTERPOLATION_NESTING] parens;
    int numParens;

    // Whether compile errors should be printed to stderr or discarded.
    bool printErrors;

    // If a syntax or compile error has occurred.
    bool hasError;
}

struct Local
{
    // The name of the local variable. This points directly into the original
    // source code string.
    const(char)* name;

    // The length of the local variable's name.
    int length;

    // The depth in the scope chain that this variable was declared at. Zero is
    // the outermost scope--parameters for a method, or the first local block in
    // top level code. One is the scope within that, etc.
    int depth;

    // If this local variable is being used as an upvalue.
    bool isUpvalue;
}

struct CompilerUpvalue
{
    // True if this upvalue is capturing a local variable from the enclosing
    // function. False if it's capturing an upvalue.
    bool isLocal;

    // The index of the local or upvalue being captured in the enclosing function.
    int index;
}

struct Loop
{
    // Index of the instruction that the loop should jump back to.
    int start;

    // Index of the argument for the CODE_JUMP_IF instruction used to exit the
    // loop. Stored so we can patch it once we know where the loop ends.
    int exitJump;

    // Index of the first instruction of the body of the loop.
    int body_;

    // Depth of the scope(s) that need to be exited if a break is hit inside the
    // loop.
    int scopeDepth;

    // The loop enclosing this one, or null if this is the outermost loop.
    Loop* enclosing;
}

// The different signature syntaxes for different kinds of methods.
enum SignatureType
{
    // A name followed by a (possibly empty) parenthesized parameter list. Also
    // used for binary operators.
    SIG_METHOD,
    
    // Just a name. Also used for unary operators.
    SIG_GETTER,
    
    // A name followed by "=".
    SIG_SETTER,
    
    // A square bracketed parameter list.
    SIG_SUBSCRIPT,
    
    // A square bracketed parameter list followed by "=".
    SIG_SUBSCRIPT_SETTER,
    
    // A constructor initializer function. This has a distinct signature to
    // prevent it from being invoked directly outside of the constructor on the
    // metaclass.
    SIG_INITIALIZER
}

struct Signature
{
    const(char)* name;
    int length;
    SignatureType type;
    int arity;
}

struct ClassInfo
{
    // The name of the class.
    ObjString* name;
    
    // Attributes for the class itself
    ObjMap* classAttributes;
    // Attributes for methods in this class
    ObjMap* methodAttributes;

    // Symbol table for the fields of the class.
    SymbolTable fields;

    // Symbols for the methods defined by the class. Used to detect duplicate
    // method definitions.
    IntBuffer methods;
    IntBuffer staticMethods;

    // True if the class being compiled is a foreign class.
    bool isForeign;
    
    // True if the current method being compiled is static.
    bool inStatic;

    // The signature of the method being compiled.
    Signature* signature;
}

struct Compiler
{
    Parser* parser;

    // The compiler for the function enclosing this one, or null if it's the
    // top level.
    Compiler* parent;

    // The currently in scope local variables.
    Local[MAX_LOCALS] locals;

    // The number of local variables currently in scope.
    int numLocals;

    // The upvalues that this function has captured from outer scopes. The count
    // of them is stored in [numUpvalues].
    CompilerUpvalue[MAX_UPVALUES] upvalues;

    // The current level of block scope nesting, where zero is no nesting. A -1
    // here means top-level code is being compiled and there is no block scope
    // in effect at all. Any variables declared will be module-level.
    int scopeDepth;
    
    // The current number of slots (locals and temporaries) in use.
    //
    // We use this and maxSlots to track the maximum number of additional slots
    // a function may need while executing. When the function is called, the
    // fiber will check to ensure its stack has enough room to cover that worst
    // case and grow the stack if needed.
    //
    // This value here doesn't include parameters to the function. Since those
    // are already pushed onto the stack by the caller and tracked there, we
    // don't need to double count them here.
    int numSlots;

    // The current innermost loop being compiled, or null if not in a loop.
    Loop* loop;

    // If this is a compiler for a method, keeps track of the class enclosing it.
    ClassInfo* enclosingClass;

    // The function being compiled.
    ObjFn* fn;
    
    // The constants for the function being compiled.
    ObjMap* constants;

    // Whether or not the compiler is for a constructor initializer
    bool isInitializer;

    // The number of attributes seen while parsing.
    // We track this separately as compile time attributes
    // are not stored, so we can't rely on attributes.count
    // to enforce an error message when attributes are used
    // anywhere other than methods or classes.
    int numAttributes;
    // Attributes for the next class or method.
    ObjMap* attributes;
}

// Describes where a variable is declared.
enum Scope
{
    // A local variable in the current function.
    SCOPE_LOCAL,
    
    // A local variable declared in an enclosing function.
    SCOPE_UPVALUE,
    
    // A top-level module variable.
    SCOPE_MODULE
}

// A reference to a variable and the scope where it is defined. This contains
// enough information to emit correct code to load or store the variable.
struct Variable
{
    // The stack slot, upvalue slot, or module symbol defining the variable.
    int index;
  
    // Where the variable is declared.
    Scope scope_;
}

import core.stdc.stdarg;
static void printError(Parser* parser, int line, const(char)* label,
                       const(char)* format, va_list args)
{
    import core.stdc.stdio;
    parser.hasError = true;
    if (!parser.printErrors) return;

    // Only report errors if there is a WrenErrorFn to handle them.
    if (parser.vm.config.errorFn == null) return;

    // Format the label and message.
    char[ERROR_MESSAGE_SIZE] message;
    int length = sprintf(message.ptr, "%s: ", label);
    length += vsprintf(message.ptr + length, format, args);
    assert(length < ERROR_MESSAGE_SIZE, "Error should not exceed buffer.");

    ObjString* module_ = parser.module_.name;
    const(char)* module_name = module_ ? module_.value.ptr : "<unknown>";

    parser.vm.config.errorFn(parser.vm, WrenErrorType.WREN_ERROR_COMPILE,
                                module_name, line, message.ptr);
}

// Outputs a lexical error.
static void lexError(Parser* parser, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    printError(parser, parser.currentLine, "Error", format, args);
    va_end(args);
}

// Outputs a compile or syntax error. This also marks the compilation as having
// an error, which ensures that the resulting code will be discarded and never
// run. This means that after calling error(), it's fine to generate whatever
// invalid bytecode you want since it won't be used.
//
// You'll note that most places that call error() continue to parse and compile
// after that. That's so that we can try to find as many compilation errors in
// one pass as possible instead of just bailing at the first one.
static void error(Compiler* compiler, const char* format, ...)
{
    import core.stdc.stdio;
    Token* token = &compiler.parser.previous;

    // If the parse error was caused by an error token, the lexer has already
    // reported it.
    if (token.type == TokenType.TOKEN_ERROR) return;
    
    va_list args;
    va_start(args, format);
    if (token.type == TokenType.TOKEN_LINE)
    {
        printError(compiler.parser, token.line, "Error at newline", format, args);
    }
    else if (token.type == TokenType.TOKEN_EOF)
    {
        printError(compiler.parser, token.line,
                "Error at end of file", format, args);
    }
    else
    {
        // Make sure we don't exceed the buffer with a very long token.
        char[10 + MAX_VARIABLE_NAME + 4 + 1] label;
        if (token.length <= MAX_VARIABLE_NAME)
        {
            sprintf(label.ptr, "Error at '%.*s'", token.length, token.start);
        }
        else
        {
            sprintf(label.ptr, "Error at '%.*s...'", MAX_VARIABLE_NAME, token.start);
        }
        printError(compiler.parser, token.line, label.ptr, format, args);
    }
    va_end(args);
}

// Adds [constant] to the constant pool and returns its index.
static int addConstant(Compiler* compiler, Value constant)
{
    if (compiler.parser.hasError) return -1;
    
    // See if we already have a constant for the value. If so, reuse it.
    if (compiler.constants != null)
    {
        Value existing = wrenMapGet(compiler.constants, constant);
        if (IS_NUM(existing)) return cast(int)AS_NUM(existing);
    }
    
    // It's a new constant.
    if (compiler.fn.constants.count < MAX_CONSTANTS)
    {
        if (IS_OBJ(constant)) wrenPushRoot(compiler.parser.vm, AS_OBJ(constant));
        wrenValueBufferWrite(compiler.parser.vm, &compiler.fn.constants,
                            constant);
        if (IS_OBJ(constant)) wrenPopRoot(compiler.parser.vm);
        
        if (compiler.constants == null)
        {
            compiler.constants = wrenNewMap(compiler.parser.vm);
        }
        wrenMapSet(compiler.parser.vm, compiler.constants, constant,
                NUM_VAL(compiler.fn.constants.count - 1));
    }
    else
    {
        error(compiler, "A function may only contain %d unique constants.",
            MAX_CONSTANTS);
    }

    return compiler.fn.constants.count - 1;
}

// Initializes [compiler].
static void initCompiler(Compiler* compiler, Parser* parser, Compiler* parent,
                         bool isMethod)
{
    compiler.parser = parser;
    compiler.parent = parent;
    compiler.loop = null;
    compiler.enclosingClass = null;
    compiler.isInitializer = false;
    
    // Initialize these to null before allocating in case a GC gets triggered in
    // the middle of initializing the compiler.
    compiler.fn = null;
    compiler.constants = null;
    compiler.attributes = null;

    parser.vm.compiler = compiler;

    // Declare a local slot for either the closure or method receiver so that we
    // don't try to reuse that slot for a user-defined local variable. For
    // methods, we name it "this", so that we can resolve references to that like
    // a normal variable. For functions, they have no explicit "this", so we use
    // an empty name. That way references to "this" inside a function walks up
    // the parent chain to find a method enclosing the function whose "this" we
    // can close over.
    compiler.numLocals = 1;
    compiler.numSlots = compiler.numLocals;

    if (isMethod)
    {
        compiler.locals[0].name = "this";
        compiler.locals[0].length = 4;
    }
    else
    {
        compiler.locals[0].name = null;
        compiler.locals[0].length = 0;
    }
    
    compiler.locals[0].depth = -1;
    compiler.locals[0].isUpvalue = false;

    if (parent == null)
    {
        // Compiling top-level code, so the initial scope is module-level.
        compiler.scopeDepth = -1;
    }
    else
    {
        // The initial scope for functions and methods is local scope.
        compiler.scopeDepth = 0;
    }
    
    compiler.numAttributes = 0;
    compiler.attributes = wrenNewMap(parser.vm);
    compiler.fn = wrenNewFunction(parser.vm, parser.module_,
                                    compiler.numLocals);
}

// Lexing ----------------------------------------------------------------------

struct Keyword
{
    const(char)* identifier;
    size_t      length;
    TokenType   tokenType;
}

static immutable Keyword[] keywords =
[
    {"break",     5, TokenType.TOKEN_BREAK},
    {"continue",  8, TokenType.TOKEN_CONTINUE},
    {"class",     5, TokenType.TOKEN_CLASS},
    {"construct", 9, TokenType.TOKEN_CONSTRUCT},
    {"else",      4, TokenType.TOKEN_ELSE},
    {"false",     5, TokenType.TOKEN_FALSE},
    {"for",       3, TokenType.TOKEN_FOR},
    {"foreign",   7, TokenType.TOKEN_FOREIGN},
    {"if",        2, TokenType.TOKEN_IF},
    {"import",    6, TokenType.TOKEN_IMPORT},
    {"as",        2, TokenType.TOKEN_AS},
    {"in",        2, TokenType.TOKEN_IN},
    {"is",        2, TokenType.TOKEN_IS},
    {"null",      4, TokenType.TOKEN_NULL},
    {"return",    6, TokenType.TOKEN_RETURN},
    {"static",    6, TokenType.TOKEN_STATIC},
    {"super",     5, TokenType.TOKEN_SUPER},
    {"this",      4, TokenType.TOKEN_THIS},
    {"true",      4, TokenType.TOKEN_TRUE},
    {"var",       3, TokenType.TOKEN_VAR},
    {"while",     5, TokenType.TOKEN_WHILE},
    {null,        0, TokenType.TOKEN_EOF} // Sentinel to mark the end of the array.
];

// Returns true if [c] is a valid (non-initial) identifier character.
static bool isName(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

// Returns true if [c] is a digit.
static bool isDigit(char c)
{
    return c >= '0' && c <= '9';
}

// Returns the current character the parser is sitting on.
static char peekChar(Parser* parser)
{
    return *parser.currentChar;
}

// Returns the character after the current character.
static char peekNextChar(Parser* parser)
{
    // If we're at the end of the source, don't read past it.
    if (peekChar(parser) == '\0') return '\0';
    return *(parser.currentChar + 1);
}

// Advances the parser forward one character.
static char nextChar(Parser* parser)
{
    char c = peekChar(parser);
    parser.currentChar++;
    if (c == '\n') parser.currentLine++;
    return c;
}

// If the current character is [c], consumes it and returns `true`.
static bool matchChar(Parser* parser, char c)
{
    if (peekChar(parser) != c) return false;
    nextChar(parser);
    return true;
}

// Sets the parser's current token to the given [type] and current character
// range.
static void makeToken(Parser* parser, TokenType type)
{
    parser.next.type = type;
    parser.next.start = parser.tokenStart;
    parser.next.length = cast(int)(parser.currentChar - parser.tokenStart);
    parser.next.line = parser.currentLine;
    
    // Make line tokens appear on the line containing the "\n".
    if (type == TokenType.TOKEN_LINE) parser.next.line--;
}

// If the current character is [c], then consumes it and makes a token of type
// [two]. Otherwise makes a token of type [one].
static void twoCharToken(Parser* parser, char c, TokenType two, TokenType one)
{
    makeToken(parser, matchChar(parser, c) ? two : one);
}

// Skips the rest of the current line.
static void skipLineComment(Parser* parser)
{
    while (peekChar(parser) != '\n' && peekChar(parser) != '\0')
    {
        nextChar(parser);
    }
}

// Skips the rest of a block comment.
static void skipBlockComment(Parser* parser)
{
    int nesting = 1;
    while (nesting > 0)
    {
        if (peekChar(parser) == '\0')
        {
            lexError(parser, "Unterminated block comment.");
            return;
        }

        if (peekChar(parser) == '/' && peekNextChar(parser) == '*')
        {
            nextChar(parser);
            nextChar(parser);
            nesting++;
            continue;
        }

        if (peekChar(parser) == '*' && peekNextChar(parser) == '/')
        {
            nextChar(parser);
            nextChar(parser);
            nesting--;
            continue;
        }

        // Regular comment character.
        nextChar(parser);
    }
}

// Reads the next character, which should be a hex digit (0-9, a-f, or A-F) and
// returns its numeric value. If the character isn't a hex digit, returns -1.
static int readHexDigit(Parser* parser)
{
    char c = nextChar(parser);
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;

    // Don't consume it if it isn't expected. Keeps us from reading past the end
    // of an unterminated string.
    parser.currentChar--;
    return -1;
}

// Parses the numeric value of the current token.
static void makeNumber(Parser* parser, bool isHex)
{
    import core.stdc.errno;
    import core.stdc.stdlib;

    errno = 0;

    if (isHex)
    {
        parser.next.value = NUM_VAL(cast(double)strtoll(parser.tokenStart, null, 16));
    }
    else
    {
        parser.next.value = NUM_VAL(strtod(parser.tokenStart, null));
    }

    if (errno == ERANGE)
    {
        lexError(parser, "Number literal was too large (%d).", ulong.sizeof);
        parser.next.value = NUM_VAL(0);
    }

    // We don't check that the entire token is consumed after calling strtoll()
    // or strtod() because we've already scanned it ourselves and know it's valid.

    makeToken(parser, TokenType.TOKEN_NUMBER);
}

// Finishes lexing a hexadecimal number literal.
static void readHexNumber(Parser* parser)
{
    // Skip past the `x` used to denote a hexadecimal literal.
    nextChar(parser);

    // Iterate over all the valid hexadecimal digits found.
    while (readHexDigit(parser) != -1) continue;

    makeNumber(parser, true);
}

// Finishes lexing a number literal.
static void readNumber(Parser* parser)
{
    while (isDigit(peekChar(parser))) nextChar(parser);

    // See if it has a floating point. Make sure there is a digit after the "."
    // so we don't get confused by method calls on number literals.
    if (peekChar(parser) == '.' && isDigit(peekNextChar(parser)))
    {
        nextChar(parser);
        while (isDigit(peekChar(parser))) nextChar(parser);
    }

    // See if the number is in scientific notation.
    if (matchChar(parser, 'e') || matchChar(parser, 'E'))
    {
        // Allow a single positive/negative exponent symbol.
        if(!matchChar(parser, '+'))
        {
        matchChar(parser, '-');
        }

        if (!isDigit(peekChar(parser)))
        {
        lexError(parser, "Unterminated scientific notation.");
        }

        while (isDigit(peekChar(parser))) nextChar(parser);
    }

    makeNumber(parser, false);
}


void wrenMarkCompiler(WrenVM* vm, Compiler* compiler)
{
    assert(0, "stub");
    /*
    wrenGrayValue(vm, compiler.parser.current.value);
    wrenGrayValue(vm, compiler.parser.previous.value);
    wrenGrayValue(vm, compiler.parser.next.value);

    // Walk up the parent chain to mark the outer compilers too. The VM only
    // tracks the innermost one.
    do
    {
        wrenGrayObj(vm, (Obj*)compiler.fn);
        wrenGrayObj(vm, (Obj*)compiler.constants);
        wrenGrayObj(vm, (Obj*)compiler.attributes);
        
        if (compiler.enclosingClass != null)
        {
        wrenBlackenSymbolTable(vm, &compiler.enclosingClass.fields);

        if(compiler.enclosingClass.methodAttributes != null) 
        {
            wrenGrayObj(vm, (Obj*)compiler.enclosingClass.methodAttributes);
        }
        if(compiler.enclosingClass.classAttributes != null) 
        {
            wrenGrayObj(vm, (Obj*)compiler.enclosingClass.classAttributes);
        }
        }
        
        compiler = compiler.parent;
    }
    while (compiler != null);
    */
}