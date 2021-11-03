module wren.compiler;
import wren.common;
import wren.dbg;
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

struct Compiler
{

}

void wrenMarkCompiler(WrenVM* vm, Compiler* compiler)
{
    assert(0, "stub");
    /*
    wrenGrayValue(vm, compiler->parser->current.value);
    wrenGrayValue(vm, compiler->parser->previous.value);
    wrenGrayValue(vm, compiler->parser->next.value);

    // Walk up the parent chain to mark the outer compilers too. The VM only
    // tracks the innermost one.
    do
    {
        wrenGrayObj(vm, (Obj*)compiler->fn);
        wrenGrayObj(vm, (Obj*)compiler->constants);
        wrenGrayObj(vm, (Obj*)compiler->attributes);
        
        if (compiler->enclosingClass != NULL)
        {
        wrenBlackenSymbolTable(vm, &compiler->enclosingClass->fields);

        if(compiler->enclosingClass->methodAttributes != NULL) 
        {
            wrenGrayObj(vm, (Obj*)compiler->enclosingClass->methodAttributes);
        }
        if(compiler->enclosingClass->classAttributes != NULL) 
        {
            wrenGrayObj(vm, (Obj*)compiler->enclosingClass->classAttributes);
        }
        }
        
        compiler = compiler->parent;
    }
    while (compiler != NULL);
    */
}