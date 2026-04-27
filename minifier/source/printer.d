module printer;

import ast;
import std.array : Appender;

string printModule(WrenModule mod)
{
    Appender!string buf;
    bool first = true;
    foreach (item; mod.items)
    {
        if (!first) buf.put('\n');
        first = false;
        printNode(buf, item);
    }
    return buf.data;
}

private void printNode(ref Appender!string buf, Node n)
{
    if (auto cd  = cast(ClassDecl)  n) { printClass(buf, cd);   return; }
    if (auto imp = cast(ImportDecl) n) { printImport(buf, imp); return; }
    if (auto vd  = cast(VarDecl)    n) { printVarDecl(buf, vd); return; }
    if (auto es  = cast(ExprStmt)   n) { printExpr(buf, es.expr); return; }
    printStmt(buf, n);
}

private void printClass(ref Appender!string buf, ClassDecl cd)
{
    if (cd.isForeign) buf.put("foreign ");
    buf.put("class "); buf.put(cd.name);
    if (cd.superclass.length) { buf.put(" is "); buf.put(cd.superclass); }
    buf.put('{');
    foreach (m; cd.methods) { buf.put('\n'); printMethod(buf, m); }
    buf.put('\n'); buf.put('}');
}

private void printImport(ref Appender!string buf, ImportDecl d)
{
    buf.put("import "); buf.put(d.path);
    if (d.names.length)
    {
        buf.put(" for ");
        foreach (i, name; d.names)
        {
            if (i) buf.put(',');
            buf.put(name);
            if (d.aliases[i].length) { buf.put(" as "); buf.put(d.aliases[i]); }
        }
    }
}

private void printMethod(ref Appender!string buf, MethodDecl m)
{
    final switch (m.kind) with (MethodKind)
    {
        case foreign_:
            buf.put("foreign "); buf.put(m.name);
            printParams(buf, m.params); return;
        case foreignStatic:
            buf.put("foreign static "); buf.put(m.name);
            printParams(buf, m.params); return;
        case foreignGetter:
            buf.put("foreign "); buf.put(m.name); return;
        case foreignStaticGetter:
            buf.put("foreign static "); buf.put(m.name); return;
        case construct:
            buf.put("construct "); buf.put(m.name);
            printParams(buf, m.params);
            printBlock(buf, m.body); return;
        case static_:
            buf.put("static "); buf.put(m.name);
            printParams(buf, m.params);
            printBlock(buf, m.body); return;
        case staticGetter:
            buf.put("static "); buf.put(m.name);
            printBlock(buf, m.body); return;
        case getter:
            buf.put(m.name);
            printBlock(buf, m.body); return;
        case setter:
            buf.put(m.name); buf.put('=');
            printParams(buf, m.params);
            printBlock(buf, m.body); return;
        case op:
            buf.put(m.name);
            if (m.params.length) printParams(buf, m.params);
            printBlock(buf, m.body); return;
        case subscript:
            buf.put('['); printCommaSep(buf, m.params); buf.put(']');
            printBlock(buf, m.body); return;
        case subscriptSetter:
            buf.put('[');
            foreach (i, p; m.params[0..$-1]) { if (i) buf.put(','); buf.put(p); }
            buf.put("]="); buf.put('('); buf.put(m.params[$-1]); buf.put(')');
            printBlock(buf, m.body); return;
        case normal:
            buf.put(m.name);
            printParams(buf, m.params);
            printBlock(buf, m.body); return;
    }
}

private void printParams(ref Appender!string buf, string[] params)
{
    buf.put('('); printCommaSep(buf, params); buf.put(')');
}

private void printCommaSep(ref Appender!string buf, string[] items)
{
    foreach (i, s; items) { if (i) buf.put(','); buf.put(s); }
}

private void printBlock(ref Appender!string buf, BlockStmt b)
{
    buf.put('{');
    foreach (s; b.stmts) { buf.put('\n'); printStmt(buf, s); }
    buf.put('\n'); buf.put('}');
}

