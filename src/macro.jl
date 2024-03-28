include("./env.jl")


# --------------------------------------------------------------------------- #
# ------------------------------- Structures -------------------------------- #
# --------------------------------------------------------------------------- #


struct MetaMacro
    name::Symbol
    args::Any
    body::Any
    scope::Env
end
show(io::IO, p::MetaMacro) = print(io, "<macro>")


# --------------------------------------------------------------------------- #
# ------------------------------- Auxiliaries ------------------------------- #
# --------------------------------------------------------------------------- #


function macro_expansion(expr::Any, env::Env)

    # 1. Iterates over all arguments of the expression
    if isa(expr, Expr) && expr.head !== :$
        expr = Expr(expr.head, [
            macro_expansion(arg, env) for arg in expr.args
        ]...)
        return expr
    end

    # 2. If we found an interpolation, we need to replace it by fetching the expression
    if isa(expr, Expr) && expr.head === :$
        val = handle_interpolation(expr, env)
        return val
    end

    # 3. If we don't have an expression, we return it as is
    return expr
end


function find_lhs_assignments(expr::Any, symbols::Vector{Any})
    # 1. Iterates over all arguments of the expression
    if isa(expr, Expr)
        find_lhs_assignments.(expr.args, Ref(symbols))
    end

    # 2. If we found an assignment, we store the left hand side symbol
    # in the symbols vector
    if isa(expr, Symbol)
        push!(symbols, expr)
    end
end


function macro_gensym(expr::Any, env::Env)

    # 1. Finds all the symbols in the expression that are left hand
    # sides of assignments
    symbols = []
    find_lhs_assignments(expr, symbols)

    # 2. Dedupes the symbols
    symbols = unique(symbols)

    # 3. Removes the symbols that are already defined in the environment
    symbols = filter(sym -> get_value(env, sym) === nothing, symbols)

    # 3. Sets the value of the symbols to a gensym to avoid shadowing
    # variables in the environment
    for sym in symbols
        set_value!(env, sym, gensym())
    end

    # 5. Returns the new macro wrapped in a let statement
    return expr
end


function make_macro(args::Any, body::Union{Expr, Symbol}, env::Env, name::Symbol=:())

    # 1. Creates a new scope for the macro
    scope = extend_env(env)

    # 1. Creates a new macro
    func = (params...) -> begin
        call_env = params[end - 1]
        def_env = params[end]
        params = params[1:end-2]

        # 1.1. Takes the arguments and binds them to the macro parameters
        bindings = Dict{Symbol,Any}(zip(args, params))

        # 1.2. Before evaluating the body, we extend the macro scope with the bindings
        for (var, value) in bindings
            set_value!(def_env, var, value)
        end

        # 1.3. Since when we expand the macro, we might create name collisions,
        # we need to resolve the conflicts by generating unique names to 
        # the assigned varibales
        expr = macro_gensym(body, def_env)
        
        # 1.4. Expands the macro into the expression to be evaluated
        # given the scope
        expr = macro_expansion(expr, def_env)

        # 1.5. Evaluates the macro in the call scope
        res = eval_expr(expr, call_env)
        return res
    end

    func = MetaMacro(name, args, func, scope)

    # 2. Return the function
    return func
end


# --------------------------------------------------------------------------- #
# --------------------------- Statement Handling ---------------------------- #
# --------------------------------------------------------------------------- #


function handle_macro(expr::Expr, eval_env::Env, storing_env::Env)
    signature = expr.args[1]
    body = expr.args[2]
    macro_name = signature.args[1]
    args = signature.args[2:end]

    # 1. Makes sure the arguments are a vector of symbols
    args = isa(args, Symbol) ? [args] : args

    # 2. Creates a macro
    mac = make_macro(args, body, eval_env, macro_name)

    # 3. Stores the macro in the environment
    set_value!(storing_env, macro_name, mac)

    # 4. Returns the macro
    return mac
end


function handle_interpolation(expr::Expr, env::Env)
    sym = expr.args[end]

    # 1. Fetches the value of the symbol that is going to be interpolated
    # from the environment
    val = get_value(env, sym)

    # 2. Returns the value of the symbol without evaluating it
    return val
end
