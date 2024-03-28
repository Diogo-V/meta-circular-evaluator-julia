# ------------------------------------------------------------------------------
# lang_def.jl
# This file contains the core implementation of the MetaJulia language, including
# the evaluation of expressions, handling of various language constructs, and
# auxiliary functions.
# ------------------------------------------------------------------------------
include("./env.jl")
include("./fexpr.jl")
include("./macro.jl")


# ------------------------------------------------------------------------------
#                                Structures
# ------------------------------------------------------------------------------


"""
    Func

A structure representing a function in the MetaJulia language.

# Fields
- `name::Symbol`: The name of the function.
- `args::Any`: The arguments of the function.
- `body::Any`: The body of the function.
- `scope::Env`: The environment scope of the function.
"""
struct Func
    name::Symbol
    args::Any
    body::Any
    scope::Env
end


"""
    show(io::IO, p::Func)

Special show method for `Func` objects, printing "<function>" when called.
"""
show(io::IO, p::Func) = print(io, "<function>")


# ------------------------------------------------------------------------------
#                                 Tracing
# ------------------------------------------------------------------------------


"""
    traceable_functions

A dictionary holding the traceable functions in the MetaJulia language.
"""
traceable_functions = Dict{Symbol,Any}()


"""
    register_traceable(func::Any, call_env::Env, def_env::Env)

Register the given `func` as a traceable function in the `traceable_functions` dictionary.
"""
function register_traceable(func::Any, call_env::Env, def_env::Env)
    traceable_functions[func] = func
end


# Register the `register_traceable` function in the global environment to 
# expose it to the MetaJulia language
set_value!(global_env, :register_traceable, Func(:register_traceable, [], register_traceable, global_env))


"""
    is_traceable(name::Any)

Check if the given `name` corresponds to a traceable function.
"""
function is_traceable(name::Any)
    return haskey(traceable_functions, name)
end


"""
    traceable_call(func::Union{Func, FExpr, MetaMacro}, args::Any...)

Call the given `func` (which can be a `Func`, `FExpr`, or `MetaMacro`) with the provided `args`.
Print the function name, arguments, and return value for tracing purposes.
"""
function traceable_call(func::Union{Func, FExpr, MetaMacro}, args::Any...)
    println("Calling function: ", func.name, " with arguments: ", args[1:end-2])
    res = func.body(args...)
    println("Function ", func.name, " returned: ", res)
    return res
end


# ------------------------------------------------------------------------------
#                                Auxiliaries
# ------------------------------------------------------------------------------


"""
    is_primitive(expr::Expr, env::Env)

Check if the given expression `expr` is a primitive function in the provided environment `env`.
Always returns `false` for expressions.
"""
function is_primitive(expr::Expr, env::Env)
    return false
end


"""
    is_primitive(expr::Symbol, env::Env)

Check if the given symbol `expr` represents a primitive function in the provided environment `env`.
If the symbol is not defined in the environment, it checks if it corresponds to a function in the `Base` module.
"""
function is_primitive(expr::Symbol, env::Env)
    val = get_value(env, expr) 

    if val === nothing
        x = getfield(Base, expr)
        return x !== nothing
    else
        return false
    end
end


"""
    make_function(args::Any, body::Expr, env::Env, name::Symbol=:())

Create a new function with the given `args`, `body`, and `name` in the provided environment `env`.
"""
function make_function(args::Any, body::Expr, env::Env, name::Symbol=:())
    scope = extend_env(env)

    func = (params...) -> begin
        call_env = params[end - 1]
        def_env = params[end]
        params = params[1:end-2]

        evaled_params = [eval_expr(param, call_env) for param in params]

        bindings = Dict{Symbol,Any}(zip(args, evaled_params))

        for (var, value) in bindings
            set_value!(def_env, var, value)
        end

        eval_expr(body, def_env)
    end

    f = Func(name, args, func, scope)
    return f
end


# ------------------------------------------------------------------------------
#                           Statement Handling
# ------------------------------------------------------------------------------


"""
    handle_call(expr::Expr, env::Env)

Handle a function call expression `expr` in the given environment `env`.
Evaluates the function and its arguments, and performs the appropriate call based on the function type.
"""
function handle_call(expr::Expr, env::Env)
    func_name = expr.args[1]
    func_args = expr.args[2:end]

    func = eval_expr(func_name, env)

    # If we are trying to evaluate an expression inside a fexpr, we need to evaluate it
    if isa(func, CallScopedEval)
        return call_scoped_eval(func)(func_args[1])
    end

    # If we have a primitive function, we need to evaluate the arguments and call it
    if is_primitive(func_name, env)
        func_args = [eval_expr(arg, env) for arg in func_args]
        res = func(func_args...)
        return res
    end

    # If we have a traceable function, we need to call it with tracing
    if is_traceable(func_name)
        return traceable_call(func, func_args..., env, func.scope)
    end

    res = func.body(func_args..., env, func.scope)
    return res
end


