module lexer;

import std.ascii : isAlpha, isAlphaNum, isDigit, isHexDigit;
import std.format : format;

enum Tok
{
    // literals
    number, string_,
    // keywords (all prefixed kw to avoid D keyword clash)
    kwAs, kwBreak, kwClass, kwConstruct, kwContinue, kwElse, kwFalse,
    kwFor, kwForeign, kwIf, kwImport, kwIn, kwIs, kwNull, kwReturn,
    kwStatic, kwSuper, kwThis, kwTrue, kwVar, kwWhile,
    // identifier
    ident,
    // arithmetic
    plus, minus, star, slash, percent,
    // comparison / equality
    eq, eqEq, bang, bangEq,
    lt, ltEq, ltLt,
    gt, gtEq, gtGt,
    // bitwise
    amp, ampAmp, pipe, pipePipe, caret, tilde,
    // misc operators
    dollar, question, colon,
    // range
    dotDot, dotDotDot,
    // punctuation
    dot, comma,
    lparen, rparen,
    lbrace, rbrace,
    lbracket, rbracket,
    // sentinels
    newline, eof
}

struct Token
{
    Tok    kind;
    string text;
    int    line;
    int    col;
}

class LexError : Exception
{
    this(string msg, string file = __FILE__, size_t ln = __LINE__)
    { super(msg, file, ln); }
}

private bool canEndStatement(Tok t) pure nothrow
{
    switch (t) with (Tok)
    {
        case ident:
        case number: case string_:
        case kwTrue: case kwFalse: case kwNull:
        case kwThis: case kwSuper:
        case kwBreak: case kwContinue: case kwReturn:
        case rparen: case rbracket: case rbrace:
            return true;
        default:
            return false;
    }
}

