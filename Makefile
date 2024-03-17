TESTS_DIR = tests

p1:
	@julia $(TESTS_DIR)/p1.jl

p2:
	@julia $(TESTS_DIR)/p2.jl

test: p1 p2
	