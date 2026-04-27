module parser;

import lexer, ast;
import std.format : format;

class ParseError : Exception
{
    this(string msg, string file = __FILE__, size_t ln = __LINE__)
    { super(msg, file, ln); }
}

private struct Parser
{
    Token[] toks;
    int     pos;

    @property Token cur() { return toks[pos]; }

    Token consume() { return toks[pos++]; }

    Token expect(Tok k)
    {
        if (cur.kind != k)
            throw new ParseError(
                format("Expected %s got '%s' at %d:%d", k, cur.text, cur.line, cur.col));
        return consume();
    }

    void skipNewlines() { while (cur.kind == Tok.newline) consume(); }
    void consumeNewline() { if (cur.kind == Tok.newline) consume(); }
}

WrenModule parseModule(Token[] tokens)
{
    auto p   = Parser(tokens, 0);
    auto mod = new WrenModule();
    while (p.cur.kind != Tok.eof)
    {
        p.skipNewlines();
        if (p.cur.kind == Tok.eof) break;
        mod.items ~= parseTopLevel(p);
    }
    return mod;
}

private Node parseTopLevel(ref Parser p)
{
    switch (p.cur.kind) with (Tok)
    {
        case kwImport:  return parseImport(p);
        case kwClass:   return parseClass(p);
        case kwForeign:
            p.consume();
            auto cd = parseClass(p);
            cd.isForeign = true;
            return cd;
        default:        return parseStatement(p);
    }
}

private ImportDecl parseImport(ref Parser p)
{
    p.expect(Tok.kwImport);
    auto d = new ImportDecl();
    d.path = p.expect(Tok.string_).text;
    if (p.cur.kind == Tok.kwFor)
    {
        p.consume();
        while (true)
        {
            string name   = p.expect(Tok.ident).text;
            string alias_ = "";
            if (p.cur.kind == Tok.kwAs) { p.consume(); alias_ = p.expect(Tok.ident).text; }
            d.names   ~= name;
            d.aliases ~= alias_;
            if (p.cur.kind != Tok.comma) break;
            p.consume();
        }
    }
    p.consumeNewline();
    return d;
}

private ClassDecl parseClass(ref Parser p)
{
    p.expect(Tok.kwClass);
    auto d = new ClassDecl();
    d.name = p.expect(Tok.ident).text;
    if (p.cur.kind == Tok.kwIs) { p.consume(); d.superclass = p.expect(Tok.ident).text; }
    p.expect(Tok.lbrace);
    p.skipNewlines();
    while (p.cur.kind != Tok.rbrace && p.cur.kind != Tok.eof)
    {
        d.methods ~= parseMethod(p);
        p.skipNewlines();
    }
    p.expect(Tok.rbrace);
    p.consumeNewline();
    return d;
}

