module optimizer;

import ast;
import std.conv   : to, ConvException;
import std.format : format;
import std.math   : floor, isInfinity, isNaN;
import std.ascii  : isAlpha, isAlphaNum;

// ── Public entry point ────────────────────────────────────────────────────────

void optimizeModule(WrenModule mod)
{
    foreach (item; mod.items)
        if (auto cd = cast(ClassDecl) item)
        {
            bool[string] methodNames;
            foreach (m; cd.methods) methodNames[m.name] = true;

            foreach (m; cd.methods)
                if (m.body !is null)
                    optimizeBody(m.body, m.params, null, null, methodNames);
        }
}

// ── String-interpolation identifier scanner ───────────────────────────────────
// Variable names used inside %(…) in string literals must not be renamed because
// the literal text is opaque to the renamer.

private void collectInterpIdents(string raw, ref bool[string] result)
{
    size_t i = 0;
    while (i + 1 < raw.length)
    {
        if (raw[i] == '%' && raw[i + 1] == '(')
        {
            i += 2;
            int depth = 1;
            while (i < raw.length && depth > 0)
            {
                char ch = raw[i];
                if      (ch == '(') { depth++; i++; }
                else if (ch == ')') { depth--; i++; }
                else if (isAlpha(ch) || ch == '_')
                {
                    size_t s = i;
                    while (i < raw.length && (isAlphaNum(raw[i]) || raw[i] == '_')) i++;
                    result[raw[s .. i]] = true;
                }
                else i++;
            }
        }
        else i++;
    }
}

private void scanNodeForInterpIdents(Node n, ref bool[string] result)
{
    if (n is null) return;
    if (auto blk = cast(BlockStmt)  n) { foreach (s; blk.stmts)   scanNodeForInterpIdents(s, result); return; }
    if (auto es  = cast(ExprStmt)   n) { scanExprForInterpIdents(es.expr,  result); return; }
    if (auto rs  = cast(ReturnStmt) n) { scanExprForInterpIdents(rs.value, result); return; }
    if (auto vd  = cast(VarDecl)    n) { scanExprForInterpIdents(vd.init,  result); return; }
    if (auto ifs = cast(IfStmt)     n)
    {
        scanExprForInterpIdents(ifs.cond, result);
        scanNodeForInterpIdents(ifs.then_, result);
        scanNodeForInterpIdents(ifs.else_, result);
        return;
    }
    if (auto ws = cast(WhileStmt) n) { scanExprForInterpIdents(ws.cond, result); scanNodeForInterpIdents(ws.body, result); return; }
    if (auto fs = cast(ForStmt)   n) { scanExprForInterpIdents(fs.seq,  result); scanNodeForInterpIdents(fs.body, result); return; }
}

private void scanExprForInterpIdents(Expr e, ref bool[string] result)
{
    if (e is null) return;
    if (auto lit = cast(LiteralExpr)          e) { if (lit.kind == LiteralExpr.Kind.string_) collectInterpIdents(lit.raw, result); return; }
    if (auto b   = cast(BinaryExpr)           e) { scanExprForInterpIdents(b.left, result); scanExprForInterpIdents(b.right, result); return; }
    if (auto u   = cast(UnaryExpr)            e) { scanExprForInterpIdents(u.operand, result); return; }
    if (auto a   = cast(AssignExpr)           e) { scanExprForInterpIdents(a.value, result); return; }
    if (auto c   = cast(CallExpr)             e) { scanExprForInterpIdents(c.receiver, result); foreach (arg; c.args) scanExprForInterpIdents(arg, result); return; }
    if (auto se  = cast(SetterExpr)           e) { scanExprForInterpIdents(se.receiver, result); scanExprForInterpIdents(se.value, result); return; }
    if (auto sub = cast(SubscriptExpr)        e) { scanExprForInterpIdents(sub.receiver, result); foreach (idx; sub.indices) scanExprForInterpIdents(idx, result); return; }
    if (auto sub = cast(SubscriptAssignExpr)  e) { scanExprForInterpIdents(sub.receiver, result); foreach (idx; sub.indices) scanExprForInterpIdents(idx, result); scanExprForInterpIdents(sub.value, result); return; }
    if (auto t   = cast(TernaryExpr)          e) { scanExprForInterpIdents(t.cond, result); scanExprForInterpIdents(t.then_, result); scanExprForInterpIdents(t.else_, result); return; }
    if (auto r   = cast(RangeExpr)            e) { scanExprForInterpIdents(r.from, result); scanExprForInterpIdents(r.to, result); return; }
    if (auto le  = cast(ListExpr)             e) { foreach (el; le.elements) scanExprForInterpIdents(el, result); return; }
    if (auto me  = cast(MapExpr)              e) { foreach (k; me.keys) scanExprForInterpIdents(k, result); foreach (v; me.values) scanExprForInterpIdents(v, result); return; }
    if (auto be  = cast(BlockExpr)            e) { scanNodeForInterpIdents(be.body, result); return; }
    if (auto se  = cast(SuperExpr)            e) { foreach (a; se.args) scanExprForInterpIdents(a, result); return; }
}

