# --------------------------------------------------------------------------- #
# ------------------------- Environment Management -------------------------- #
# --------------------------------------------------------------------------- #


struct Env
    vars::Dict{Symbol,Any}
    parent::Union{Nothing,Env}
end


struct Function
    args::Any      # Contains the arguments of the function
    body::Any      # Contains the body of the function
    scope::Env     # Contains an environment which is an extension of the calling environment
end
show(io::IO, p::Function) = print(io, "<function>")


struct FExpr
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


struct MetaMacro
    args::Any
    body::Any
    scope::Env
end
show(io::IO, p::MetaMacro) = print(io, "<macro>")


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

    if env === global_env
        env.vars[sym] = val
        return
    end

    # 1. We iterate over the environment chain to find the first environment where the symbol is defined
    tmp = env
    while tmp !== nothing
        if haskey(tmp.vars, sym) && tmp !== global_env
            tmp.vars[sym] = val
            return
        end
        tmp = tmp.parent
    end

    # 2. If the symbol is not defined in any environment, we define it in the first one
    env.vars[sym] = val
end


global_env = Env(Dict{Symbol,Any}(), nothing)


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


function make_function(args::Any, body::Expr, env::Env)

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

    f = Function(args, func, scope)

    # 2. Return the function
    return f
end


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


function make_fexpr(args::Any, body::Union{Expr, Symbol}, env::Env)

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

    func = FExpr(args, func, scope)

    # 2. Return the function
    return func
end


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


function make_macro(args::Any, body::Union{Expr, Symbol}, env::Env)

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

    func = MetaMacro(args, func, scope)

    # 2. Return the function
    return func
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
        func = make_function(args, body, eval_env)

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


function handle_fexpr(expr::Expr, eval_env::Env, storing_env::Env)
    signature = expr.args[1]
    body = expr.args[2]
    fn_name = signature.args[1]
    args = signature.args[2:end]

    # 1. Makes sure the arguments are a vector of symbols
    args = isa(args, Symbol) ? [args] : args

    # 2. Creates a function 
    func = make_fexpr(args, body, eval_env)

    # 3. Stores the function in the environment
    set_value!(storing_env, fn_name, func)

    # 4. Returns the function
    return func
end


function handle_macro(expr::Expr, eval_env::Env, storing_env::Env)
    signature = expr.args[1]
    body = expr.args[2]
    macro_name = signature.args[1]
    args = signature.args[2:end]

    # 1. Makes sure the arguments are a vector of symbols
    args = isa(args, Symbol) ? [args] : args

    # 2. Creates a macro
    mac = make_macro(args, body, eval_env)

    # 3. Stores the macro in the environment
    set_value!(storing_env, macro_name, mac)

    # 4. Returns the macro
    return mac
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
    func = make_function(args, body, env)

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


function handle_interpolation(expr::Expr, env::Env)
    sym = expr.args[end]

    # 1. Fetches the value of the symbol that is going to be interpolated
    # from the environment
    val = get_value(env, sym)

    # 2. Returns the value of the symbol without evaluating it
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


function main(expr::Any, env::Env)
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


function metajulia_eval(expr::Any)
    if isa(expr, Expr)
        return main(expr, global_env)
    else
        return eval_expr(expr, global_env)
    end
end
