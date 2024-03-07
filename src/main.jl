# Define basic data structures
struct Env
    vars::Dict{Symbol,Any}
    parent::Union{Nothing,Env}
end

global_env = Env(Dict{Symbol,Any}(), nothing)

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

# Evaluation functions
function eval_expr(expr::Symbol, env::Env)
    val = get_value(env, expr)  # Tries to fetch the value of the symbol from the environment
    if val === nothing 
        getfield(Base, expr)  # Fetches the primitive function from the Base module
    else
        val 
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

function eval_expr(expr::Expr, env::Env)
    if expr.head === :call
        handle_call(expr, env)
    elseif expr.head === :if
        # TODO: Implement if-else
    elseif expr.head === :let
        # TODO: Implement let
    else
        # All other expressions should be collections of sub-expressions in an environment
        # and so, we do a broadcast to apply the function element-wise over the collection of expressions.
        eval_expr.(expr.args, Ref(env))  
    end
end

# REPL
function metajulia_repl()
    env = global_env
    while true
        print(">> ")
        line = readline()
        expr = Meta.parse(line)
        val = eval_expr(expr, env)
        println(val)
    end
end