// ── Body optimizer ────────────────────────────────────────────────────────────

private void optimizeBody(BlockStmt body_,
                          string[]             methodParams,
                          LiteralExpr[string]  outerConsts,
                          string[string]       outerRenames,
                          bool[string]         forbidden = null)
{
    // Pass 1 — constant collection
    LiteralExpr[string] consts;
    if (outerConsts !is null)
        foreach (k, v; outerConsts) consts[k] = v;

    foreach (s; body_.stmts)
        if (auto vd = cast(VarDecl) s)
        {
            // Fold the initializer with currently-known consts so that
            // expressions like `x + 3` (where x is already a const) become
            // a literal and can themselves be collected as constants.
            Expr foldedInit = foldExpr(vd.init, consts);
            if (auto lit = cast(LiteralExpr) foldedInit)
                consts[vd.name] = lit;
        }

    // Invalidate any var that is ever reassigned anywhere in the body tree
    removeReassigned(body_, consts);

    // Pass 2a — fold
    Node[] folded;
    foreach (s; body_.stmts)
    {
        if (auto vd = cast(VarDecl) s)
        {
            if (vd.name in consts) continue; // dead — remove
            vd.init = foldExpr(vd.init, consts);
            folded ~= vd;
        }
        else folded ~= foldStmt(s, consts);
    }
    body_.stmts = folded;

    // Pass 2b — rename
    string[string] renames;
    if (outerRenames !is null)
        foreach (k, v; outerRenames) renames[k] = v;

    NameAllocator alloc;
    alloc.forbidden = forbidden;

    // Identifiers used inside %(…) string interpolations must keep their original
    // names — the literal text is opaque to the renamer and cannot be updated.
    bool[string] interpIdents;
    scanNodeForInterpIdents(body_, interpIdents);
    foreach (k; interpIdents.byKey)
    {
        if (shouldRename(k)) renames[k] = k; // identity mapping: k stays as k
        alloc.forbidden[k] = true;           // don't assign k as a short name for others
    }

    // Rename params first (in order)
    foreach (ref p; methodParams)
    {
        if (!shouldRename(p) || p in renames) continue; // skip interp-protected names
        string n = alloc.next();
        renames[p] = n;
        p = n;
    }
    // Then rename local vars (in declaration order)
    foreach (s; body_.stmts)
        if (auto vd = cast(VarDecl) s)
            if (shouldRename(vd.name) && vd.name !in renames)
            {
                string n = alloc.next();
                renames[vd.name] = n;
                vd.name = n;
            }

    // Collect ForStmt loop variables and assign short names
    // Forward-declare as a delegate to allow mutual recursion with collectForVars.
    void delegate(Expr) collectForVarsExpr;
    void collectForVars(Node n)
    {
        if (auto blk = cast(BlockStmt) n) { foreach (s; blk.stmts) collectForVars(s); return; }
        if (auto fs  = cast(ForStmt)   n)
        {
            if (shouldRename(fs.loopVar) && fs.loopVar !in renames)
                renames[fs.loopVar] = alloc.next();
            collectForVars(fs.body);
            return;
        }
        if (auto ifs = cast(IfStmt)   n) { collectForVars(ifs.then_); if (ifs.else_) collectForVars(ifs.else_); return; }
        if (auto ws  = cast(WhileStmt) n) { collectForVars(ws.body); return; }
        if (auto es  = cast(ExprStmt)  n) { collectForVarsExpr(es.expr); return; }
    }
    collectForVarsExpr = delegate(Expr e)
    {
        if (e is null) return;
        if (auto be  = cast(BlockExpr)           e) { collectForVars(be.body); return; }
        if (auto c   = cast(CallExpr)            e) { collectForVarsExpr(c.receiver); foreach (a; c.args) collectForVarsExpr(a); return; }
        if (auto b   = cast(BinaryExpr)          e) { collectForVarsExpr(b.left); collectForVarsExpr(b.right); return; }
        if (auto u   = cast(UnaryExpr)           e) { collectForVarsExpr(u.operand); return; }
        if (auto a   = cast(AssignExpr)          e) { collectForVarsExpr(a.value); return; }
        if (auto se  = cast(SetterExpr)          e) { collectForVarsExpr(se.receiver); collectForVarsExpr(se.value); return; }
        if (auto sub = cast(SubscriptExpr)       e) { collectForVarsExpr(sub.receiver); foreach (i; sub.indices) collectForVarsExpr(i); return; }
        if (auto sub = cast(SubscriptAssignExpr) e) { collectForVarsExpr(sub.receiver); foreach (i; sub.indices) collectForVarsExpr(i); collectForVarsExpr(sub.value); return; }
        if (auto t   = cast(TernaryExpr)         e) { collectForVarsExpr(t.cond); collectForVarsExpr(t.then_); collectForVarsExpr(t.else_); return; }
        if (auto r   = cast(RangeExpr)           e) { collectForVarsExpr(r.from); collectForVarsExpr(r.to); return; }
        if (auto le  = cast(ListExpr)            e) { foreach (el; le.elements) collectForVarsExpr(el); return; }
        if (auto me  = cast(MapExpr)             e) { foreach (k; me.keys) collectForVarsExpr(k); foreach (v; me.values) collectForVarsExpr(v); return; }
        if (auto se  = cast(SuperExpr)           e) { foreach (a; se.args) collectForVarsExpr(a); return; }
    };
    collectForVars(body_);

    // Apply renames throughout body
    foreach (ref s; body_.stmts) s = renameStmt(s, renames, alloc);
}

