# ------------------------------------------------------------------------------
# env.jl
# This file contains the implementation of the environment structure and related
# functions for managing variable scopes and bindings.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
#                                Structures
# ------------------------------------------------------------------------------


"""
    Env

A structure representing an environment for storing variable bindings.

# Fields
- `vars::Dict{Symbol,Any}`: A dictionary mapping variable names (symbols) to their values.
- `parent::Union{Nothing,Env}`: A reference to the parent environment, or `nothing` for the global environment.
"""
struct Env
    vars::Dict{Symbol,Any}
    parent::Union{Nothing,Env}
end


"""
    extend_env(parent_env::Env)

Create a new environment with an empty variable dictionary, inheriting from the given `parent_env`.
"""
function extend_env(parent_env::Env)
    return Env(Dict{Symbol,Any}(), parent_env)
end


"""
    extend_env(env::Env, vars::Dict{Symbol,Any})

Create a new environment with the given `vars` dictionary, inheriting from the provided `env`.
"""
function extend_env(env::Env, vars::Dict{Symbol,Any})
    new_env = Env(vars, env)
    return new_env
end


"""
    get_value(env::Env, sym::Symbol)

Retrieve the value associated with the given symbol `sym` in the environment `env`.
If the symbol is not found in the current environment, the search continues in the parent environment.
If the symbol is not found in any environment, `nothing` is returned.
"""
function get_value(env::Env, sym::Symbol)
    haskey(env.vars, sym) && return env.vars[sym]
    env.parent === nothing && return nothing
    get_value(env.parent, sym)
end


"""
    set_value!(env::Env, sym::Symbol, val::Any)

Set the value `val` associated with the given symbol `sym` in the environment `env`.
If the symbol is already defined in an environment higher in the chain, its value is updated.
If the symbol is not defined in any environment, it is defined in the current environment.
"""
function set_value!(env::Env, sym::Symbol, val::Any)

    # In case we are trying to set a value in the global environment
    # we do not need to traverse the environment chain
    if env === global_env
        env.vars[sym] = val
        return
    end

    tmp = env
    while tmp !== nothing
        if haskey(tmp.vars, sym) && tmp !== global_env
            tmp.vars[sym] = val
            return
        end
        tmp = tmp.parent
    end

    env.vars[sym] = val
end


"""
    global_env

The global environment, which is the root of the environment hierarchy.
"""
global_env = Env(Dict{Symbol,Any}(), nothing)