private void printStmt(ref Appender!string buf, Node s)
{
    if (auto vd  = cast(VarDecl)    s) { printVarDecl(buf, vd); return; }
    if (auto es  = cast(ExprStmt)   s) { printExpr(buf, es.expr); return; }
    if (auto rs  = cast(ReturnStmt) s)
    {
        buf.put("return");
        if (rs.value !is null) { buf.put(' '); printExpr(buf, rs.value); }
        return;
    }
    if (cast(BreakStmt)    s) { buf.put("break");    return; }
    if (cast(ContinueStmt) s) { buf.put("continue"); return; }
    if (auto ifs = cast(IfStmt)    s) { printIf(buf, ifs);   return; }
    if (auto ws  = cast(WhileStmt) s) { printWhile(buf, ws); return; }
    if (auto fs  = cast(ForStmt)   s) { printFor(buf, fs);   return; }
    if (auto blk = cast(BlockStmt) s) { printBlock(buf, blk); return; }
}

private void printVarDecl(ref Appender!string buf, VarDecl vd)
{
    buf.put("var "); buf.put(vd.name); buf.put('=');
    printExpr(buf, vd.init);
}

private void printIf(ref Appender!string buf, IfStmt s)
{
    buf.put("if("); printExpr(buf, s.cond); buf.put(')');
    printStmt(buf, s.then_);
    if (s.else_ !is null) { buf.put("else "); printStmt(buf, s.else_); }
}

private void printWhile(ref Appender!string buf, WhileStmt s)
{
    buf.put("while("); printExpr(buf, s.cond); buf.put(')');
    printStmt(buf, s.body);
}

private void printFor(ref Appender!string buf, ForStmt s)
{
    buf.put("for("); buf.put(s.loopVar); buf.put(" in ");
    printExpr(buf, s.seq); buf.put(')');
    printStmt(buf, s.body);
}

private int binaryOpBP(string op) pure nothrow
{
    switch (op)
    {
        case "||":              return  3;
        case "&&":              return  4;
        case "==": case "!=":   return  5;
        case "is":              return  6;
        case "<":  case ">":
        case "<=": case ">=":   return  7;
        case "|":               return  8;
        case "^":               return  9;
        case "&":               return 10;
        case "<<": case ">>":   return 11;
        case "..": case "...":  return 12;
        case "+":  case "-":    return 13;
        case "*":  case "/":
        case "%":               return 14;
        default:                return  0;
    }
}

// Returns the binding power of an expression's outermost operator.
// Atoms (literals, calls, etc.) return a high value — they never need parens.
private int exprBP(Expr e) pure nothrow
{
    if (auto b = cast(BinaryExpr)  e) return binaryOpBP(b.op);
    if (cast(TernaryExpr) e !is null) return 2;
    if (cast(AssignExpr)  e !is null) return 1;
    if (cast(RangeExpr)   e !is null) return 12;
    return 100;
}

// Print e as a child of a binary operator with binding power parentBP.
// isRight: true for the right operand (left-assoc means equal bp also needs parens).
private void printOperand(ref Appender!string buf, Expr e, int parentBP, bool isRight)
{
    int bp = exprBP(e);
    bool needsParens = isRight ? (bp <= parentBP) : (bp < parentBP);
    if (needsParens) buf.put('(');
    printExpr(buf, e);
    if (needsParens) buf.put(')');
}

