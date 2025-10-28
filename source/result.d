module result;

import std.conv;
import std.stdio;
public import std.sumtype : SumType, match;

alias Result(T) = SumType!(T, Exception);

/// Catch an exception and wrap it in a result type
Result!T tryEval(T)(lazy T expr) nothrow {
    try return Result!T(expr);
    catch (Exception e) return Result!T(e);
}

version(unittest) {
    class TooSmallException : Exception {
        this(string msg, string file = __FILE__, size_t line = __LINE__) {
            super(msg, file, line);
        }
    }

    class ZeroException : Exception {
        this(string msg, string file = __FILE__, size_t line = __LINE__) {
            super(msg, file, line);
        }
    }
}

unittest {
    int foo(int a) {
        if (a < 0)  throw new         Exception("a is negative: " ~ a.to!string);
        if (a == 0) throw new     ZeroException("a is zero");
        if (a <= 2) throw new TooSmallException("a is too small: " ~ a.to!string);
        return a * 42;
    }

    string tryFoo(int a) {
        return tryEval(foo(a)).match!(
            (int n) => "Got int " ~ n.to!string,
            (Exception e) {
                if (typeid(e) == typeid(ZeroException))
                    return "Special message on zero !!!";
                else
                    return "Got " ~ typeid(e).to!string ~ " with message " ~ e.msg;
            },
        );
    }

    assert(tryFoo(-1) == "Got object.Exception with message a is negative: -1");
    assert(tryFoo(0)  == "Special message on zero !!!");
    assert(tryFoo(1)  == "Got result.TooSmallException with message a is too small: 1");
    assert(tryFoo(4)  == "Got int 168");
}

// TODO: make a unittest for this
T orDefault(T)(lazy T expr) nothrow {
    int[] errors;
    return expr.orDefaultWithError(0, errors);
}

// TODO: make a unittest for this
T orDefaultWithError(T, E)(lazy T expr, E error, ref E[] errors) nothrow {
    return tryEval(expr).match!(
        (T value) => value,
        (_) {
            errors ~= error;
            return T.init;
        },
    );
}
