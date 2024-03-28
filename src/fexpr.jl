include("./env.jl")


# --------------------------------------------------------------------------- #
# ------------------------------- Structures -------------------------------- #
# --------------------------------------------------------------------------- #


struct FExpr
    name::Symbol   # Contains the name of the fexpr
    args::Any      # Contains the arguments of the fexpr
    body::Any      # Contains the body of the fexpr
    scope::Env     # Contains an environment which is an extension of the calling environment
end
show(io::IO, p::FExpr) = print(io, "<fexpr>")


struct CallScopedEval
    def_fn_env::Env
    call_fn_env::Env
end
show(io::IO, p::CallScopedEval) = print(io, "<function>")


# --------------------------------------------------------------------------- #
# ------------------------------- Auxiliaries ------------------------------- #
# --------------------------------------------------------------------------- #


function call_scoped_eval(params::CallScopedEval)
    return (expr::Any) -> begin
        # If we call the eval function without binding any variable, during the
        # build of the fexpr, we don't need to retrieve the expression from the
        # function definition scope and instead, we can evaluate it directly
        if length(params.def_fn_env.vars) == 1
            return eval_expr(expr, params.call_fn_env)
        end

        # We need to first evaluate the expression in the function definition scope
        # to get the expression by using the symbol and then evaluate it in the
        # function call scope
        arg = eval_expr(expr, params.def_fn_env)
        return eval_expr(arg, params.call_fn_env)
    end
end


function make_fexpr(args::Any, body::Union{Expr, Symbol}, env::Env, name::Symbol=:())

    # 1. Creates a new scope for the fexpr
    scope = extend_env(env)

    # 1. Creates a new function
    func = (params...) -> begin
        call_env = params[end - 1]
        def_env = params[end]
        params = params[1:end-2]

        # 1.1. Takes the arguments and binds them to the function parameters
        bindings = Dict{Symbol,Any}(zip(args, params))

        # 1.2. Before evaluating the body, we extend the function scope with the bindings
        for (var, value) in bindings
            set_value!(def_env, var, value)
        end

        # 1.3. In fexpr, the eval function is evaluated in the call scope and so,
        # we create a function that evaluates the body in the call scope
        # and store it in the function scope
        set_value!(def_env, :eval, CallScopedEval(def_env, call_env))

        # 1.3. Evaluates the body in the function scope
        res = eval_expr(body, def_env)
        return res
    end

    func = FExpr(name, args, func, scope)

    # 2. Return the function
    return func
end


# --------------------------------------------------------------------------- #
# --------------------------- Statement Handling ---------------------------- #
# --------------------------------------------------------------------------- #


function handle_fexpr(expr::Expr, eval_env::Env, storing_env::Env)
    signature = expr.args[1]
    body = expr.args[2]
    fn_name = signature.args[1]
    args = signature.args[2:end]

    # 1. Makes sure the arguments are a vector of symbols
    args = isa(args, Symbol) ? [args] : args

    # 2. Creates a function 
    func = make_fexpr(args, body, eval_env, fn_name)

    # 3. Stores the function in the environment
    set_value!(storing_env, fn_name, func)

    # 4. Returns the function
    return func
end
