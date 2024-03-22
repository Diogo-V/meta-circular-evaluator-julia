@echo off

set TESTS_DIR=tests

set ARGUMENT=%1

    julia %TESTS_DIR%\%ARGUMENT%.jl
