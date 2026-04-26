module ast;

// ── Base ──────────────────────────────────────────────────────────────────────
class Node {}

// ── Module ────────────────────────────────────────────────────────────────────
class WrenModule : Node
{
    Node[] items; // ImportDecl | VarDecl | ClassDecl | ExprStmt
}

// ── Top-level declarations ────────────────────────────────────────────────────
class ImportDecl : Node
{
    string   path;          // the quoted module path, raw (including quotes)
    string[] names;         // empty = bare import; populated for "for X, Y"
    string[] aliases;       // parallel to names; "" = no alias
}

class ClassDecl : Node
{
    string       name;
    string       superclass; // "" if none
    MethodDecl[] methods;
}

enum MethodKind
{
    normal,          // name(params) { }
    getter,          // name { }
    setter,          // name=(value) { }
    op,              // operator overload: +(other) { }  or  - { }
    subscript,       // [idx] { }
    subscriptSetter, // [idx]=(val) { }
    construct,       // construct name(params) { }
    static_,         // static name(params) { }
    staticGetter,    // static name { }
    foreign_,        // foreign name(params)
    foreignStatic,   // foreign static name(params)
}

class MethodDecl : Node
{
    MethodKind kind;
    string     name;   // operator symbol for op kind
    string[]   params;
    BlockStmt  body;   // null for foreign methods
}

// ── Statements ────────────────────────────────────────────────────────────────
class VarDecl : Node
{
    string name;
    Expr   init; // always present (Wren requires initialiser)
}

class BlockStmt : Node
{
    Node[] stmts;
}

class IfStmt : Node
{
    Expr cond;
    Node then_;
    Node else_; // null if no else
}

class WhileStmt : Node
{
    Expr cond;
    Node body;
}

class ForStmt : Node
{
    string loopVar;
    Expr   seq;
    Node   body;
}

class ReturnStmt : Node
{
    Expr value; // null = bare return
}

class BreakStmt    : Node {}
class ContinueStmt : Node {}

class ExprStmt : Node
{
    Expr expr;
}

// ── Expressions ───────────────────────────────────────────────────────────────
class Expr : Node {}

class LiteralExpr : Expr
{
    enum Kind { number, string_, bool_, null_ }
    Kind   kind;
    string raw;     // verbatim source text for number/string; "true"/"false"/"null" for others
    bool   boolVal; // for kind == bool_

    LiteralExpr dup()
    {
        auto c = new LiteralExpr();
        c.kind    = kind;
        c.raw     = raw;
        c.boolVal = boolVal;
        return c;
    }
}

class ListExpr : Expr
{
    Expr[] elements;
}

class MapExpr : Expr
{
    Expr[] keys;
    Expr[] values;
}

class IdentExpr : Expr
{
    string name;
}

// Simple variable assignment:  name = value
class AssignExpr : Expr
{
    string name;
    Expr   value;
}

// obj.field = value  (setter call)
class SetterExpr : Expr
{
    Expr   receiver;
    string field;
    Expr   value;
}

class BinaryExpr : Expr
{
    string op;
    Expr   left, right;
}

class UnaryExpr : Expr
{
    string op;
    Expr   operand;
}

// Dot-method call: receiver.method(args)
// receiver == null means implicit-this call: method(args)
class CallExpr : Expr
{
    Expr     receiver; // null = implicit this
    string   method_;
    Expr[]   args;
    bool     hasParens; // true if source had explicit () — distinguishes getter from 0-arg call
}

class SubscriptExpr : Expr
{
    Expr   receiver;
    Expr[] indices;
}

class SubscriptAssignExpr : Expr
{
    Expr   receiver;
    Expr[] indices;
    Expr   value;
}

class ThisExpr  : Expr {}

class SuperExpr : Expr
{
    string method_; // "" = super constructor
    Expr[] args;
}

class RangeExpr : Expr
{
    Expr from, to;
    bool inclusive; // true = ..,  false = ...
}

class TernaryExpr : Expr
{
    Expr cond, then_, else_;
}

// Closure / block argument:  {|p1, p2| stmts }
class BlockExpr : Expr
{
    string[]  params;
    BlockStmt body;
}