Token[] tokenize(string src)
{
    Token[] out_;
    int pos, line = 1, col = 1;
    Tok lastEmitted = Tok.eof; // nothing emitted yet

    void emit(Tok k, string text, int l, int c)
    {
        out_ ~= Token(k, text, l, c);
        lastEmitted = k;
    }

    void emitNewlineIfSignificant()
    {
        if (!canEndStatement(lastEmitted)) return;
        // Don't emit if the next non-whitespace character (on any following line)
        // is '.' — that indicates method-chain continuation across a line break.
        int look = pos + 1;
        while (look < src.length && (src[look] == ' ' || src[look] == '\t' ||
                                     src[look] == '\r' || src[look] == '\n'))
            look++;
        if (look < src.length && src[look] == '.') return;
        emit(Tok.newline, "\n", line, col);
    }

    // Scans a full string token starting at src[pos] which must be '"'.
    // Advances pos past the closing '"'. Returns the full raw text.
    string scanString()
    {
        import std.array : Appender;
        Appender!string buf;

        int startLine = line, startCol = col;

        // Triple-quoted raw string?
        if (pos + 2 < src.length && src[pos+1] == '"' && src[pos+2] == '"')
        {
            buf.put(`"""`);
            pos += 3; col += 3;
            bool closed = false;
            while (pos < src.length)
            {
                if (pos + 2 < src.length && src[pos] == '"' && src[pos+1] == '"' && src[pos+2] == '"')
                {
                    buf.put(`"""`); pos += 3; col += 3;
                    closed = true;
                    break;
                }
                if (src[pos] == '\n') { buf.put('\n'); line++; col = 1; pos++; }
                else { buf.put(src[pos]); col++; pos++; }
            }
            if (!closed)
                throw new LexError(format("Unterminated triple-quoted string at %d:%d", startLine, startCol));
            return buf.data;
        }

        // Regular string — opening '"' is at pos
        buf.put('"');
        pos++; col++; // consume opening "
        bool closed = false;
        while (pos < src.length)
        {
            char c = src[pos];
            if (c == '"') { buf.put('"'); pos++; col++; closed = true; break; }
            if (c == '\\')
            {
                if (pos + 1 < src.length)
                { buf.put(src[pos .. pos+2]); pos += 2; col += 2; }
                else { pos++; col++; }
                continue;
            }
            if (c == '%' && pos+1 < src.length && src[pos+1] == '(')
            {
                buf.put("%("); pos += 2; col += 2;
                int depth = 1;
                while (pos < src.length && depth > 0)
                {
                    char ic = src[pos];
                    if (ic == '(')      { depth++; buf.put('('); pos++; col++; }
                    else if (ic == ')') { depth--; buf.put(')'); pos++; col++; }
                    else if (ic == '"') { buf.put(scanString()); } // nested string
                    else if (ic == '\n'){ buf.put('\n'); line++; col = 1; pos++; }
                    else                { buf.put(ic); pos++; col++; }
                }
                continue;
            }
            if (c == '\n') { buf.put('\n'); line++; col = 1; pos++; }
            else { buf.put(c); pos++; col++; }
        }
        if (!closed)
            throw new LexError(format("Unterminated string at %d:%d", startLine, startCol));
        return buf.data;
    }

    while (pos < src.length)
    {
        int l = line, c = col;
        char ch = src[pos];

        // newline
        if (ch == '\n')
        {
            emitNewlineIfSignificant();
            pos++; line++; col = 1;
            continue;
        }
        // other whitespace (semicolons treated as optional statement terminators, stripped)
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == ';')
        {
            pos++; col++;
            continue;
        }
        // line comment
        if (pos + 1 < src.length && src[pos] == '/' && src[pos+1] == '/')
        {
            while (pos < src.length && src[pos] != '\n') { pos++; col++; }
            continue;
        }
        // block comment (nestable)
        if (pos + 1 < src.length && src[pos] == '/' && src[pos+1] == '*')
        {
            pos += 2; col += 2;
            int depth = 1;
            while (pos < src.length && depth > 0)
            {
                if (pos + 1 < src.length && src[pos] == '/' && src[pos+1] == '*')
                { depth++; pos += 2; col += 2; }
                else if (pos + 1 < src.length && src[pos] == '*' && src[pos+1] == '/')
                { depth--; pos += 2; col += 2; }
                else
                {
                    if (src[pos] == '\n') { line++; col = 1; } else col++;
                    pos++;
                }
            }
            if (depth != 0)
                throw new LexError(format("Unterminated block comment at %d:%d", l, c));
            continue;
        }
        // string (including triple-quoted)
        if (ch == '"')
        {
            string raw = scanString();
            emit(Tok.string_, raw, l, c);
            continue;
        }
        // number
        if (ch.isDigit)
        {
            int start = pos;
            if (ch == '0' && pos+1 < src.length && (src[pos+1] == 'x' || src[pos+1] == 'X'))
            {
                pos += 2; col += 2;
                while (pos < src.length && src[pos].isHexDigit) { pos++; col++; }
            }
            else
            {
                while (pos < src.length && src[pos].isDigit) { pos++; col++; }
                if (pos < src.length && src[pos] == '.' &&
                    !(pos + 1 < src.length && src[pos + 1] == '.'))
                {
                    pos++; col++;
                    while (pos < src.length && src[pos].isDigit) { pos++; col++; }
                }
                if (pos < src.length && (src[pos] == 'e' || src[pos] == 'E'))
                {
                    pos++; col++;
                    if (pos < src.length && (src[pos] == '+' || src[pos] == '-')) { pos++; col++; }
                    while (pos < src.length && src[pos].isDigit) { pos++; col++; }
                }
            }
            emit(Tok.number, src[start .. pos], l, c);
            continue;
        }
        // identifier or keyword
        if (ch.isAlpha || ch == '_')
        {
            int start = pos;
            while (pos < src.length && (src[pos].isAlphaNum || src[pos] == '_')) { pos++; col++; }
            string word = src[start .. pos];
            Tok k = keyword(word);
            emit(k, word, l, c);
            continue;
        }
        // operators and punctuation
        pos++; col++;
        switch (ch)
        {
            case '+': emit(Tok.plus,    "+",  l, c); break;
            case '-': emit(Tok.minus,   "-",  l, c); break;
            case '*': emit(Tok.star,    "*",  l, c); break;
            case '/': emit(Tok.slash,   "/",  l, c); break;
            case '%': emit(Tok.percent, "%",  l, c); break;
            case '~': emit(Tok.tilde,   "~",  l, c); break;
            case '^': emit(Tok.caret,   "^",  l, c); break;
            case '$': emit(Tok.dollar,  "$",  l, c); break;
            case '?': emit(Tok.question,"?",  l, c); break;
            case ':': emit(Tok.colon,   ":",  l, c); break;
            case ',': emit(Tok.comma,   ",",  l, c); break;
            case '(': emit(Tok.lparen,  "(",  l, c); break;
            case ')': emit(Tok.rparen,  ")",  l, c); break;
            case '[': emit(Tok.lbracket,"[",  l, c); break;
            case ']': emit(Tok.rbracket,"]",  l, c); break;
            case '{': emit(Tok.lbrace,  "{",  l, c); break;
            case '}': emit(Tok.rbrace,  "}",  l, c); break;
            case '=':
                if (pos < src.length && src[pos] == '=') { pos++; col++; emit(Tok.eqEq,   "==", l, c); }
                else emit(Tok.eq, "=", l, c);
                break;
            case '!':
                if (pos < src.length && src[pos] == '=') { pos++; col++; emit(Tok.bangEq, "!=", l, c); }
                else emit(Tok.bang, "!", l, c);
                break;
            case '<':
                if (pos < src.length && src[pos] == '=') { pos++; col++; emit(Tok.ltEq,   "<=", l, c); }
                else if (pos < src.length && src[pos] == '<') { pos++; col++; emit(Tok.ltLt, "<<", l, c); }
                else emit(Tok.lt, "<", l, c);
                break;
            case '>':
                if (pos < src.length && src[pos] == '=') { pos++; col++; emit(Tok.gtEq,   ">=", l, c); }
                else if (pos < src.length && src[pos] == '>') { pos++; col++; emit(Tok.gtGt, ">>", l, c); }
                else emit(Tok.gt, ">", l, c);
                break;
            case '&':
                if (pos < src.length && src[pos] == '&') { pos++; col++; emit(Tok.ampAmp, "&&", l, c); }
                else emit(Tok.amp, "&", l, c);
                break;
            case '|':
                if (pos < src.length && src[pos] == '|') { pos++; col++; emit(Tok.pipePipe,"||", l, c); }
                else emit(Tok.pipe, "|", l, c);
                break;
            case '.':
                if (pos + 1 < src.length && src[pos] == '.' && src[pos+1] == '.')
                { pos += 2; col += 2; emit(Tok.dotDotDot, "...", l, c); }
                else if (pos < src.length && src[pos] == '.')
                { pos++; col++; emit(Tok.dotDot, "..", l, c); }
                else emit(Tok.dot, ".", l, c);
                break;
            default:
                throw new LexError(
                    format("Unexpected character '%s' at %d:%d", ch, l, c));
        }
    }
    // trailing newline if last token can end a statement
    emitNewlineIfSignificant();
    emit(Tok.eof, "", line, col);
    return out_;
}

