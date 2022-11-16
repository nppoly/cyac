#-*- coding:utf-8 -*- 
import unittest
from cyac import Trie, AC
import sys

class TestBuff(unittest.TestCase):
    def test_buff_ac(self):
        trie = Trie(ignore_case=True)
        ids = {w : trie.insert(w) for w in [u"aİİ", u"aai̇", u"aai̇bİ"]}
        trie.save("trie.bin")
        with open("trie.bin", "rb") as fi:
            bs = bytearray(fi.read())
        self.assertEqual(len(bs), trie.buff_size())
        bs2 = bytearray(trie.buff_size())
        trie.to_buff(bs2)
        self.assertEqual(bs2, bs)

        self._check_trie_correct(Trie.from_buff(bs2, copy=True), ids)
        self._check_trie_correct(Trie.from_buff(bs2, copy=False), ids)


    def _check_trie_correct(self, trie, ids):
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

    def test_buff_ac(self):
        ac = AC.build([u"aİ", u"aaİ", u"aai̇", u"aai̇bİ"], True)
        ac.save("ac.bin")
        with open("ac.bin", "rb") as fi:
            bs = bytearray(fi.read())
        self.assertEqual(len(bs), ac.buff_size())
        bs2 = bytearray(ac.buff_size())
        ac.to_buff(bs2)
        self.assertEqual(bs2, bs)
        self._check_ac_correct(ac)
        self._check_ac_correct(AC.from_buff(bs2, copy=True))
        self._check_ac_correct(AC.from_buff(bs2, copy=False))

    def _check_ac_correct(self, ac):
        self.assertEqual(ac.size, 3)
        arr = [(end_, val) for val, start_, end_ in ac.match(u"aai̇bİa")]
        self.assertEqual(arr, [(4, 1), (4, 0), (6, 2)])

if __name__ == '__main__':
    unittest.main()