private MethodDecl parseMethod(ref Parser p)
{
    auto m = new MethodDecl();

    bool isForeign = (p.cur.kind == Tok.kwForeign);
    if (isForeign) p.consume();

    bool isStatic = (p.cur.kind == Tok.kwStatic);
    if (isStatic) p.consume();

    // construct
    if (p.cur.kind == Tok.kwConstruct)
    {
        p.consume();
        m.kind   = MethodKind.construct;
        m.name   = p.expect(Tok.ident).text;
        m.params = parseParamList(p);
        if (!isForeign) m.body = parseBlock(p); else p.consumeNewline();
        return m;
    }

    // subscript operator
    if (p.cur.kind == Tok.lbracket)
    {
        p.consume();
        while (p.cur.kind != Tok.rbracket && p.cur.kind != Tok.eof)
        {
            m.params ~= p.expect(Tok.ident).text;
            if (p.cur.kind == Tok.comma) p.consume();
        }
        p.expect(Tok.rbracket);
        if (p.cur.kind == Tok.eq)
        {
            p.consume();
            m.kind = MethodKind.subscriptSetter;
            p.expect(Tok.lparen);
            m.params ~= p.expect(Tok.ident).text;
            p.expect(Tok.rparen);
        }
        else m.kind = MethodKind.subscript;
        if (!isForeign) m.body = parseBlock(p); else p.consumeNewline();
        return m;
    }

    // operator overload methods (-, !, ~, +, *, /, %, <, >, <=, >=, ==, !=, &, |, ^, <<, >>)
    static immutable Tok[] opToks = [
        Tok.minus, Tok.bang, Tok.tilde, Tok.plus, Tok.star, Tok.slash,
        Tok.percent, Tok.lt, Tok.gt, Tok.ltEq, Tok.gtEq, Tok.eqEq,
        Tok.bangEq, Tok.amp, Tok.pipe, Tok.caret, Tok.ltLt, Tok.gtGt
    ];
    bool isOp = false;
    foreach (ot; opToks) if (p.cur.kind == ot) { isOp = true; break; }
    if (isOp)
    {
        m.kind = MethodKind.op;
        m.name = p.consume().text;
        if (p.cur.kind == Tok.lparen) m.params = parseParamList(p);
        if (!isForeign) m.body = parseBlock(p); else p.consumeNewline();
        return m;
    }

    // named method
    m.name = p.expect(Tok.ident).text;

    // setter: name=(value) { }
    if (p.cur.kind == Tok.eq)
    {
        p.consume();
        m.kind   = MethodKind.setter;
        m.params = parseParamList(p);
        if (!isForeign) m.body = parseBlock(p); else p.consumeNewline();
        return m;
    }

    if (p.cur.kind == Tok.lparen)
    {
        m.kind   = isForeign ? (isStatic ? MethodKind.foreignStatic : MethodKind.foreign_)
                             : (isStatic ? MethodKind.static_        : MethodKind.normal);
        m.params = parseParamList(p);
    }
    else
    {
        m.kind = isForeign ? (isStatic ? MethodKind.foreignStaticGetter : MethodKind.foreignGetter)
                           : (isStatic ? MethodKind.staticGetter         : MethodKind.getter);
    }

    if (!isForeign) m.body = parseBlock(p); else p.consumeNewline();
    return m;
}

private string[] parseParamList(ref Parser p)
{
    p.expect(Tok.lparen);
    string[] params;
    p.skipNewlines();
    while (p.cur.kind != Tok.rparen && p.cur.kind != Tok.eof)
    {
        params ~= p.expect(Tok.ident).text;
        p.skipNewlines();
        if (p.cur.kind == Tok.comma) { p.consume(); p.skipNewlines(); }
    }
    p.expect(Tok.rparen);
    return params;
}

// ── Statements ────────────────────────────────────────────────────────────────

private Node parseStatement(ref Parser p)
{
    p.skipNewlines();
    switch (p.cur.kind) with (Tok)
    {
        case kwVar:      return parseVarDecl(p);
        case kwImport:   return parseImport(p);
        case kwIf:       return parseIf(p);
        case kwWhile:    return parseWhile(p);
        case kwFor:      return parseFor(p);
        case kwReturn:   return parseReturn(p);
        case kwBreak:    p.consume(); p.consumeNewline(); return new BreakStmt();
        case kwContinue: p.consume(); p.consumeNewline(); return new ContinueStmt();
        case lbrace:     return parseBlock(p);
        default:         return parseExprStmt(p);
    }
}

private VarDecl parseVarDecl(ref Parser p)
{
    p.expect(Tok.kwVar);
    auto d = new VarDecl();
    d.name = p.expect(Tok.ident).text;
    if (p.cur.kind == Tok.eq) { p.consume(); d.init = parseExpr(p); }
    p.consumeNewline();
    return d;
}

