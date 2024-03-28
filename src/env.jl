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
