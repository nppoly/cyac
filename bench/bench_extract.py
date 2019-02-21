# from cyac import AC
from bench_init import *

sep = set([ord(s) for s in ['.', '\t', '\n', '\a', ' ', ',']])


def extract_re(pat, txt):
    return pat.sub(lambda m: m.group(0), txt)

def extract_flashtext(pat, txt):
    for x in pat.replace_keywords(txt):
        pass

def extract_trie(pat, txt):
    for x in trie.replace_longest(txt, replaced, sep):
        pass


if __name__ == '__main__':
    words = read_file()
    txt = read_txt()
    setup = "from __main__ import extract_re, extract_flashtext, extract_trie, ft, rex, trie, words, txt, txt2"

    ft = init_flashtext(words, len(words))
    rex = init_re(words, len(words))
    trie = init_trie(words, len(words))
    replaced = [k for k, id_ in trie.items()]

    for size in range(20000, len(txt), 20000):
        txt2 = txt[:size]
        # print("build", "re", size, timeit.timeit("replace_re(rex, txt)", setup=setup, number=5))
        print("extract", "flashtext", size, timeit.timeit("extract_flashtext(ft, txt2)", setup=setup, number=5))
        print("extract", "trie", size, timeit.timeit("extract_trie(trie, txt2)", setup=setup, number=5))