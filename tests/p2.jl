include("../src/main.jl")
using Test

# We do this renaming to make it easier to test
fn = metajulia_eval

@testset verbose = true "Part 2" begin
    @testset verbose = true "Identity functions" begin
        @test fn(:(
            identity_function(x) = x;
            identity_function(1 + 2)
        )) == 3
        @test fn(:(
            identity_fexpr(x) := x;
            identity_fexpr(1 + 2)
        )) == :(1 + 2)
    end

    @testset verbose = true "Eval is evaluated in the call scope" begin
        @test fn(:(
            debug(expr) := 
                let r = eval(expr);
                    s = "" + expr + " => " + r
                    return s
                end ;
            let x = 1
                1 + debug(x + 1)
            end
        )) == "x + 1 => 2"
        @test fn(:(
            let a = 1
                global puzzle(x) :=
                    let b = 2
                        eval(x) + a + b
                    end 
            end;
            let a = 3, b = 4
                puzzle(a + b)
            end
        )) == 10
        @test fn(:(
            let a = 1
                global puzzle(x) :=
                    let b = 2
                        eval(x) + a + b
                    end 
            end;
            let eval = 123
                puzzle(eval)
            end
        )) == 126
    end

    @testset verbose = true "Control flow" begin
        @test fn(:(
            when(condition, action) := eval(condition) ? eval(action) : false;
            show_sign(n) =
                begin
                    when(n > 0, println("Positive"))
                    when(n < 0, println("Negative"))
                    n
                end;
            show_sign(3)
        )) == "Positive"
        @test fn(:(
            when(condition, action) := eval(condition) ? eval(action) : false;
            show_sign(n) =
                begin
                    when(n > 0, println("Positive"))
                    when(n < 0, println("Negative"))
                    n
                end;
            show_sign(-3)
        )) == "Negative"
        @test fn(:(
            when(condition, action) := eval(condition) ? eval(action) : false;
            show_sign(n) =
                begin
                    when(n > 0, println("Positive"))
                    when(n < 0, println("Negative"))
                    n
                end;
            show_sign(0)
        )) == 0
    end

    @testset verbose = true "Repeating actions" begin
        @test fn(:(
            repeat_until(condition, action) :=
                let ;
                loop() = (eval(action); eval(condition) ? false : loop())
                loop()
            end;
            let n = 4, vals = []
                repeat_until(n == 0, (append!(vals, n); n = n - 1))
                vals
            end
        )) == [4, 3, 2, 1]
    end

    @testset verbose = true "Access local scopes" begin
        @test fn(:(
            mystery() := eval;
            let a = 1, b = 2
                mystery()(:(a + b))
            end
        )) == 3
        @test fn(:(
            mystery() := eval;
            let a = 1, b = 2
                global eval_here = mystery()
            end;
            let a = 3, b = 4
                global eval_there = mystery()
            end;
            eval_here(:(a + b)) + eval_there(:(a + b))
        )) == 10
    end
end
