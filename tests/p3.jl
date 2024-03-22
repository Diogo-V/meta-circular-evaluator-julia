include("../src/main.jl")
using Test

# We do this renaming to make it easier to test
fn = metajulia_eval

@testset verbose = true "Part 3" begin
    @testset verbose = true "Absolute function in imperative style" begin
        @test fn(:(
            when(condition, action) $= :($condition ? $action : false);
            abs(x) = (when(x < 0, (x = -x;)); x);
            abs(-5)
        )) == 5
        @test fn(:(
            when(condition, action) $= :($condition ? $action : false);
            abs(x) = (when(x < 0, (x = -x;)); x);
            abs(5)
        )) == 5
    end

    @testset verbose = true "Can do repeated actions" begin
        @test fn(:(
            repeat_until(condition, action) $=
                :(let ;
                    loop() = ($action; $condition ? false : loop())
                    loop() 
                end) ;
            let n = 4, vals = []
                repeat_until(n == 0, (push!(vals, n); n = n - 1))
            end
        )) == [4, 3, 2, 1, false]
    end

    @testset verbose = true "Gensym blocks variable shadowing" begin
        @test fn(:(
            repeat_until(condition, action) $=
                let loop = gensym()
                    :(let ;
                        $loop() = ($action; $condition ? false : $loop())
                        $loop()
                    end) 
                end;
            let loop = "I'm looping!", i = 3, vals = []
                repeat_until(i == 0, (push!(vals, loop); i = i - 1))
            end
        )) == ["I'm looping!", "I'm looping!", "I'm looping!", false]
    end
end
