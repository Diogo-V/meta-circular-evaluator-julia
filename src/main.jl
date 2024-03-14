# --------------------------------------------------------------------------- #
# ------------------------- Environment Management -------------------------- #
# --------------------------------------------------------------------------- #


struct Env
    vars::Dict{Symbol,Any}
    parent::Union{Nothing,Env}
end


global_env = Env(Dict{Symbol,Any}(), nothing)


# Function to extend an environment by creating a new sub-environment
function extend_env(parent_env::Env)
    return Env(Dict{Symbol,Any}(), parent_env)
end


function extend_env(parent_env::Env, vars::AbstractDict{Symbol,Any})
    new_vars = Dict{Symbol,Any}(vars)
    return Env(new_vars, parent_env)
end


function extend_env(env::Env, vars::Dict{Symbol,Any})
    new_env = Env(vars, env)
    return new_env
end


# This is a debugging function to print the arguments of a function
function print_args(args)
    count = 1
    for arg in args
        println("Argument $count head: $(arg.head)")
        println("Argument $count args: $(arg)")
        count += 1
    end
end


function get_value(env::Env, sym::Symbol)
    haskey(env.vars, sym) && return env.vars[sym]
    env.parent === nothing && return nothing
    get_value(env.parent, sym)
end


function set_value!(env::Env, sym::Symbol, val)
    env.vars[sym] = val
end


# --------------------------------------------------------------------------- #
# --------------------------- Statement Handling ---------------------------- #
# --------------------------------------------------------------------------- #


function handle_call(expr::Expr, env::Env)
    f = eval_expr(expr.args[1], env)
    args = [eval_expr(arg, env) for arg in expr.args[2:end]]
    f(args...)
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
    symbol = expr.args[1]

    # If the symbol is a variable
    if isa(symbol, Symbol)
        value = eval_expr(expr.args[2], eval_env)
        set_value!(storing_env, symbol, value)

    elseif isa(symbol, Expr) && symbol.head === :call
        name = symbol.args[1]
        args = symbol.args[2:end]
        body = expr.args[2]

        # Create a new function with the given arguments and body
        func = (args_vals...) -> begin
            new_env = extend_env(eval_env, Dict{Symbol,Any}(zip(args, args_vals)))
            eval_expr(body, new_env)
        end
        set_value!(storing_env, name, func)
        # return the string <function>
        return "<function>"
    end
end


function handle_let(expr::Expr, old_env::Env)
    env = extend_env(old_env)

    vals = [eval_expr(arg, env) for arg in expr.args]

    if isa(vals[end], Symbol)
        return get_value(env, vals[end])
    else
        return vals[end]
    end
end


function handle_anonymous_function(expr::Expr, env::Env)
    args_expr = expr.args[1]
    body_expr = expr.args[2]

    # Make sure args_expr is a collection
    args_expr = isa(args_expr, Symbol) ? [args_expr] : args_expr.args

    anon_func = (args_vals...) -> begin
        # Zip together argument names with values and create a dictionary
        args_dict = Dict{Symbol, Any}()
        for (arg_name, arg_val) in zip(args_expr, args_vals)
            args_dict[arg_name] = arg_val
        end

        # Create a new environment for the anonymous function
        anon_env = extend_env(env, args_dict)
        # Evaluate the body of the anonymous function in the new environment
        eval_expr(body_expr, anon_env)
    end
    return anon_func
end


function handle_global(expr::Expr, env::Env)
    val = nothing
    for arg in expr.args
        if arg.head === :(=)  # Global keywords are always assignments, but we do a 2nd check
            val = handle_assignment(arg, env, global_env)
        end
    end
    return val
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
    if expr.head === :call  # TODO: revisit annonimous functions
        handle_call(expr, env)
    elseif expr.head === :if || expr.head === :elseif
        # Probably this should handle elseif as well
        handle_if(expr, env)
    elseif expr.head === :let
        handle_let(expr, env)
    elseif expr.head === :(=)
        handle_assignment(expr, env, env)
    elseif expr.head === :function
        # TODO: Implement function declaration
        # 1. Create a closure with the current environment
        # 2. Put in the environment
    elseif expr.head === :global
        handle_global(expr, env)
    elseif expr.head === :block || expr.head === :toplevel
        handle_block(expr, env)
    elseif expr.head === :&&
        handle_and(expr, env)
    elseif expr.head === :||
        handle_or(expr, env)
    elseif expr.head === :->
        handle_anonymous_function(expr, env)
    else
        # All other expressions should be collections of sub-expressions in an environment
        # and so, we do a broadcast to apply the function element-wise over the collection of expressions.
        eval_expr.(expr.args, Ref(env))  # TODO: Check if this is the correct way to pass the environment (LineNumberNode)
    end
end


# --------------------------------------------------------------------------- #
# ------------------------------ REPL Functions ----------------------------- #
# --------------------------------------------------------------------------- #


function read_from_stdin()
    lines = []
    while true  # Julia does not have do-while, so we use this trick
        line = readline()
        push!(lines, line)
        line != "" || break
    end
    single_line = join(lines, "\n")
    return single_line
end


function main(text::String, env::Env)
    expr = Meta.parse(text)
    eval_expr(expr, env)
end


function main(expr::Expr, env::Env)
    eval_expr(expr, env)
end


function metajulia_repl()
    env = global_env
    while true
        print(">> ")
        program = read_from_stdin()
        val = main(program, env)
        println(val)
    end
end


function metajulia_eval(expr::Expr)
    main(expr, global_env)
end


function run_test()
    env = global_env
    program = read_from_stdin()
    val = main(program, env)
    println(val)
end


if abspath(PROGRAM_FILE) == @__FILE__
    run_test()
end
