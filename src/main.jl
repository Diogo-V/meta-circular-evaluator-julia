# ------------------------------------------------------------------------------
# lang_def.jl
# This file contains the implementation of the MetaJulia REPL.
# ------------------------------------------------------------------------------
include("./lang_def.jl") # Include the language definition


# ------------------------------------------------------------------------------
#                            REPL Functions
# ------------------------------------------------------------------------------


"""
    read_from_stdin()

Read input from the standard input (stdin) until an empty line is encountered.
Returns the input as a single string.
"""
function read_from_stdin()
    lines = []
    while true # Julia does not have do-while, so we use this trick
        line = readline()
        push!(lines, line)
        line != "" || break
    end
    single_line = join(lines, "\\n")
    return single_line
end


"""
    main(text::String, env::Env)

Parse and evaluate the given string `text` in the provided environment `env`.
"""
function main(text::String, env::Env)
    expr = Meta.parse(text)
    eval_expr(expr, env)
end


"""
    main(expr::Any, env::Env)

Evaluate the given expression `expr` in the provided environment `env`.
"""
function main(expr::Any, env::Env)
    eval_expr(expr, env)
end


"""
    metajulia_repl()

Start the MetaJulia REPL (Read-Eval-Print Loop).
Prompts the user for input, evaluates the input, and prints the result.
"""
function metajulia_repl()
    env = global_env
    while true
        print(">> ")
        program = read_from_stdin()
        val = main(program, env)
        println(val)
    end
end


"""
    metajulia_eval(expr::Any)

Evaluate the given expression `expr` in the global environment.
If `expr` is an `Expr`, it is parsed and evaluated using `main`.
Otherwise, it is evaluated directly using `eval_expr`.
"""
function metajulia_eval(expr::Any)
    if isa(expr, Expr)
        return main(expr, global_env)
    else
        return eval_expr(expr, global_env)
    end
end
