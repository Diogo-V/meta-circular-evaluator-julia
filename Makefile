EXPECTED_DIR = tests/expected
INPUT_DIR = tests/input
OUTPUT_DIR = tests/output

TARGET = src/main.jl

RED=\033[0;31m
GREEN=\033[0;32m
NC=\033[0m

test:
	@mkdir -p $(OUTPUT_DIR)
	@for file in $(wildcard $(INPUT_DIR)/*.in); do \
		julia $(TARGET) < $$file > $(OUTPUT_DIR)/$$(basename $$file .in).out; \
		diff $(EXPECTED_DIR)/$$(basename $$file .in).out $(OUTPUT_DIR)/$$(basename $$file .in).out; \
		if [ $$? -eq 0 ]; then \
			echo "[$$(basename $$file .in).in]: ${GREEN}PASSED${NC}"; \
		else \
			echo "[$$(basename $$file .in).in]: ${RED}FAILED${NC}"; \
		fi; \
	done
