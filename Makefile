TESTS_DIR = tests

t1:
	@julia $(TESTS_DIR)/p1.jl

test: t1
	