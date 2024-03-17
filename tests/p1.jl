include("../src/main.jl")
using Test

# We do this renaming to make it easier to test
fn = metajulia_eval

@testset verbose = true "Part 1" begin
    @testset verbose = true "Primitives" begin
        @test fn(:(1 + 2)) == 3
        @test fn(:(1 - 2)) == -1
        @test fn(:(1 * 2)) == 2
        @test fn(:(1 / 2)) == 0.5
        @test fn(:((2 + 3)*(4 + 5))) == 45
        @test fn(:((2 + 3)*(4 + 5) + 1)) == 46
    end
    
    @testset verbose = true "Single conditions" begin
        @test fn(:(1 == 1)) == true
        @test fn(:(1 == 2)) == false
        @test fn(:(1 != 1)) == false
        @test fn(:(1 != 2)) == true
        @test fn(:(1 < 2)) == true
        @test fn(:(1 > 2)) == false
        @test fn(:(1 <= 2)) == true
        @test fn(:(1 >= 2)) == false
    end

    @testset verbose = true "Chained conditions" begin
        @test fn(:(1 == 1 && 2 == 2)) == true
        @test fn(:(1 == 1 && 2 == 3)) == false
        @test fn(:(1 == 1 || 2 == 2)) == true
        @test fn(:(1 == 1 || 2 == 3)) == true
        @test fn(:(1 == 2 || 2 == 3)) == false
    end

    @testset verbose = true "Short circuit conditions" begin
        @test fn(:(
            begin
                quotient_or_false(a, b) = !(b == 0) && a/b
                quotient_or_false(6, 2)
            end
        )) == 3.0
        @test fn(:(
            begin
                quotient_or_false(a, b) = !(b == 0) && a/b
                quotient_or_false(6, 0)
            end
        )) == false
        @test fn(:(
            begin
                quotient_or_true(a, b) = b == 0 || a/b
                quotient_or_true(6, 0)
            end
        )) == true
        @test fn(:(
            begin
                quotient_or_true(a, b) = b == 0 || a/b
                quotient_or_true(6, 2)
            end
        )) == 3.0
    end

    @testset verbose = true "If statements" begin
        @test fn(:(3 > 2 ? 1 : 0)) == 1
        @test fn(:(3 < 2 ? 1 : 0)) == 0
        @test fn(:(
            if 3 > 2 
                1
            else
                0
            end
        )) == 1
        @test fn(:(
            if 3 < 2
                1
            elseif 2 > 3
                2
            else
                0
            end
        )) == 0
    end

    @testset verbose = true "Blocks" begin
        @test fn(:((1 + 2; 2 * 3; 3 / 4))) == 0.75
        @test fn(:(begin 1 + 2; 2 * 3; 3 / 4 end)) == 0.75
    end

    @testset verbose = true "Assignments" begin
        @test fn(:(x = 1; x)) == 1
        @test fn(:(x = 2; x * 3)) == 6
        @test fn(:(a = 1; b = 2; a + b)) == 3
    end

    @testset verbose = true "Functions" begin
        @test fn(:(f(x) = x + 1; f(2))) == 3
        @test fn(:(f(x) = x + 1; f(2) + 1)) == 4
        @test fn(:(x(y) = y + 1; x(1))) == 2
        @test fn(:(a = 1; x(y, z) = y + z; x(1, a))) == 2
    end

    @testset verbose = true "Let assignments" begin
        @test fn(:(let x = 1; x end)) == 1
        @test fn(:(let x = 2; x * 3 end)) == 6
        @test fn(:(let a = 1, b = 2; let a = 3; a + b end end)) == 5
        @test fn(:(
            let a = 1
                a + 2
            end
        )) == 3
    end

    @testset verbose = true "Let functions" begin
        @test fn(:(let f(x) = x + 1; f(2) end)) == 3
        @test fn(:(let f(x) = x + 1; let f(x) = x + 2; f(2) end end)) == 4
        @test fn(:(let f(x) = x + 1; let f(x) = x + 2; f(2) end end)) == 4
        @test fn(:(let x(y) = y + 1; x(1) end)) == 2
        @test fn(:(let x(y, z) = y + z; x(1,2) end)) == 3
        @test fn(:(let x = 1, y(x) = x + 1; y(x + 1) end)) == 3
    end

    @testset verbose = true "Let creates scope" begin
        @test fn(:(
            baz = 3;
            let x = 0
                baz = 5
            end + baz
        )) == 8
        @test fn(:(
            baz = 3;
            let ; 
                baz = 6 
            end + baz
        )) == 9
    end

    @testset verbose = true "Higher order functions" begin
        @test fn(:(
            triple(x) = x * 3;
            sum(f, a, b) = a > b ? 0 : f(a) + sum(f, a + 1, b);
            sum(triple, 1, 10)
        )) == 165
    end

    @testset verbose = true "Annonymous functions" begin
        @test fn(:((x -> x + 1)(2))) == 3
        @test fn(:((x -> x + 1)(2) + 1)) == 4
        @test fn(:((x -> x + 1)(2) + (y -> y + 1)(1))) == 5
        @test fn(:((x -> x + 1)(2) + (y -> y + 1)(1) + (z -> z + 1)(0))) == 6
        @test fn(:((() -> 5)())) == 5
        @test fn(:(((x, y) -> x + y)(1, 2))) == 3
        @test fn(:(
            sum(f, a, b) = a > b ? 0 : f(a) + sum(f, a + 1, b);
            sum(x -> x * x, 1, 10)
        )) == 385
        @test fn(:(
            incr =
                let priv_counter = 0
                    () -> priv_counter = priv_counter + 1
                end;
            incr() ; incr() ; incr()
        )) == 3
    end

    @testset verbose = true "Globals" begin
        @test fn(:(
            let secret = 1234; global show_secret() = secret end;
            show_secret()
        )) == 1234
        @test fn(:(
            let priv_balance = 0
                global deposit = quantity -> priv_balance = priv_balance + quantity
                global withdraw = quantity -> priv_balance = priv_balance - quantity
            end;
            deposit(200); withdraw(50)
        )) == 150
    end
end
