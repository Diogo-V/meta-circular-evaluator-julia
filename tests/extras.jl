include("../src/main.jl")
using Test

# We do this renaming to make it easier to test
fn = metajulia_eval

macro capture_out(block)
    quote
        if ccall(:jl_generating_output, Cint, ()) == 0
            original_stdout = stdout
            out_rd, out_wr = redirect_stdout()
            out_reader = @async read(out_rd, String)
        end

        try
            $(esc(block))
        finally
            if ccall(:jl_generating_output, Cint, ()) == 0
                redirect_stdout(original_stdout)
                close(out_wr)
            end
        end

        if ccall(:jl_generating_output, Cint, ()) == 0
            fetch(out_reader)
        else
            ""
        end
    end
end

function test_show(x, repr)
    io = IOBuffer()
    show(io, x)
    String(take!(io)) == repr
end

macro test_with_stdout(expr, expected_output, expected_result)
    quote
        out_val = $expr
        out_text = @capture_out $expr
        out_text == $expected_output && out_val == $expected_result
    end
end

@testset verbose = true "Extras" begin
    @testset verbose = true "Tracing" begin
        @test @test_with_stdout(fn(:(
            f(x) = x;
            register_traceable(f);
            f(1)
        )), "Calling function: f with arguments: (1,)\nFunction f returned: 1\n", 1)
        @test @test_with_stdout(fn(:(
            f(x) = x;
            register_traceable(f);
            f(1) + f(2)
        )), "Calling function: f with arguments: (1,)\nFunction f returned: 1\nCalling function: f with arguments: (2,)\nFunction f returned: 2\n", 3)
        @test @test_with_stdout(fn(:(
            f(x) := x;
            register_traceable(f);
            f(1)
        )), "Calling function: f with arguments: (1,)\nFunction f returned: 1\n", 1)
        @test @test_with_stdout(fn(:(
            f(x) $= :($x);
            register_traceable(f);
            f(1)
        )), "Calling function: f with arguments: (1,)\nFunction f returned: 1\n", 1)
        @test @test_with_stdout(fn(:(
            f(x) $= :($x);
            register_traceable(f);
            f(1) + f(2)
        )), "Calling function: f with arguments: (1,)\nFunction f returned: 1\nCalling function: f with arguments: (2,)\nFunction f returned: 2\n", 3)
        @test @test_with_stdout(fn(:(
            f(x) $= :($x);
            register_traceable(f);
            f(f(2))
        )), "Calling function: f with arguments: (:(f(2)),)\nCalling function: f with arguments: (2,)\nFunction f returned: 2\nFunction f returned: 2\n", 2) 
    end
end
