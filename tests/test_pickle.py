#-*- coding:utf-8 -*- 
import unittest
import pickle
from cyac import Trie, AC

class TestPickle(unittest.TestCase):
    def test_pickle_trie(self):
        trie = Trie(ignore_case=True)
        ids = {w : trie.insert(w) for w in [u"aİİ", u"aai̇", u"aai̇bİ"]}
        with open("trie.pkl", "wb") as fo:
            pickle.dump(trie, fo)
        with open("trie.pkl", "rb") as fi:
            trie = pickle.load(fi)
        replaced = {
            ids[u"aİİ"] : u"a",
            ids[u"aai̇"] : u"b",
            ids[u"aai̇bİ"] : u"c",
        }
        res = trie.replace_longest(u"aaİ aai̇bİaa", lambda x, start, end: replaced[x])
        self.assertEqual(res, u"b caa")
        sep = set([ord(" ")]) # space as seperator
        res = trie.replace_longest(u"aaİ aai̇bİaa", lambda x, start, end: replaced[x], sep)
        self.assertEqual(res, u"b aai̇bİaa")

    def test_pickle_ac(self):
        ac = AC.build([u"aİ", u"aaİ", u"aai̇", u"aai̇bİ"], True)
        with open("ac.pkl", "wb") as fo:
            pickle.dump(ac, fo)
        with open("ac.pkl", "rb") as fi:
            ac = pickle.load(fi)
        self.assertEqual(ac.size, 3)
        arr = [(end_, val) for val, start_, end_ in ac.match(u"aai̇bİa")]
        self.assertEqual(arr, [(4, 1), (4, 0), (6, 2)])