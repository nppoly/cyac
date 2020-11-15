#-*- coding:utf-8 -*- 
import unittest
from cyac import AC
from pathlib import Path
import sys
import os


class TestAC(unittest.TestCase):

    words_file = "test.txt" # change name here if test.txt != test.txt

    def test_init(self):
        ac = AC.build([u'我', u'我是', u'是中'])
        arr = [(end_, val) for val, start_, end_ in ac.match(u"我是中国人")]
        self.assertEqual(arr, [(1, 0), (2, 1), (3, 2)])

    def test_sep(self):
        ac = AC.build([u"a", u"aa", u"A", u"AA"])
        sep = set([ord(" ")])
        arr = [(end_, val) for val, _, end_ in ac.match(u"a aaa", sep)]
        self.assertEqual(arr, [(1, 0)])

    def test_ignore_case(self):
        if sys.version_info.major < 3:
            return
        ac = AC.build([u"aİ", u"aİİ", u"aai̇", u"aai̇bİ"], True)
        arr = [(end_, val) for val, start_, end_ in ac.match(u"aai̇bİa")]
        self.assertEqual(arr, [(4, 2), (4, 0), (6, 3)])

        ac = AC.build([u"aİ", u"aaİ", u"aai̇", u"aai̇bİ"], True)
        self.assertEqual(ac.size, 3)
        arr = [(end_, val) for val, start_, end_ in ac.match(u"aai̇bİa")]
        self.assertEqual(arr, [(4, 1), (4, 0), (6, 2)])

    def test_ignore_case_sep(self):
        if sys.version_info.major < 3:
            return
        ac = AC.build([u"aİ", u"aaİ", u"aai̇", u"aai̇bİ"], True)
        sep = set([ord(" ")])
        arr = [(end_, val) for val, start_, end_ in ac.match(u"aai̇bİ", sep)]
        self.assertEqual(arr, [(6, 2)])

    def test_save(self):
        ac_file = "ac_cyac"
        with open(TestAC.words_file, "r", encoding="utf-8") as f:
            words = list(f)
        ac = AC.build(words)
        ac_to_be_saved_size = ac.buff_size()
        ac.save(ac_file)
        ac_saved_size = Path(ac_file).stat().st_size
        self.assertEqual(ac_to_be_saved_size, ac_saved_size)
        os.remove(ac_file)