// ── Pass 1 helpers ────────────────────────────────────────────────────────────

private void removeReassigned(Node n, ref LiteralExpr[string] consts)
{
    if (auto blk = cast(BlockStmt) n)
    { foreach (s; blk.stmts) removeReassigned(s, consts); return; }
    if (auto es  = cast(ExprStmt)   n) { removeReassignedExpr(es.expr,   consts); return; }
    if (auto rs  = cast(ReturnStmt) n) { if (rs.value) removeReassignedExpr(rs.value, consts); return; }
    if (auto vd  = cast(VarDecl)    n) { if (vd.init)  removeReassignedExpr(vd.init,  consts); return; }
    if (auto ifs = cast(IfStmt)     n)
    {
        removeReassignedExpr(ifs.cond, consts);
        removeReassigned(ifs.then_, consts);
        if (ifs.else_ !is null) removeReassigned(ifs.else_, consts);
        return;
    }
    if (auto ws = cast(WhileStmt)  n) { removeReassignedExpr(ws.cond, consts); removeReassigned(ws.body,  consts); return; }
    if (auto fs = cast(ForStmt)    n)
    {
        removeReassignedExpr(fs.seq, consts);
        consts.remove(fs.loopVar); // loop var shadows any outer const with the same name
        removeReassigned(fs.body, consts);
        return;
    }
}

