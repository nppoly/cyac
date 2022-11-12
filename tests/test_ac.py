#-*- coding:utf-8 -*- 
import unittest
from cyac import AC
import sys

class TestAC(unittest.TestCase):
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

    def test_match_longest(self):
        ac = AC.build([u"py", u"python"])
        text = 'python'
        matched = list(ac.match(text, no_substring=True))
        print(matched)
        self.assertEquals(len(matched), 1)
        self.assertEquals(text[matched[0][1]:matched[0][2]], "python")