private Tok keyword(string w) pure nothrow
{
    switch (w)
    {
        case "as":        return Tok.kwAs;
        case "break":     return Tok.kwBreak;
        case "class":     return Tok.kwClass;
        case "construct": return Tok.kwConstruct;
        case "continue":  return Tok.kwContinue;
        case "else":      return Tok.kwElse;
        case "false":     return Tok.kwFalse;
        case "for":       return Tok.kwFor;
        case "foreign":   return Tok.kwForeign;
        case "if":        return Tok.kwIf;
        case "import":    return Tok.kwImport;
        case "in":        return Tok.kwIn;
        case "is":        return Tok.kwIs;
        case "null":      return Tok.kwNull;
        case "return":    return Tok.kwReturn;
        case "static":    return Tok.kwStatic;
        case "super":     return Tok.kwSuper;
        case "this":      return Tok.kwThis;
        case "true":      return Tok.kwTrue;
        case "var":       return Tok.kwVar;
        case "while":     return Tok.kwWhile;
        default:          return Tok.ident;
    }
}

unittest
{
    // basic tokens
    auto t = tokenize("var x = 42");
    assert(t[0].kind == Tok.kwVar);
    assert(t[1].kind == Tok.ident && t[1].text == "x");
    assert(t[2].kind == Tok.eq);
    assert(t[3].kind == Tok.number && t[3].text == "42");
    assert(t[4].kind == Tok.newline);
    assert(t[5].kind == Tok.eof);
}

unittest
{
    // line comment stripped
    auto t = tokenize("// hello\nvar x");
    assert(t[0].kind == Tok.kwVar, "line comment should be stripped");
    assert(t[1].kind == Tok.ident && t[1].text == "x");

    // nested block comment
    auto t2 = tokenize("/* /* inner */ outer */var x");
    assert(t2[0].kind == Tok.kwVar, "nested block comment should be stripped");

    // newline NOT emitted after operator
    auto t3 = tokenize("a +\nb");
    assert(t3[0].kind == Tok.ident);
    assert(t3[1].kind == Tok.plus);
    assert(t3[2].kind == Tok.ident);   // b — no newline between + and b
    assert(t3[3].kind == Tok.newline); // significant after b

    // newline emitted after closing paren
    auto t4 = tokenize("foo()\nbar");
    assert(t4[0].kind == Tok.ident);
    assert(t4[1].kind == Tok.lparen);
    assert(t4[2].kind == Tok.rparen);
    assert(t4[3].kind == Tok.newline); // ) can end a statement
    assert(t4[4].kind == Tok.ident);

    // hex literal
    auto t5 = tokenize("0xcafe");
    assert(t5[0].kind == Tok.number && t5[0].text == "0xcafe");

    // float with exponent
    auto t6 = tokenize("3.14e2");
    assert(t6[0].kind == Tok.number && t6[0].text == "3.14e2");

    // string with interpolation is opaque
    auto t7 = tokenize(`"hello %(name)!"`);
    assert(t7[0].kind == Tok.string_);
    assert(t7[0].text == `"hello %(name)!"`);
}