private BlockStmt parseBlock(ref Parser p)
{
    p.expect(Tok.lbrace);
    auto b = new BlockStmt();
    p.skipNewlines();
    while (p.cur.kind != Tok.rbrace && p.cur.kind != Tok.eof)
    {
        b.stmts ~= parseStatement(p);
        p.skipNewlines();
    }
    p.expect(Tok.rbrace);
    p.consumeNewline();
    return b;
}

private IfStmt parseIf(ref Parser p)
{
    p.expect(Tok.kwIf);
    p.expect(Tok.lparen);
    auto s  = new IfStmt();
    s.cond  = parseExpr(p);
    p.expect(Tok.rparen);
    s.then_ = parseStatement(p);
    p.skipNewlines();
    if (p.cur.kind == Tok.kwElse) { p.consume(); s.else_ = parseStatement(p); }
    return s;
}

private WhileStmt parseWhile(ref Parser p)
{
    p.expect(Tok.kwWhile);
    p.expect(Tok.lparen);
    auto s = new WhileStmt();
    s.cond = parseExpr(p);
    p.expect(Tok.rparen);
    s.body = parseStatement(p);
    return s;
}

private ForStmt parseFor(ref Parser p)
{
    p.expect(Tok.kwFor);
    p.expect(Tok.lparen);
    auto s    = new ForStmt();
    s.loopVar = p.expect(Tok.ident).text;
    p.expect(Tok.kwIn);
    s.seq     = parseExpr(p);
    p.expect(Tok.rparen);
    s.body    = parseStatement(p);
    return s;
}

private ReturnStmt parseReturn(ref Parser p)
{
    p.expect(Tok.kwReturn);
    auto s = new ReturnStmt();
    if (p.cur.kind != Tok.newline && p.cur.kind != Tok.rbrace && p.cur.kind != Tok.eof)
        s.value = parseExpr(p);
    p.consumeNewline();
    return s;
}

private ExprStmt parseExprStmt(ref Parser p)
{
    auto s = new ExprStmt();
    s.expr = parseExpr(p);
    p.consumeNewline();
    return s;
}

// ── Expressions (Pratt precedence climbing) ───────────────────────────────────

private int infixBP(Tok t) pure nothrow
{
    switch (t) with (Tok)
    {
        case eq:                     return  1;
        case question:               return  2;
        case pipePipe:               return  3;
        case ampAmp:                 return  4;
        case eqEq: case bangEq:      return  5;
        case kwIs:                   return  6;
        case lt: case gt:
        case ltEq: case gtEq:        return  7;
        case pipe:                   return  8;
        case caret:                  return  9;
        case amp:                    return 10;
        case ltLt: case gtGt:        return 11;
        case dotDot: case dotDotDot: return 12;
        case plus: case minus:       return 13;
        case star: case slash:
        case percent:                return 14;
        case dot: case lparen:
        case lbracket:               return 16;
        default:                     return  0;
    }
}

