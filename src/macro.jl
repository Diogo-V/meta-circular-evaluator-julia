# ------------------------------------------------------------------------------
# macro.jl
# This file contains the implementation of macro handling.
# ------------------------------------------------------------------------------
include("./env.jl")


# ------------------------------------------------------------------------------
#                                Structures
# ------------------------------------------------------------------------------


"""
    MetaMacro

A structure representing a macro in the MetaJulia language.

# Fields
- `name::Symbol`: The name of the macro.
- `args::Any`: The arguments of the macro.
- `body::Any`: The body of the macro.
- `scope::Env`: The environment scope of the macro.
"""
struct MetaMacro
    name::Symbol
    args::Any
    body::Any
    scope::Env
end


"""
    show(io::IO, p::MetaMacro)

Special show method for `MetaMacro` objects, printing "<macro>" when called.
"""
show(io::IO, p::MetaMacro) = print(io, "<macro>")


# ------------------------------------------------------------------------------
#                                Auxiliaries
# ------------------------------------------------------------------------------


"""
    macro_expansion(expr::Any, env::Env)

Perform macro expansion on the given expression `expr` within the provided environment `env`.
This function recursively expands all subexpressions and handles interpolation.
"""
function macro_expansion(expr::Any, env::Env)
    if isa(expr, Expr) && expr.head !== :$
        expr = Expr(expr.head, [
            macro_expansion(arg, env) for arg in expr.args
        ]...)
        return expr
    end

    if isa(expr, Expr) && expr.head === :$
        val = handle_interpolation(expr, env)
        return val
    end

    return expr
end


"""
    find_lhs_assignments(expr::Any, symbols::Vector{Any})

Find all symbols that are assigned values (left-hand side of assignments) in the given expression `expr`.
The found symbols are stored in the `symbols` vector.
"""
function find_lhs_assignments(expr::Any, symbols::Vector{Any})
    if isa(expr, Expr)
        find_lhs_assignments.(expr.args, Ref(symbols))
    end

    if isa(expr, Symbol)
        push!(symbols, expr)
    end
end


"""
    macro_gensym(expr::Any, env::Env)

Generate unique symbols for all left-hand side assignments in the given expression `expr`,
to avoid shadowing variables in the environment `env`.
"""
function macro_gensym(expr::Any, env::Env)
    symbols = []
    find_lhs_assignments(expr, symbols)

    # Needs to dedupe in case it finds the same symbol multiple times and 
    # filters the symbols that were already defined in the environment
    symbols = unique(symbols)
    symbols = filter(sym -> get_value(env, sym) === nothing, symbols)

    for sym in symbols
        set_value!(env, sym, gensym())
    end

    return expr
end


"""
    make_macro(args::Any, body::Union{Expr, Symbol}, env::Env, name::Symbol=:())

Create a new macro with the given `args`, `body`, and `name` in the provided `env`.
"""
function make_macro(args::Any, body::Union{Expr, Symbol}, env::Env, name::Symbol=:())
    scope = extend_env(env)

    func = (params...) -> begin
        call_env = params[end - 1]
        def_env = params[end]
        params = params[1:end-2]

        bindings = Dict{Symbol,Any}(zip(args, params))

        for (var, value) in bindings
            set_value!(def_env, var, value)
        end

        # Since when we expand the macro, we might create name collisions,
        # we need to resolve the conflicts by generating unique names to 
        # the assigned varibales
        expr = macro_gensym(body, def_env)
        
        # Expands the macro into the expression to be evaluated given the scope
        expr = macro_expansion(expr, def_env)

        # Evaluates the macro in the call scope
        return eval_expr(expr, call_env)
    end

    func = MetaMacro(name, args, func, scope)
    return func
end

# ------------------------------------------------------------------------------
#                           Statement Handling
# ------------------------------------------------------------------------------


"""
    handle_macro(expr::Expr, eval_env::Env, storing_env::Env)

Handle the definition of a new macro from the given expression `expr`.
The macro is created in the `eval_env` environment and stored in the `storing_env` environment.
"""
function handle_macro(expr::Expr, eval_env::Env, storing_env::Env)
    signature = expr.args[1]
    body = expr.args[2]
    macro_name = signature.args[1]
    args = signature.args[2:end]

    args = isa(args, Symbol) ? [args] : args
    mac = make_macro(args, body, eval_env, macro_name)

    set_value!(storing_env, macro_name, mac)
    return mac
end


"""
    handle_interpolation(expr::Expr, env::Env)

Handle the interpolation of a symbol within the given expression `expr` in the provided environment `env`.
Returns the value of the interpolated symbol without evaluating it.
"""
function handle_interpolation(expr::Expr, env::Env)
    sym = expr.args[end]

    val = get_value(env, sym)
    return val
end
