@echo off

set TESTS_DIR=tests

for %%f in (%TESTS_DIR%\*.jl) do (
    julia %%f
)