private void removeReassignedExpr(Expr e, ref LiteralExpr[string] consts)
{
    if (e is null) return;
    if (auto a   = cast(AssignExpr)          e) { consts.remove(a.name); removeReassignedExpr(a.value, consts); return; }
    if (auto b   = cast(BinaryExpr)          e) { removeReassignedExpr(b.left, consts); removeReassignedExpr(b.right, consts); return; }
    if (auto u   = cast(UnaryExpr)           e) { removeReassignedExpr(u.operand, consts); return; }
    if (auto c   = cast(CallExpr)            e) { if (c.receiver) removeReassignedExpr(c.receiver, consts); foreach (a; c.args) removeReassignedExpr(a, consts); return; }
    if (auto se  = cast(SetterExpr)          e) { removeReassignedExpr(se.receiver, consts); removeReassignedExpr(se.value, consts); return; }
    if (auto sub = cast(SubscriptExpr)       e) { removeReassignedExpr(sub.receiver, consts); foreach (i; sub.indices) removeReassignedExpr(i, consts); return; }
    if (auto sub = cast(SubscriptAssignExpr) e) { removeReassignedExpr(sub.receiver, consts); foreach (i; sub.indices) removeReassignedExpr(i, consts); removeReassignedExpr(sub.value, consts); return; }
    if (auto t   = cast(TernaryExpr)         e) { removeReassignedExpr(t.cond, consts); removeReassignedExpr(t.then_, consts); removeReassignedExpr(t.else_, consts); return; }
    if (auto r   = cast(RangeExpr)           e) { removeReassignedExpr(r.from, consts); removeReassignedExpr(r.to, consts); return; }
    if (auto le  = cast(ListExpr)            e) { foreach (el; le.elements) removeReassignedExpr(el, consts); return; }
    if (auto me  = cast(MapExpr)             e) { foreach (k; me.keys) removeReassignedExpr(k, consts); foreach (v; me.values) removeReassignedExpr(v, consts); return; }
    if (auto be  = cast(BlockExpr)           e)
    {
        // Closure params shadow outer names; don't let assignments to them
        // invalidate outer constants with the same name.
        LiteralExpr[string] innerConsts = consts.dup;
        bool[string] shadowed;
        foreach (p; be.params) { innerConsts.remove(p); shadowed[p] = true; }
        removeReassigned(be.body, innerConsts);
        // Propagate genuine invalidations (not caused by param shadowing) to outer scope
        foreach (k; consts.keys)
            if (k !in shadowed && k !in innerConsts) consts.remove(k);
        return;
    }
    if (auto se  = cast(SuperExpr)           e) { foreach (a; se.args) removeReassignedExpr(a, consts); return; }
}

// ── Pass 2a — fold ────────────────────────────────────────────────────────────

private Node foldStmt(Node s, LiteralExpr[string] consts)
{
    if (auto es  = cast(ExprStmt)   s) { es.expr   = foldExpr(es.expr,   consts); return es; }
    if (auto rs  = cast(ReturnStmt) s) { if (rs.value) rs.value = foldExpr(rs.value, consts); return rs; }
    if (auto vd  = cast(VarDecl)    s) { vd.init   = foldExpr(vd.init,   consts); return vd; }
    if (auto ifs = cast(IfStmt)     s)
    {
        ifs.cond  = foldExpr(ifs.cond,  consts);
        ifs.then_ = foldStmt(ifs.then_, consts);
        if (ifs.else_ !is null) ifs.else_ = foldStmt(ifs.else_, consts);
        return ifs;
    }
    if (auto ws = cast(WhileStmt)  s) { ws.cond = foldExpr(ws.cond, consts); ws.body = foldStmt(ws.body, consts); return ws; }
    if (auto fs = cast(ForStmt)    s) { fs.seq  = foldExpr(fs.seq,  consts); fs.body = foldStmt(fs.body, consts); return fs; }
    if (auto blk = cast(BlockStmt) s)
    {
        Node[] out_;
        foreach (inner; blk.stmts)
        {
            if (auto vd = cast(VarDecl) inner)
            {
                if (vd.name in consts) continue;
                vd.init = foldExpr(vd.init, consts);
                out_ ~= vd;
            }
            else out_ ~= foldStmt(inner, consts);
        }
        blk.stmts = out_;
        return blk;
    }
    return s;
}

