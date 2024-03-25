TESTS_DIR = tests

p1:
	@julia $(TESTS_DIR)/p1.jl

p2:
	@julia $(TESTS_DIR)/p2.jl

p3:
	@julia $(TESTS_DIR)/p3.jl

teacher:
	@julia $(TESTS_DIR)/teacher.jl

test: p1 p2 p3
	