private void printExpr(ref Appender!string buf, Expr e)
{
    if (e is null) return;

    if (auto lit = cast(LiteralExpr) e) { buf.put(lit.raw); return; }
    if (auto id  = cast(IdentExpr)   e) { buf.put(id.name); return; }
    if (cast(ThisExpr) e)               { buf.put("this");  return; }

    if (auto a  = cast(AssignExpr) e)
    { buf.put(a.name); buf.put('='); printExpr(buf, a.value); return; }

    if (auto se = cast(SetterExpr) e)
    {
        printReceiver(buf, se.receiver); buf.put('.'); buf.put(se.field);
        buf.put('='); printExpr(buf, se.value); return;
    }

    if (auto u = cast(UnaryExpr) e)
    { buf.put(u.op); printExpr(buf, u.operand); return; }

    if (auto b = cast(BinaryExpr) e)
    {
        bool wordOp = (b.op == "is");
        int bp = binaryOpBP(b.op);
        printOperand(buf, b.left,  bp, false);
        if (wordOp) buf.put(' ');
        buf.put(b.op);
        if (wordOp) buf.put(' ');
        printOperand(buf, b.right, bp, true);
        return;
    }

    if (auto c = cast(CallExpr) e)
    {
        if (c.receiver !is null) { printReceiver(buf, c.receiver); buf.put('.'); }
        buf.put(c.method_);
        // Last arg may be a block — split regular args from trailing block
        size_t nRegular = c.args.length;
        BlockExpr trailingBlock = null;
        if (nRegular > 0)
        {
            if (auto be = cast(BlockExpr) c.args[$-1])
            { trailingBlock = be; nRegular--; }
        }
        if (c.hasParens || nRegular > 0)
        {
            buf.put('(');
            foreach (i, arg; c.args[0..nRegular]) { if (i) buf.put(','); printExpr(buf, arg); }
            buf.put(')');
        }
        if (trailingBlock !is null) printBlockExpr(buf, trailingBlock);
        return;
    }

    if (auto s = cast(SuperExpr) e)
    {
        buf.put("super");
        if (s.method_.length) { buf.put('.'); buf.put(s.method_); }
        if (s.args.length)
        {
            buf.put('(');
            foreach (i, a; s.args) { if (i) buf.put(','); printExpr(buf, a); }
            buf.put(')');
        }
        return;
    }

    if (auto sub = cast(SubscriptExpr) e)
    {
        printReceiver(buf, sub.receiver); buf.put('[');
        foreach (i, idx; sub.indices) { if (i) buf.put(','); printExpr(buf, idx); }
        buf.put(']'); return;
    }

    if (auto sub = cast(SubscriptAssignExpr) e)
    {
        printReceiver(buf, sub.receiver); buf.put('[');
        foreach (i, idx; sub.indices) { if (i) buf.put(','); printExpr(buf, idx); }
        buf.put("]="); printExpr(buf, sub.value); return;
    }

    if (auto t = cast(TernaryExpr) e)
    { printExpr(buf, t.cond); buf.put('?'); printExpr(buf, t.then_); buf.put(':'); printExpr(buf, t.else_); return; }

    if (auto r = cast(RangeExpr) e)
    { printExpr(buf, r.from); buf.put(r.inclusive ? ".." : "..."); printExpr(buf, r.to); return; }

    if (auto le = cast(ListExpr) e)
    { buf.put('['); foreach (i, el; le.elements) { if (i) buf.put(','); printExpr(buf, el); } buf.put(']'); return; }

    if (auto me = cast(MapExpr) e)
    {
        buf.put('{');
        foreach (i, k; me.keys) { if (i) buf.put(','); printExpr(buf, k); buf.put(':'); printExpr(buf, me.values[i]); }
        buf.put('}'); return;
    }

    if (auto be = cast(BlockExpr) e) { printBlockExpr(buf, be); return; }
}

// Dot has precedence 16; these expression types have lower effective precedence
// and must be parenthesised when used as a receiver to preserve semantics.
private void printReceiver(ref Appender!string buf, Expr e)
{
    bool needsParens = cast(UnaryExpr)   e !is null
                    || cast(BinaryExpr)  e !is null
                    || cast(TernaryExpr) e !is null
                    || cast(AssignExpr)  e !is null;
    if (needsParens) buf.put('(');
    printExpr(buf, e);
    if (needsParens) buf.put(')');
}

private void printBlockExpr(ref Appender!string buf, BlockExpr be)
{
    buf.put('{');
    if (be.params.length) { buf.put('|'); printCommaSep(buf, be.params); buf.put('|'); }
    foreach (s; be.body.stmts) { buf.put('\n'); printStmt(buf, s); }
    buf.put('\n'); buf.put('}');
}

unittest
{
    import lexer, parser, optimizer;
    import std.string    : indexOf;
    import std.algorithm : canFind;

    // basic method round-trip
    string src = "class A {\n  f(x) {\n    return x + 1\n  }\n}";
    auto mod = parseModule(tokenize(src));
    string out_ = printModule(mod);
    assert(out_.indexOf("  ") == -1, "no double-spaces: " ~ out_);
    assert(out_.indexOf("\n\n") == -1, "no blank lines: " ~ out_);

    // full pipeline: constant fold + rename
    string src2 = "class A {\n  f(count) {\n    var n = 10\n    return count + n\n  }\n}";
    auto mod2 = parseModule(tokenize(src2));
    optimizeModule(mod2);
    string out2 = printModule(mod2);
    assert(out2.canFind("a+10") || out2.canFind("a + 10"), out2);
    assert(!out2.canFind("count"),  out2);
    assert(!out2.canFind("var n"),  out2);
}
