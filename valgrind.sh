valgrind --tool=memcheck --leak-check=full --num-callers=30 --suppressions=tests/valgrind-python.supp python tests/test_all.py