private Expr parseExpr(ref Parser p, int minBP = 0)
{
    Expr lhs = parsePrefix(p);

    while (true)
    {
        int bp = infixBP(p.cur.kind);
        if (bp <= minBP) break;

        Token op = p.consume();

        if (op.kind == Tok.eq)
        {
            auto id = cast(IdentExpr) lhs;
            if (id is null)
                throw new ParseError(format("Invalid assignment target at %d:%d", op.line, op.col));
            auto a  = new AssignExpr();
            a.name  = id.name;
            a.value = parseExpr(p, bp - 1); // right-assoc
            lhs = a; continue;
        }

        if (op.kind == Tok.question)
        {
            auto t  = new TernaryExpr();
            t.cond  = lhs;
            t.then_ = parseExpr(p, 0);
            p.expect(Tok.colon);
            t.else_ = parseExpr(p, bp - 1);
            lhs = t; continue;
        }

        if (op.kind == Tok.kwIs)
        {
            auto b  = new BinaryExpr();
            b.op    = "is"; b.left = lhs; b.right = parseExpr(p, bp);
            lhs = b; continue;
        }

        if (op.kind == Tok.dotDot || op.kind == Tok.dotDotDot)
        {
            auto r      = new RangeExpr();
            r.from      = lhs;
            r.inclusive = (op.kind == Tok.dotDot);
            r.to        = parseExpr(p, bp);
            lhs = r; continue;
        }

        if (op.kind == Tok.dot)
        {
            string mname = p.expect(Tok.ident).text;
            if (p.cur.kind == Tok.eq)
            {
                p.consume();
                auto se     = new SetterExpr();
                se.receiver = lhs; se.field = mname;
                se.value    = parseExpr(p, 0);
                lhs = se; continue;
            }
            auto call     = new CallExpr();
            call.receiver = lhs;
            call.method_  = mname;
            if (p.cur.kind == Tok.lparen) { call.hasParens = true; call.args = parseArgList(p); }
            if (p.cur.kind == Tok.lbrace) call.args ~= parseBlockExpr(p);
            lhs = call; continue;
        }

        if (op.kind == Tok.lbracket)
        {
            Expr[] idx;
            p.skipNewlines();
            while (p.cur.kind != Tok.rbracket && p.cur.kind != Tok.eof)
            {
                idx ~= parseExpr(p, 0);
                p.skipNewlines();
                if (p.cur.kind == Tok.comma) { p.consume(); p.skipNewlines(); }
            }
            p.expect(Tok.rbracket);
            if (p.cur.kind == Tok.eq)
            {
                p.consume();
                auto sa = new SubscriptAssignExpr();
                sa.receiver = lhs; sa.indices = idx; sa.value = parseExpr(p, 0);
                lhs = sa;
            }
            else
            {
                auto sub = new SubscriptExpr();
                sub.receiver = lhs; sub.indices = idx;
                lhs = sub;
            }
            continue;
        }

        if (op.kind == Tok.lparen)
        {
            // bare call: foo(...) — lhs must be IdentExpr
            auto id = cast(IdentExpr) lhs;
            if (id is null)
                throw new ParseError(format("Unexpected '(' at %d:%d", op.line, op.col));
            p.pos--; // un-consume
            auto call     = new CallExpr();
            call.receiver = null;
            call.method_  = id.name;
            call.hasParens = true;
            call.args      = parseArgList(p);
            if (p.cur.kind == Tok.lbrace) call.args ~= parseBlockExpr(p);
            lhs = call; continue;
        }

        // regular binary
        auto b = new BinaryExpr();
        b.op = op.text; b.left = lhs; b.right = parseExpr(p, bp);
        lhs = b;
    }
    return lhs;
}

