# from cyac import AC
from bench_init import *

sep = set([ord(s) for s in ['.', '\t', '\n', '\a', ' ', ',']])


def replace_re(pat, txt):
    return pat.sub(lambda m: m.group(0), txt)

def replace_flashtext(pat, txt):
    return pat.replace_keywords(txt)

def replace_trie(pat, txt):
    return trie.replace_longest(txt, replaced, sep)


if __name__ == '__main__':
    words = read_file()
    txt = read_txt()
    setup = "from __main__ import replace_re, replace_flashtext, replace_trie, ft, rex, trie, words, txt, txt2"

    ft = init_flashtext(words, len(words))
    rex = init_re(words, len(words))
    trie = init_trie(words, len(words))
    replaced = [k for k, id_ in trie.items()]

    for size in range(20000, len(txt), 20000):
        txt2 = txt[:size]
        # print("build", "re", size, timeit.timeit("replace_re(rex, txt)", setup=setup, number=5))
        print("replace", "flashtext", size, timeit.timeit("replace_flashtext(ft, txt2)", setup=setup, number=5))
        print("replace", "trie", size, timeit.timeit("replace_trie(trie, txt2)", setup=setup, number=5))