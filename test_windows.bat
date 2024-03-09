@echo off


set EXPECTED_DIR=tests\expected
set INPUT_DIR=tests\input
set OUTPUT_DIR=tests\output
set TARGET=src\main.jl

if not exist %OUTPUT_DIR% mkdir %OUTPUT_DIR%

for %%f in (%INPUT_DIR%\*.in) do (
    julia %TARGET% < %%f > %OUTPUT_DIR%\%%~nf.out
    fc %EXPECTED_DIR%\%%~nf.out %OUTPUT_DIR%\%%~nf.out > nul
    if errorlevel 1 (
        echo [%%~nf.in]: FAILED
    ) else (
        echo [%%~nf.in]: PASSED
    )
)