private Expr parsePrefix(ref Parser p)
{
    Token t = p.cur;

    if (t.kind == Tok.minus || t.kind == Tok.bang || t.kind == Tok.tilde || t.kind == Tok.dollar)
    {
        p.consume();
        auto u = new UnaryExpr();
        u.op = t.text; u.operand = parseExpr(p, 15);
        return u;
    }

    if (t.kind == Tok.lparen)
    {
        p.consume(); p.skipNewlines();
        Expr e = parseExpr(p, 0);
        p.skipNewlines(); p.expect(Tok.rparen);
        return e;
    }

    if (t.kind == Tok.lbracket)
    {
        p.consume();
        auto l = new ListExpr();
        p.skipNewlines();
        while (p.cur.kind != Tok.rbracket && p.cur.kind != Tok.eof)
        {
            l.elements ~= parseExpr(p, 0);
            p.skipNewlines();
            if (p.cur.kind == Tok.comma) { p.consume(); p.skipNewlines(); }
        }
        p.expect(Tok.rbracket);
        return l;
    }

    // { ... } — map literal or block/closure
    if (t.kind == Tok.lbrace)
    {
        int savedPos = p.pos;
        p.consume(); p.skipNewlines();

        // empty braces → empty block expression
        if (p.cur.kind == Tok.rbrace)
        {
            p.consume();
            auto be = new BlockExpr(); be.body = new BlockStmt();
            return be;
        }
        // pipe → closure with params
        if (p.cur.kind == Tok.pipe) { p.pos = savedPos; return parseBlockExpr(p); }

        // speculatively parse first expression; if followed by ':' it's a map
        int beforeFirst = p.pos;
        try
        {
            Expr firstKey = parseExpr(p, 0);
            p.skipNewlines();
            if (p.cur.kind == Tok.colon)
            {
                auto m = new MapExpr();
                p.consume(); p.skipNewlines();
                m.keys   ~= firstKey;
                m.values ~= parseExpr(p, 0);
                p.skipNewlines();
                while (p.cur.kind == Tok.comma)
                {
                    p.consume(); p.skipNewlines();
                    if (p.cur.kind == Tok.rbrace) break;
                    m.keys   ~= parseExpr(p, 0); p.skipNewlines();
                    p.expect(Tok.colon);          p.skipNewlines();
                    m.values ~= parseExpr(p, 0); p.skipNewlines();
                }
                p.expect(Tok.rbrace);
                return m;
            }
            // not a map — backtrack and parse as block
            p.pos = savedPos;
            return parseBlockExpr(p);
        }
        catch (ParseError)
        {
            p.pos = savedPos;
            return parseBlockExpr(p);
        }
    }

    if (t.kind == Tok.kwSuper)
    {
        p.consume();
        auto s = new SuperExpr();
        if (p.cur.kind == Tok.dot) { p.consume(); s.method_ = p.expect(Tok.ident).text; }
        if (p.cur.kind == Tok.lparen) s.args = parseArgList(p);
        return s;
    }

    if (t.kind == Tok.kwThis) { p.consume(); return new ThisExpr(); }

    p.consume();
    switch (t.kind) with (Tok)
    {
        case number:
        {
            auto e = new LiteralExpr();
            e.kind = LiteralExpr.Kind.number; e.raw = t.text; return e;
        }
        case string_:
        {
            auto e = new LiteralExpr();
            e.kind = LiteralExpr.Kind.string_; e.raw = t.text; return e;
        }
        case kwTrue:
        {
            auto e = new LiteralExpr();
            e.kind = LiteralExpr.Kind.bool_; e.boolVal = true; e.raw = "true"; return e;
        }
        case kwFalse:
        {
            auto e = new LiteralExpr();
            e.kind = LiteralExpr.Kind.bool_; e.boolVal = false; e.raw = "false"; return e;
        }
        case kwNull:
        {
            auto e = new LiteralExpr();
            e.kind = LiteralExpr.Kind.null_; e.raw = "null"; return e;
        }
        case ident:
        {
            auto id = new IdentExpr(); id.name = t.text;
            // implicit-this call with trailing block: foo { }
            if (p.cur.kind == Tok.lbrace)
            {
                auto call     = new CallExpr();
                call.receiver = null; call.method_ = id.name;
                call.args    ~= parseBlockExpr(p);
                return call;
            }
            return id;
        }
        default:
            throw new ParseError(format("Unexpected token '%s' at %d:%d", t.text, t.line, t.col));
    }
}

private Expr[] parseArgList(ref Parser p)
{
    p.expect(Tok.lparen);
    Expr[] args;
    p.skipNewlines();
    while (p.cur.kind != Tok.rparen && p.cur.kind != Tok.eof)
    {
        args ~= parseExpr(p, 0);
        p.skipNewlines();
        if (p.cur.kind == Tok.comma) { p.consume(); p.skipNewlines(); }
    }
    p.expect(Tok.rparen);
    return args;
}

