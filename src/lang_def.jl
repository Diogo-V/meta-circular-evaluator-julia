include("./env.jl")
include("./fexpr.jl")
include("./macro.jl")

# --------------------------------------------------------------------------- #
# ------------------------------- Structures -------------------------------- #
# --------------------------------------------------------------------------- #


struct Func
    name::Symbol   # Contains the name of the function
    args::Any      # Contains the arguments of the function
    body::Any      # Contains the body of the function
    scope::Env     # Contains an environment which is an extension of the calling environment
end
show(io::IO, p::Func) = print(io, "<function>")


# --------------------------------------------------------------------------- #
# -------------------------------- Tracing ---------------------------------- #
# --------------------------------------------------------------------------- #

traceable_functions = Dict{Symbol,Any}()


function register_traceable(func::Any, call_env::Env, def_env::Env)
    traceable_functions[func] = func
end
set_value!(global_env, :register_traceable, Func(:register_traceable, [], register_traceable, global_env))


function is_traceable(name::Any)
    return haskey(traceable_functions, name)
end


function traceable_call(func::Union{Func, FExpr, MetaMacro}, args::Any...)
    println("Calling function: ", func.name, " with arguments: ", args[1:end-2])
    res = func.body(args...)
    println("Function ", func.name, " returned: ", res)
    return res
end


# --------------------------------------------------------------------------- #
# ------------------------------- Auxiliaries ------------------------------- #
# --------------------------------------------------------------------------- #


function is_primitive(expr::Expr, env::Env)
    return false
end


function is_primitive(expr::Symbol, env::Env)
    val = get_value(env, expr)  # Tries to fetch the value of the symbol from the environment

    if val === nothing
        x = getfield(Base, expr)  # Fetches the primitive function from the Base module
        return x !== nothing
    else
        return false
    end
end


function make_function(args::Any, body::Expr, env::Env, name::Symbol=:())

    # 1. Creates a new scope for the function
    scope = extend_env(env)

    # 1. Creates a new function
    func = (params...) -> begin
        call_env = params[end - 1]
        def_env = params[end]
        params = params[1:end-2]

        # 1.1. Contrary to the make_fexpr, we need to evaluate the arguments
        evaled_params = [eval_expr(param, call_env) for param in params]

        # 1.2. Takes the arguments and binds them to the function parameters
        bindings = Dict{Symbol,Any}(zip(args, evaled_params))

        # 1.3. Before evaluating the body, we extend the function scope with the bindings
        for (var, value) in bindings
            set_value!(def_env, var, value)
        end

        # 1.4. Evaluates the body in the function scope
        eval_expr(body, def_env)
    end

    f = Func(name, args, func, scope)

    # 2. Return the function
    return f
end


# --------------------------------------------------------------------------- #
# --------------------------- Statement Handling ---------------------------- #
# --------------------------------------------------------------------------- #


function handle_call(expr::Expr, env::Env)
    func_name = expr.args[1]
    func_args = expr.args[2:end]

    # 1. Extracts the function expression from the environment
    func = eval_expr(func_name, env)

    # 2. If we are trying to evaluate an expression inside a fexpr, we need to evaluate it
    if isa(func, CallScopedEval)
        return call_scoped_eval(func)(func_args[1])
    end

    # 3. If we have a primitive function, we need to evaluate the arguments and call it
    if is_primitive(func_name, env)
        func_args = [eval_expr(arg, env) for arg in func_args]
        res = func(func_args...)
        return res
    end

    # 4. If we are in a global scope, calls the function/fexpr with the evaluated arguments
    if is_traceable(func_name)
        return traceable_call(func, func_args..., env, func.scope)
    end
    res = func.body(func_args..., env, func.scope)
    return res
end


function handle_if(expr::Expr, env::Env)
    cond = eval_expr(expr.args[1], env)
    if cond
        return eval_expr(expr.args[2], env)  # True branch
    elseif length(expr.args) > 2 # If there is an else branch
        return eval_expr(expr.args[3], env)  # False branch
    end
    return false
end


function handle_and(expr::Expr, env::Env)
    val = true
    for arg in expr.args
        val = eval_expr(arg, env)
        if val == false  # An expression can evaluate to something other than a boolean
            return false
        end
    end
    return val
end


function handle_or(expr::Expr, env::Env)
    val = false
    for arg in expr.args
        val = eval_expr(arg, env)
        if val != false  # An expression can evaluate to something other than a boolean
            return val
        end
    end
    return false
end