Expr foldExpr(Expr e, LiteralExpr[string] consts)
{
    if (e is null) return e;
    if (auto id  = cast(IdentExpr)           e) { if (auto p = id.name in consts) return (*p).dup(); return e; }
    if (auto b   = cast(BinaryExpr)          e) { b.left = foldExpr(b.left, consts); b.right = foldExpr(b.right, consts); return tryFoldArith(b); }
    if (auto u   = cast(UnaryExpr)           e) { u.operand = foldExpr(u.operand, consts); return tryFoldUnary(u); }
    if (auto a   = cast(AssignExpr)          e) { a.value   = foldExpr(a.value,   consts); return e; }
    if (auto c   = cast(CallExpr)            e) { if (c.receiver) c.receiver = foldExpr(c.receiver, consts); foreach (ref arg; c.args) arg = foldExpr(arg, consts); return e; }
    if (auto se  = cast(SetterExpr)          e) { se.receiver = foldExpr(se.receiver, consts); se.value = foldExpr(se.value, consts); return e; }
    if (auto sub = cast(SubscriptExpr)       e) { sub.receiver = foldExpr(sub.receiver, consts); foreach (ref i; sub.indices) i = foldExpr(i, consts); return e; }
    if (auto sub = cast(SubscriptAssignExpr) e) { sub.receiver = foldExpr(sub.receiver, consts); foreach (ref i; sub.indices) i = foldExpr(i, consts); sub.value = foldExpr(sub.value, consts); return e; }
    if (auto t   = cast(TernaryExpr)         e) { t.cond = foldExpr(t.cond, consts); t.then_ = foldExpr(t.then_, consts); t.else_ = foldExpr(t.else_, consts); return e; }
    if (auto r   = cast(RangeExpr)           e) { r.from = foldExpr(r.from, consts); r.to = foldExpr(r.to, consts); return e; }
    if (auto le  = cast(ListExpr)            e) { foreach (ref el; le.elements) el = foldExpr(el, consts); return e; }
    if (auto me  = cast(MapExpr)             e) { foreach (ref k; me.keys) k = foldExpr(k, consts); foreach (ref v; me.values) v = foldExpr(v, consts); return e; }
    if (auto be  = cast(BlockExpr)           e)
    {
        // Closures inherit outer constants but params shadow outer names.
        LiteralExpr[string] innerConsts = consts.dup;
        foreach (p; be.params) innerConsts.remove(p);
        foreach (ref s; be.body.stmts) s = foldStmt(s, innerConsts);
        return e;
    }
    if (auto se  = cast(SuperExpr)           e) { foreach (ref a; se.args) a = foldExpr(a, consts); return e; }
    return e;
}

private Expr tryFoldUnary(UnaryExpr u)
{
    if (u.op != "-") return u;
    auto lit = cast(LiteralExpr) u.operand;
    if (lit is null || lit.kind != LiteralExpr.Kind.number) return u;
    double v;
    try { v = lit.raw.to!double; }
    catch (ConvException) return u;
    v = -v;
    if (isInfinity(v) || isNaN(v)) return u;
    auto r  = new LiteralExpr();
    r.kind  = LiteralExpr.Kind.number;
    r.raw   = (v == floor(v) && v >= long.min && v <= long.max)
              ? format("%d", cast(long) v)
              : format("%g", v);
    return r;
}

private Expr tryFoldArith(BinaryExpr b)
{
    auto lLit = cast(LiteralExpr) b.left;
    auto rLit = cast(LiteralExpr) b.right;
    if (lLit is null || rLit is null)                    return b;
    if (lLit.kind != LiteralExpr.Kind.number)            return b;
    if (rLit.kind != LiteralExpr.Kind.number)            return b;

    double lv, rv;
    try { lv = lLit.raw.to!double; rv = rLit.raw.to!double; }
    catch (ConvException) return b;

    double result;
    switch (b.op)
    {
        case "+": result = lv + rv; break;
        case "-": result = lv - rv; break;
        case "*": result = lv * rv; break;
        case "/":
            if (rv == 0.0) return b;
            result = lv / rv;
            break;
        default: return b;
    }

    if (isInfinity(result) || isNaN(result)) return b;
    auto lit  = new LiteralExpr();
    lit.kind  = LiteralExpr.Kind.number;
    lit.raw   = (result == floor(result) && result >= long.min && result <= long.max)
                ? format("%d", cast(long) result)
                : format("%g", result);
    return lit;
}

// ── Pass 2b — rename ──────────────────────────────────────────────────────────

private bool shouldRename(string name) pure nothrow
{
    return name.length > 0 && name[0] != '_';
}

private struct NameAllocator
{
    int counter = 0;
    bool[string] forbidden;

    private static immutable string[] reserved = [
        "as","break","class","construct","continue","else","false",
        "for","foreign","if","import","in","is","null","return",
        "static","super","this","true","var","while"
    ];

    string next()
    {
        while (true)
        {
            string name = indexToName(counter++);
            bool ok = true;
            foreach (r; reserved) if (r == name) { ok = false; break; }
            if (ok && (name in forbidden)) ok = false;
            if (ok) return name;
        }
    }

    private static string indexToName(int i) pure
    {
        string s;
        do {
            s = cast(char)('a' + i % 26) ~ s;
            i = i / 26 - 1;
        } while (i >= 0);
        return s;
    }
}