private BlockExpr parseBlockExpr(ref Parser p)
{
    p.expect(Tok.lbrace);
    auto b = new BlockExpr();
    p.skipNewlines();
    if (p.cur.kind == Tok.pipe)
    {
        p.consume();
        while (p.cur.kind != Tok.pipe && p.cur.kind != Tok.eof)
        {
            b.params ~= p.expect(Tok.ident).text;
            if (p.cur.kind == Tok.comma) p.consume();
        }
        p.expect(Tok.pipe);
        p.skipNewlines();
    }
    auto body_ = new BlockStmt();
    while (p.cur.kind != Tok.rbrace && p.cur.kind != Tok.eof)
    {
        body_.stmts ~= parseStatement(p);
        p.skipNewlines();
    }
    p.expect(Tok.rbrace);
    b.body = body_;
    return b;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

unittest
{
    // Task 5: module and class level
    auto mod = parseModule(tokenize("class Foo {}"));
    assert(mod.items.length == 1);
    auto cd = cast(ClassDecl) mod.items[0];
    assert(cd !is null && cd.name == "Foo" && cd.superclass == "");

    auto mod2 = parseModule(tokenize("class Bar is Foo {}"));
    assert((cast(ClassDecl) mod2.items[0]).superclass == "Foo");

    auto mod3 = parseModule(tokenize("class A {\n  value { 1\n}\n}"));
    auto cd3  = cast(ClassDecl) mod3.items[0];
    assert(cd3.methods.length == 1);
    assert(cd3.methods[0].kind == MethodKind.getter);
    assert(cd3.methods[0].name == "value");

    auto mod4 = parseModule(tokenize(`import "io"`));
    auto imp  = cast(ImportDecl) mod4.items[0];
    assert(imp !is null && imp.path == `"io"`);
}

unittest
{
    // Task 6: statements
    auto mod = parseModule(tokenize("var x = 42"));
    auto vd  = cast(VarDecl) mod.items[0];
    assert(vd !is null && vd.name == "x");
    auto lit = cast(LiteralExpr) vd.init;
    assert(lit !is null && lit.raw == "42");

    assert(cast(IfStmt)    parseModule(tokenize("if (true) { x = 1\n}")).items[0] !is null);
    assert(cast(WhileStmt) parseModule(tokenize("while (true) {\n  break\n}")).items[0] !is null);
    assert(cast(ForStmt)   parseModule(tokenize("for (x in list) {\n  continue\n}")).items[0] !is null);

    auto mod5 = parseModule(tokenize("class A {\n  f { return 1\n}\n}"));
    auto ret  = cast(ReturnStmt)(cast(ClassDecl) mod5.items[0]).methods[0].body.stmts[0];
    assert(ret !is null);
}

unittest
{
    // Task 7: expressions
    auto mod = parseModule(tokenize("var x = 1 + 2 * 3"));
    auto bin = cast(BinaryExpr)(cast(VarDecl) mod.items[0]).init;
    assert(bin !is null && bin.op == "+");
    assert((cast(BinaryExpr) bin.right).op == "*");

    auto mod2  = parseModule(tokenize(`System.print("hi")`));
    auto call  = cast(CallExpr)(cast(ExprStmt) mod2.items[0]).expr;
    assert(call !is null);
    assert((cast(IdentExpr) call.receiver).name == "System");
    assert(call.method_ == "print");
    assert(call.args.length == 1);

    auto mod3 = parseModule(tokenize("var x = a ? 1 : 2"));
    assert(cast(TernaryExpr)(cast(VarDecl) mod3.items[0]).init !is null);

    auto mod4 = parseModule(tokenize("var r = 1..10"));
    auto rng  = cast(RangeExpr)(cast(VarDecl) mod4.items[0]).init;
    assert(rng !is null && rng.inclusive);

    auto mod5  = parseModule(tokenize("list.each {|x|\n  f(x)\n}"));
    auto call2 = cast(CallExpr)(cast(ExprStmt) mod5.items[0]).expr;
    assert(call2 !is null && call2.method_ == "each");
    assert(call2.args.length == 1);
    assert(cast(BlockExpr) call2.args[0] !is null);
}
