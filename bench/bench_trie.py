# from cyac import AC
from bench_init import *

def get_trie(trie, words, size):
    for i in range(size):
        trie.get(words[i])

def get_htrie(trie, words, size):
    for i in range(size):
        trie[words[i]]

def remove_trie(trie, words, size):
    for i in range(size):
        trie.remove(words[i])

if __name__ == '__main__':
    words = read_file()
    txt = read_txt()
    setup = "from __main__ import get_trie, get_htrie, remove_trie, trie, htrie, words, size"

    for size in range(20000, len(words), 20000):
        trie = init_trie(words, size)
        htrie = init_htrie(words, size)
        replaced = [k for k, id_ in trie.items()]
        # print("build", "re", size, timeit.timeit("replace_re(rex, txt)", setup=setup, number=5))
        print("get", "hat-trie", size, timeit.timeit("get_htrie(htrie, words,size)", setup=setup, number=5), flush=True)
        print("get", "trie", size, timeit.timeit("get_trie(trie, words,size)", setup=setup, number=5), flush=True)
        print("remove", "trie", size, timeit.timeit("remove_trie(trie, words,size)", setup=setup, number=5), flush=True)