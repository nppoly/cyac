from flashtext import KeywordProcessor
from cyac import AC, Trie
from hat_trie import Trie as HTrie
import re, os
import timeit

def read_file():
    dir_ = os.path.dirname(__file__)
    with open("%s/words.txt" % dir_) as fi:
        words = list(set([l.strip() for l in fi]))
    return words


def read_txt():
    dir_ = os.path.dirname(__file__)
    with open("%s/words.txt" % dir_) as fi:
        txt = fi.read()
    return txt


def init_re(words, size):
    pat = re.compile("(?<!\S)("+ "|".join(words) + ")(?!\S)")
    return pat


def init_flashtext(words, size):
    keyword_processor = KeywordProcessor()
    for i in range(size):
        keyword_processor.add_keyword(words[i])
    return keyword_processor


def init_ac(words, size):
    ret = AC.build(words[:size])
    return ret


def init_trie(words, size):
    trie = Trie()
    for i in range(size):
        trie.insert(words[i])
    return trie

def init_htrie(words, size):
    trie = HTrie()
    for i in range(size):
        trie[words[i]] = i
    return trie


if __name__ == '__main__':
    words = read_file()
    setup = "from __main__ import init_flashtext, init_re, init_ac, init_trie, init_htrie, words"

    for size in range(20000, len(words), 20000):
        print("build", "re", size, timeit.timeit("init_re(words, %s)" % size, setup=setup, number=5))
        print("build", "flashtext", size, timeit.timeit("init_flashtext(words, %s)" % size, setup=setup, number=5))
        print("build", "hat-trie", size, timeit.timeit("init_htrie(words, %s)" % size, setup=setup, number=5))
        print("build", "trie", size, timeit.timeit("init_trie(words, %s)" % size, setup=setup, number=5))
        print("build", "ac", size, timeit.timeit("init_ac(words, %s)" % size, setup=setup, number=5))