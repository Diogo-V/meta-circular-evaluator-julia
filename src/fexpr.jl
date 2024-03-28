# ------------------------------------------------------------------------------
# fexpr.jl
# This file contains the implementation of fexpr (function expressions) and
# related structures and functions.
# ------------------------------------------------------------------------------
include("./env.jl")


# ------------------------------------------------------------------------------
#                                Structures
# ------------------------------------------------------------------------------


"""
    FExpr

A structure representing a function expression (fexpr) in the MetaJulia language.

# Fields
- `name::Symbol`: The name of the fexpr.
- `args::Any`: The arguments of the fexpr.
- `body::Any`: The body of the fexpr.
- `scope::Env`: The environment scope of the fexpr.
"""
struct FExpr
    name::Symbol
    args::Any
    body::Any
    scope::Env
end


"""
    show(io::IO, p::FExpr)

Special show method for `FExpr` objects, printing "<fexpr>" when called.
"""
show(io::IO, p::FExpr) = print(io, "<fexpr>")


"""
    CallScopedEval

A structure representing the evaluation of an expression in the call scope
of a function expression (fexpr).

# Fields
- `def_fn_env::Env`: The environment scope of the fexpr definition.
- `call_fn_env::Env`: The environment scope of the fexpr call.
"""
struct CallScopedEval
    def_fn_env::Env
    call_fn_env::Env
end


"""
    show(io::IO, p::CallScopedEval)

Special show method for `CallScopedEval` objects, printing "<function>" when called.
"""
show(io::IO, p::CallScopedEval) = print(io, "<function>")


# ------------------------------------------------------------------------------
#                                Auxiliaries
# ------------------------------------------------------------------------------


"""
    call_scoped_eval(params::CallScopedEval)

Create a function that evaluates an expression in the call scope of a function expression (fexpr).
If no variables are bound during the fexpr definition, the expression is evaluated directly
in the call scope. Otherwise, the expression is first evaluated in the definition scope
to retrieve its value, and then evaluated in the call scope.
"""
function call_scoped_eval(params::CallScopedEval)
    return (expr::Any) -> begin
        if length(params.def_fn_env.vars) == 1
            return eval_expr(expr, params.call_fn_env)
        end

        arg = eval_expr(expr, params.def_fn_env)
        return eval_expr(arg, params.call_fn_env)
    end
end


"""
    make_fexpr(args::Any, body::Union{Expr, Symbol}, env::Env, name::Symbol=:())

Create a new function expression (fexpr) with the given `args`, `body`, and `name`
in the provided environment `env`.
"""
function make_fexpr(args::Any, body::Union{Expr, Symbol}, env::Env, name::Symbol=:())
    scope = extend_env(env)

    func = (params...) -> begin
        call_env = params[end - 1]
        def_env = params[end]
        params = params[1:end-2]

        bindings = Dict{Symbol,Any}(zip(args, params))

        for (var, value) in bindings
            set_value!(def_env, var, value)
        end

        # In fexpr, the eval function is evaluated in the call scope and so,
        # we create a function that evaluates the body in the call scope
        # and store it in the function scope
        set_value!(def_env, :eval, CallScopedEval(def_env, call_env))

        res = eval_expr(body, def_env)
        return res
    end

    func = FExpr(name, args, func, scope)
    return func
end


# ------------------------------------------------------------------------------
#                           Statement Handling
# ------------------------------------------------------------------------------


"""
    handle_fexpr(expr::Expr, eval_env::Env, storing_env::Env)

Handle the definition of a new function expression (fexpr) from the given expression `expr`.
The fexpr is created in the `eval_env` environment and stored in the `storing_env` environment.
"""
function handle_fexpr(expr::Expr, eval_env::Env, storing_env::Env)
    signature = expr.args[1]
    body = expr.args[2]
    fn_name = signature.args[1]
    args = signature.args[2:end]

    args = isa(args, Symbol) ? [args] : args

    func = make_fexpr(args, body, eval_env, fn_name)

    set_value!(storing_env, fn_name, func)
    return func
end