function handle_block(expr::Expr, env::Env)

    if (length(expr.args) == 0)
        return nothing
    end

    vals = [eval_expr(arg, env) for arg in expr.args]
    return vals[end]
end


function handle_assignment(expr::Expr, eval_env::Env, storing_env::Env)
    lhs = expr.args[1]
    rhs = expr.args[2]

    # 1. Check if we are assigning to a variable or a function
    is_func_def = isa(lhs, Expr) && lhs.head == :call

    # 2. Handle the assignment accordingly
    var, value = nothing, nothing
    if is_func_def
        fn_name = lhs.args[1]
        args = lhs.args[2:end]
        body = rhs
        func = make_function(args, body, eval_env, fn_name)

        var = fn_name
        value = func
    else
        var = lhs
        value = eval_expr(rhs, eval_env)  # Evaluate the right-hand side to obtain the value
    end

    # 3. Store the value in the environment
    set_value!(storing_env, var, value)

    # 4. Return the value of the expression (right-hand side)
    return value
end


function handle_let(expr::Expr, old_env::Env)
    assignments = expr.args[1]
    body = expr.args[2]

    # 1. Create a new environment with the old one as parent
    new_env = extend_env(old_env)

    # 2. Evaluate the assignments in the new environment
    eval_expr(assignments, new_env)

    # 3. Evaluate the body in the new environment
    val = eval_expr(body, new_env)

    # 4. Return the result of the body block
    return val
end


function handle_anonymous_function(expr::Expr, env::Env)
    args = expr.args[1]
    body = expr.args[2]

    # 1. Makes sure the arguments are a vector of symbols
    args = isa(args, Symbol) ? [args] : args.args

    # 2. Creates a function 
    func = make_function(args, body, env, :anonymous)

    # 3. Returns the function
    return func
end


function handle_global(expr::Expr, env::Env)
    val = nothing
    for arg in expr.args
        if arg.head === :(=)
            val = handle_assignment(arg, env, global_env)
        elseif arg.head === :(:=)
            val = handle_fexpr(arg, env, global_env)
        else
            throw(ArgumentError("Invalid global statement"))
        end
    end
    return val
end


function handle_quote(expr::Expr, env::Env)
    expressions = expr.args

    # 1. If there are no expressions, return nothing
    if length(expressions) == 0
        return nothing
    end

    # 2. A quote block is basically a block of expressions that need
    # to be evaluated in the current environment
    vals = [eval_expr(arg, env) for arg in expressions]

    # 3. Return the last value
    return vals[end]
end


# --------------------------------------------------------------------------- #
# -------------------------- Evaluate Expressions --------------------------- #
# --------------------------------------------------------------------------- #


function eval_expr(expr::Symbol, env::Env)
    val = get_value(env, expr)  # Tries to fetch the value of the symbol from the environment

    if val === nothing
        getfield(Base, expr)  # Fetches the primitive function from the Base module
    else
        val  # Returns the value from the environment
    end
end


function eval_expr(expr::QuoteNode, env::Env)
    expr.value
end


function eval_expr(expr::Number, env::Env)
    expr
end


function eval_expr(expr::String, env::Env)
    expr
end


# Print empty line to not crash the REPL
function eval_expr(expr::Nothing, env::Env)
    ""
end


# LineNumberNode to skip
function eval_expr(expr::LineNumberNode, env::Env)
    nothing
end


function eval_expr(expr::Expr, env::Env)
    if expr.head === :call
        handle_call(expr, env)
    elseif expr.head === :if || expr.head === :elseif
        handle_if(expr, env)
    elseif expr.head === :let
        handle_let(expr, env)
    elseif expr.head === :(=)
        handle_assignment(expr, env, env)
    elseif expr.head === :(:=)
        handle_fexpr(expr, env, env)
    elseif expr.head === :global
        handle_global(expr, env)
    elseif expr.head === :$=
        return handle_macro(expr, env, env)
    elseif expr.head === :$
        return handle_interpolation(expr, env)
    elseif expr.head === :block || expr.head === :toplevel
        handle_block(expr, env)
    elseif expr.head === :&&
        handle_and(expr, env)
    elseif expr.head === :||
        handle_or(expr, env)
    elseif expr.head === :->
        handle_anonymous_function(expr, env)
    elseif expr.head === :quote
        handle_quote(expr, env)
    else
        # All other expressions should be collections of sub-expressions in an environment
        # and so, we do a broadcast to apply the function element-wise over the collection of expressions.
        eval_expr.(expr.args, Ref(env))
    end
end