private Node renameStmt(Node s, string[string] renames, ref NameAllocator alloc)
{
    if (auto es  = cast(ExprStmt)   s) { es.expr   = renameExpr(es.expr,   renames, alloc); return es; }
    if (auto rs  = cast(ReturnStmt) s) { if (rs.value) rs.value = renameExpr(rs.value, renames, alloc); return rs; }
    if (auto vd  = cast(VarDecl)    s) { vd.init   = renameExpr(vd.init,   renames, alloc); return vd; }
    if (auto ifs = cast(IfStmt)     s)
    {
        ifs.cond  = renameExpr(ifs.cond, renames, alloc);
        ifs.then_ = renameStmt(ifs.then_, renames, alloc);
        if (ifs.else_ !is null) ifs.else_ = renameStmt(ifs.else_, renames, alloc);
        return ifs;
    }
    if (auto ws = cast(WhileStmt)  s) { ws.cond = renameExpr(ws.cond, renames, alloc); ws.body = renameStmt(ws.body, renames, alloc); return ws; }
    if (auto fs = cast(ForStmt)    s)
    {
        fs.seq = renameExpr(fs.seq, renames, alloc);
        if (shouldRename(fs.loopVar))
            if (auto r = fs.loopVar in renames) fs.loopVar = *r;
        fs.body = renameStmt(fs.body, renames, alloc);
        return fs;
    }
    if (auto blk = cast(BlockStmt) s)
    {
        // Each nested block gets its own scope: vars declared here that shadow
        // an outer rename receive a fresh short name, processed in declaration
        // order so init expressions see the outer binding, not the inner one.
        string[string] local = renames.dup;
        foreach (ref inner; blk.stmts)
        {
            if (auto vd2 = cast(VarDecl) inner)
            {
                vd2.init = renameExpr(vd2.init, local, alloc);
                if (shouldRename(vd2.name))
                {
                    string n2 = alloc.next();
                    local[vd2.name] = n2;
                    vd2.name = n2;
                }
            }
            else inner = renameStmt(inner, local, alloc);
        }
        return blk;
    }
    return s;
}

