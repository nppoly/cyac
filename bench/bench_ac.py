from bench_init import *

import ahocorasick

def init_pyac(words, size):
    a = ahocorasick.Automaton()
    for i in range(size):
        a.add_word(words[i], i)
    a.make_automaton()
    return a

def match(ac, txt):
    for x in ac.match(txt):
        pass

def match2(ac, txt):
    for x in ac.iter(txt):
        pass


if __name__ == '__main__':
    words = read_file()
    txt = read_txt()
    setup = "from __main__ import ac, ac2, txt2, match, match2"
    ac = init_ac(words, len(words))
    ac2 = init_pyac(words, len(words))
    for size in range(20000, len(txt), 20000):
        txt2 = txt[:size]
        print("match", "ac", size, timeit.timeit(
            "match(ac, txt2, return_all=True)", setup=setup, number=5))
        print("match", "pyahocorasick", size, timeit.timeit(
            "match2(ac2, txt2)", setup=setup, number=5))