"""
    handle_if(expr::Expr, env::Env)

Handle an if-else expression `expr` in the given environment `env`.
Evaluates the condition and executes the corresponding branch.
"""
function handle_if(expr::Expr, env::Env)
    cond = eval_expr(expr.args[1], env)
    if cond
        return eval_expr(expr.args[2], env)
    elseif length(expr.args) > 2
        return eval_expr(expr.args[3], env)
    end
    return false
end


"""
    handle_and(expr::Expr, env::Env)

Handle a logical AND expression `expr` in the given environment `env`.
Evaluates each argument and returns `false` if any argument evaluates to `false`.
"""
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


"""
    handle_or(expr::Expr, env::Env)

Handle a logical OR expression `expr` in the given environment `env`.
Evaluates each argument and returns the first non-false value.
"""
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


"""
    handle_block(expr::Expr, env::Env)

Handle a block of expressions `expr` in the given environment `env`.
Evaluates each expression and returns the value of the last expression.
"""
function handle_block(expr::Expr, env::Env)
    if (length(expr.args) == 0)
        return nothing
    end

    vals = [eval_expr(arg, env) for arg in expr.args]
    return vals[end]
end


"""
    handle_assignment(expr::Expr, eval_env::Env, storing_env::Env)

Handle an assignment expression `expr` in the given `eval_env` and `storing_env` environments.
Evaluates the right-hand side and assigns the value to the left-hand side variable or function.
"""
function handle_assignment(expr::Expr, eval_env::Env, storing_env::Env)
    lhs = expr.args[1]
    rhs = expr.args[2]

    # Check if we are assigning to a variable or a function
    is_func_def = isa(lhs, Expr) && lhs.head == :call

    # Handle the assignment accordingly
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
        value = eval_expr(rhs, eval_env)
    end

    set_value!(storing_env, var, value)
    return value
end


"""
    handle_let(expr::Expr, old_env::Env)

Handle a let expression `expr` in the given `old_env` environment.
Creates a new environment with the assignments from the let statement, evaluates the body,
and returns the result.
"""
function handle_let(expr::Expr, old_env::Env)
    assignments = expr.args[1]
    body = expr.args[2]

    new_env = extend_env(old_env)

    eval_expr(assignments, new_env)

    val = eval_expr(body, new_env)
    return val
end


"""
    handle_anonymous_function(expr::Expr, env::Env)

Handle an anonymous function expression `expr` in the given environment `env`.
Creates a new function with the provided arguments and body.
"""
function handle_anonymous_function(expr::Expr, env::Env)
    args = expr.args[1]
    body = expr.args[2]

    args = isa(args, Symbol) ? [args] : args.args

    func = make_function(args, body, env, :anonymous)
    return func
end


"""
    handle_global(expr::Expr, env::Env)

Handle a global expression `expr` in the given environment `env`.
Evaluates assignments and function definitions in the global environment.
"""
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


"""
    handle_quote(expr::Expr, env::Env)

Handle a quote expression `expr` in the given environment `env`.
Evaluates each expression within the quote block and returns the last value.
"""
function handle_quote(expr::Expr, env::Env)
    expressions = expr.args

    if length(expressions) == 0
        return nothing
    end

    # A quote block is basically a block of expressions that need
    # to be evaluated in the current environment
    vals = [eval_expr(arg, env) for arg in expressions]

    return vals[end]
end


# ------------------------------------------------------------------------------
#                        Evaluate Expressions
# ------------------------------------------------------------------------------


"""
    eval_expr(expr::Symbol, env::Env)

Evaluate a symbol expression `expr` in the given environment `env`.
If the symbol is defined in the environment, returns its value.
Otherwise, checks if it corresponds to a primitive function in the `Base` module.
"""
function eval_expr(expr::Symbol, env::Env)
    val = get_value(env, expr)

    if val === nothing
        getfield(Base, expr)
    else
        val
    end
end


"""
    eval_expr(expr::QuoteNode, env::Env)

Evaluate a quoted expression `expr` in the given environment `env`.
Returns the value of the quoted expression without evaluating it.
"""
function eval_expr(expr::QuoteNode, env::Env)
    expr.value
end


"""
    eval_expr(expr::Number, env::Env)

Evaluate a numeric expression `expr` in the given environment `env`.
Returns the numeric value without any evaluation.
"""
function eval_expr(expr::Number, env::Env)
    expr
end


"""
    eval_expr(expr::String, env::Env)

Evaluate a string expression `expr` in the given environment `env`.
Returns the string value without any evaluation.
"""
function eval_expr(expr::String, env::Env)
    expr
end


"""
    eval_expr(expr::Nothing, env::Env)

Evaluate a `nothing` expression `expr` in the given environment `env`.
Returns an empty string to avoid crashing the REPL.
"""
function eval_expr(expr::Nothing, env::Env)
    ""
end


"""
    eval_expr(expr::LineNumberNode, env::Env)

Evaluate a line number node expression `expr` in the given environment `env`.
Returns `nothing` as line number nodes are skipped during evaluation.
"""
function eval_expr(expr::LineNumberNode, env::Env)
    nothing
end


"""
    eval_expr(expr::Expr, env::Env)

Evaluate an expression `expr` in the given environment `env`.
Dispatches the expression to the appropriate handler based on the expression head.
"""
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