private Expr renameExpr(Expr e, string[string] renames, ref NameAllocator alloc)
{
    if (e is null) return e;
    if (auto id  = cast(IdentExpr)           e) { if (auto r = id.name in renames) id.name = *r; return id; }
    if (auto a   = cast(AssignExpr)          e) { if (auto r = a.name  in renames) a.name  = *r; a.value = renameExpr(a.value, renames, alloc); return a; }
    if (auto b   = cast(BinaryExpr)          e) { b.left = renameExpr(b.left, renames, alloc); b.right = renameExpr(b.right, renames, alloc); return b; }
    if (auto u   = cast(UnaryExpr)           e) { u.operand = renameExpr(u.operand, renames, alloc); return e; }
    if (auto c   = cast(CallExpr)            e) { if (c.receiver) c.receiver = renameExpr(c.receiver, renames, alloc); foreach (ref arg; c.args) arg = renameExpr(arg, renames, alloc); return e; }
    if (auto se  = cast(SetterExpr)          e) { se.receiver = renameExpr(se.receiver, renames, alloc); se.value = renameExpr(se.value, renames, alloc); return e; }
    if (auto sub = cast(SubscriptExpr)       e) { sub.receiver = renameExpr(sub.receiver, renames, alloc); foreach (ref i; sub.indices) i = renameExpr(i, renames, alloc); return e; }
    if (auto sub = cast(SubscriptAssignExpr) e) { sub.receiver = renameExpr(sub.receiver, renames, alloc); foreach (ref i; sub.indices) i = renameExpr(i, renames, alloc); sub.value = renameExpr(sub.value, renames, alloc); return e; }
    if (auto t   = cast(TernaryExpr)         e) { t.cond = renameExpr(t.cond, renames, alloc); t.then_ = renameExpr(t.then_, renames, alloc); t.else_ = renameExpr(t.else_, renames, alloc); return e; }
    if (auto r   = cast(RangeExpr)           e) { r.from = renameExpr(r.from, renames, alloc); r.to = renameExpr(r.to, renames, alloc); return e; }
    if (auto le  = cast(ListExpr)            e) { foreach (ref el; le.elements) el = renameExpr(el, renames, alloc); return e; }
    if (auto me  = cast(MapExpr)             e) { foreach (ref k; me.keys) k = renameExpr(k, renames, alloc); foreach (ref v; me.values) v = renameExpr(v, renames, alloc); return e; }
    if (auto be  = cast(BlockExpr)           e)
    {
        string[string] local = renames.dup;
        foreach (ref p; be.params)
        {
            if (!shouldRename(p)) continue;
            if (p in local && local[p] == p) continue; // interp-protected: must keep name
            string n = alloc.next();
            local[p] = n;
            p = n;
        }
        be.body = cast(BlockStmt) renameStmt(be.body, local, alloc);
        return e;
    }
    if (auto se  = cast(SuperExpr)           e) { foreach (ref a; se.args) a = renameExpr(a, renames, alloc); return e; }
    return e;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

unittest
{
    import lexer, parser;

    // constant var folded into return
    auto mod = parseModule(tokenize("class A {\n  f {\n    var x = 42\n    return x\n  }\n}"));
    optimizeModule(mod);
    auto body = (cast(ClassDecl) mod.items[0]).methods[0].body;
    assert(body.stmts.length == 1);
    auto ret = cast(ReturnStmt) body.stmts[0];
    assert(ret !is null);
    auto lit = cast(LiteralExpr) ret.value;
    assert(lit !is null && lit.raw == "42");

    // mutable var NOT folded
    auto mod2 = parseModule(tokenize(
        "class A {\n  f {\n    var x = 1\n    x = 2\n    return x\n  }\n}"));
    optimizeModule(mod2);
    auto body2 = (cast(ClassDecl) mod2.items[0]).methods[0].body;
    assert(body2.stmts.length == 3);

    // arithmetic constant folding
    auto mod3 = parseModule(tokenize(
        "class A {\n  f {\n    var x = 2\n    var y = x + 3\n    return y\n  }\n}"));
    optimizeModule(mod3);
    auto body3 = (cast(ClassDecl) mod3.items[0]).methods[0].body;
    assert(body3.stmts.length == 1);
    auto lit3 = cast(LiteralExpr)(cast(ReturnStmt) body3.stmts[0]).value;
    assert(lit3 !is null && lit3.raw == "5");
}

unittest
{
    import lexer, parser;

    // params renamed
    auto mod = parseModule(tokenize(
        "class A {\n  f(foo, bar) {\n    return foo + bar\n  }\n}"));
    optimizeModule(mod);
    auto m   = (cast(ClassDecl) mod.items[0]).methods[0];
    assert(m.params == ["a", "b"]);
    auto ret = cast(ReturnStmt) m.body.stmts[0];
    auto bin = cast(BinaryExpr) ret.value;
    assert((cast(IdentExpr) bin.left ).name == "a");
    assert((cast(IdentExpr) bin.right).name == "b");

    // field names NOT renamed (start with _)
    auto mod2 = parseModule(tokenize(
        "class A {\n  f {\n    var _x = 1\n    return _x\n  }\n}"));
    optimizeModule(mod2);
    auto body2 = (cast(ClassDecl) mod2.items[0]).methods[0].body;
    // _x is foldable (literal, never reassigned) → folded away
    assert(body2.stmts.length == 1);
    auto retLit = cast(LiteralExpr)(cast(ReturnStmt) body2.stmts[0]).value;
    assert(retLit !is null && retLit.raw == "1");

    // local var renamed
    auto mod3 = parseModule(tokenize(
        "class A {\n  f {\n    var count = 0\n    count = count + 1\n    return count\n  }\n}"));
    optimizeModule(mod3);
    auto body3 = (cast(ClassDecl) mod3.items[0]).methods[0].body;
    auto vd3   = cast(VarDecl) body3.stmts[0];
    assert(vd3 !is null && vd3.name == "a");

    // NameAllocator sequence
    NameAllocator na;
    assert(na.next() == "a");
    assert(na.next() == "b");
    // skip reserved words — 'as' is index 0 of reserved, 'break'=1, etc.
    // just verify the sequence hits z then aa
    NameAllocator nb;
    string[] seq;
    foreach (_; 0..30) seq ~= nb.next();
    assert(seq[25] == "z");         // 26th non-reserved name
    assert(seq[26].length == 2);    // aa or similar
}
