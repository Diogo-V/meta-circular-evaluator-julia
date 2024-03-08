# Define basic data structures
struct Env
    vars::Dict{Symbol,Any}
    parent::Union{Nothing,Env}
end


global_env = Env(Dict{Symbol,Any}(), nothing)

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


function extend_env(env::Env, vars::Dict{Symbol,Any})
    new_env = Env(vars, env)
    return new_env
end


# Handle different expression
function handle_call(expr::Expr, env::Env)
    f = eval_expr(expr.args[1], env)
    args = [eval_expr(arg, env) for arg in expr.args[2:end]]
    f(args...)
end


function handle_if(expr::Expr, env::Env)
    cond = eval_expr(expr.args[1], env)  
    # print_args(expr.args) # <- Debugging
    if cond
        return eval_expr(expr.args[2], env)  # True branch
    elseif length(expr.args) > 2 # If there is an else branch
        return eval_expr(expr.args[3], env)  # False branch
    end
    return false
end


function handle_and(expr::Expr, env::Env)
    for arg in expr.args
        val = eval_expr(arg, env)
        if !val
            return false
        end
    end
    return true
end

function handle_or(expr::Expr, env::Env)
    for arg in expr.args
        val = eval_expr(arg, env)
        if val
            return true
        end
    end
    return false
end






function handle_block(expr::Expr, env::Env)
    vals = [eval_expr(arg, env) for arg in expr.args]
    return vals[end]
end


# Evaluation functions
function eval_expr(expr::Symbol, env::Env)
    val = get_value(env, expr)  # Tries to fetch the value of the symbol from the environment

    if val === nothing
        getfield(Base, expr)  # Fetches the primitive function from the Base module
    else
        expr  # NOTE(diogo): This is an error case
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
        # TODO: Implement let
        # 1. Evaluate all the declared variables <- careful with function declaration
        # 2. Put in the environment
        # 3. Evaluate the body
    elseif expr.head === :(=)
        # TODO: Implement assignment
        # 1. Evaluate the right-hand side
        # 2. Assign to the left-hand side by putting in the environment
    elseif expr.head === :function
        # TODO: Implement function declaration
        # 1. Create a closure with the current environment
        # 2. Put in the environment
    elseif expr.head === :begin  # TODO: Check if this is relevant 
        # TODO: Implement begin
        # 1. Evaluate all the expressions in order
        # 2. Return the last one

        # Probably we can use the block handler for this
        # and not sure if there exists a begin head

    elseif expr.head === :global
        # TODO: Implement global
        # 1. Evaluate the expression
        # 2. Put in the global environment
    elseif expr.head === :block
        handle_block(expr, env)
    elseif expr.head === :(&&)
        handle_and(expr, env)
    elseif expr.head === :(||)
        handle_or(expr, env)
    else
        # All other expressions should be collections of sub-expressions in an environment
        # and so, we do a broadcast to apply the function element-wise over the collection of expressions.
        eval_expr.(expr.args, Ref(env))  # TODO: Check if this is the correct way to pass the environment (LineNumberNode)
    end
end


function main(text::String, env::Env)
    expr = Meta.parse(text)
    # println(expr) # <- Debugging
    eval_expr(expr, env)
end


# REPL
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

function metajulia_repl()
    env = global_env
    while true
        print(">> ")
        program = read_from_stdin()
        val = main(program, env)
        println(val)
    end
end

# For tests
function run_test()
    env = global_env
    program = read_from_stdin()
    val = main(program, env)
    println(val)
end


if abspath(PROGRAM_FILE) == @__FILE__
    run_test()
end
