TESTS_DIR = tests

p1:
	@julia $(TESTS_DIR)/p1.jl

test: p1
	