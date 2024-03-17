# --------------------------------------------------------------------------- #
# ------------------------- Environment Management -------------------------- #
# --------------------------------------------------------------------------- #


struct Env
    vars::Dict{Symbol,Any}
    parent::Union{Nothing,Env}
end


function extend_env(parent_env::Env)
    return Env(Dict{Symbol,Any}(), parent_env)
end


function extend_env(env::Env, vars::Dict{Symbol,Any})
    new_env = Env(vars, env)
    return new_env
end


function get_value(env::Env, sym::Symbol)
    haskey(env.vars, sym) && return env.vars[sym]
    env.parent === nothing && return nothing  # TODO(diogo): This is an error case
    get_value(env.parent, sym)
end


function set_value!(env::Env, sym::Symbol, val::Any)
    env.vars[sym] = val
end


global_env = Env(Dict{Symbol,Any}(), nothing)


# --------------------------------------------------------------------------- #
# ------------------------------- Auxiliaries ------------------------------- #
# --------------------------------------------------------------------------- #


function handle_make_function(args::Any, body::Expr, env::Env)
    # 1. Creates a new environment for the function (is the function scope)
    scope = extend_env(env)

    # 2. Creates a new function
    func = (params...) -> begin
        # 2.1. Takes the arguments and binds them to the function parameters
        bindings = Dict{Symbol,Any}(zip(args, params))

        # 2.2. Before evaluating the body, we extend the function scope with the bindings
        for (var, value) in bindings
            set_value!(scope, var, value)
        end

        # 2.3. Evaluates the body in the function scope
        eval_expr(body, scope)
    end

    # 3. Return the function
    return func
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
        func = handle_make_function(args, body, eval_env)

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
    func = handle_make_function(args, body, env)

    # 3. Returns the function
    return func
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
    if expr.head === :call
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


# --------------------------------------------------------------------------- #

s = :(
begin
    incr() =
        let priv_counter = 0
            priv_counter = priv_counter + 1
        end
    incr()
    incr()
    incr()
end      
)

metajulia_eval(s)