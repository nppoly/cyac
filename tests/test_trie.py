#-*- coding:utf-8 -*- 
import unittest, sys
import os
from cyac import Trie

class TestTrie(unittest.TestCase):
    def test_init(self):
        trie = Trie()
        ids = [trie.insert(w) for w in [u'Ruby', u'ruby', u'rb']]
        self.assertEqual(ids, [0, 1, 2])
        self.assertEqual(u"ruby" in trie, True)
        self.assertEqual(u"rubyx" in trie, False)
        self.assertEqual(trie.remove(u"ruby"), 1)
        self.assertEqual(trie.remove(u"ruby"), -1)

    def test_get_element(self):
        trie = Trie()
        ids = {w : trie.insert(w) for w in [u"ruby", u"rubx", u"rab", u"rub", u"rb"]}
        for w, id_ in ids.items():
            self.assertEqual(trie[id_], w)
            self.assertEqual(trie[w], id_)
    
    def test_init2(self):
        trie = Trie()
        ids = [trie.insert(w) for w in [u'Ruby', u'ruby', u'rb', u'XX']]
        self.assertEqual([(k, v) for k, v in trie.items()], [(u"Ruby", 0), (u"ruby", 1), (u"rb", 2), (u"XX", 3)])

    def test_ignore_case(self):
        trie = Trie(ignore_case=True)
        ids = [trie.insert(w) for w in [u'Ruby', u'ruby', u'rb']]
        self.assertEqual(ids, [0, 0, 1])
        self.assertEqual(trie.remove(u"ruby"), 0)
        self.assertEqual(trie.remove(u"Ruby"), -1)

    def test_prefix(self):
        trie = Trie()
        ids = {w : trie.insert(w) for w in [u"ruby", u"rubx", u"rab", u"rub"]}
        prefixes = list(trie.prefix(u"ruby on rails"))
        self.assertEqual(prefixes, [(ids[u"rub"], 3), (ids[u"ruby"], 4)])

    def test_ignore_case_prefix(self):
        if sys.version_info.major < 3:
            return
        txt = u"aaİbİc"
        trie = Trie(ignore_case=True)
        ids = {w : trie.insert(w) for w in [u"aİ", u"aİİ", u"aai̇", u"aai̇bİ"]}
        prefixes = list(trie.prefix(txt))
        self.assertEqual(prefixes, [(ids[u"aai̇"], 3), (ids[u"aai̇bİ"], 5)])
        txt = u"aai̇bİc"
        prefixes = list(trie.prefix(txt))
        self.assertEqual(prefixes, [(ids[u"aai̇"], 4), (ids[u"aai̇bİ"], 6)])

    def test_predict(self):
        trie = Trie(ordered=True)
        ids = {w : trie.insert(w) for w in [u"ruby", u"rubx", u"rab", u"rub", u"rb"]}
        predicts = list(trie.predict(u"r"))
        self.assertEqual(predicts, [
            ids[u"rb"], 
            ids[u"rab"], 
            ids[u"rub"], 
            ids[u"rubx"], 
            ids[u"ruby"]])
    
    def test_ignore_case_predict(self):
        if sys.version_info.major < 3:
            return
        trie = Trie(ignore_case=True, ordered=True)
        ids = {w : trie.insert(w) for w in [u"aaİ", u"aİİ", u"aai̇", u"aai̇bİ"]}
        predicts = list(trie.predict(u"aaİ"))
        self.assertEqual(predicts, [
            ids[u'aai̇'],
            ids[u'aai̇bİ']
        ])

    def test_match_longest(self):
        trie = Trie()
        ids = {w : trie.insert(w) for w in [u"New York", u"New", u"York", u"York City", u"City", u"City is"]}
        matches = list(trie.match_longest(u"New York City isA"))
        self.assertEqual(matches, [
            (ids[u"New York"], 0, len(u"New York")),
            (ids[u"City is"], len(u"New York "), len(u"New York City is"))
        ])
        sep = set([ord(" ")]) # space as seperator
        matches = list(trie.match_longest(u"New York City isA", sep))
        self.assertEqual(matches, [
            (ids[u"New York"], 0, len(u"New York")),
            (ids[u"City"], len(u"New York "), len(u"New York City"))
        ])

    def test_ignore_case_match_longest(self):
        if sys.version_info.major < 3:
            return
        trie = Trie(ignore_case=True)
        ids = {w : trie.insert(w) for w in [u"aİİ", u"aai̇", u"aai̇bİ"]}
        matches = list(trie.match_longest(u"aaİ aai̇bİaa"))
        self.assertEqual(matches, [
            (ids[u"aai̇"], 0, len(u"aaİ")),
            (ids[u"aai̇bİ"], len(u"aaİ "), len(u"aaİ aai̇bİ"))
        ])
        sep = set([ord(" ")]) # space as seperator
        matches = list(trie.match_longest(u"aaİ aai̇bİaa", sep))
        self.assertEqual(matches, [
            (ids[u"aai̇"], 0, len(u"aaİ")),
        ])

    def test_replace_longest(self):
        trie = Trie()
        ids = {w : trie.insert(w) for w in [u"New York", u"New", u"York", u"York City", u"City", u"City is"]}
        replaced = {
            ids[u"New York"] : u"Beijing",
            ids[u"New"] : u"Old",
            ids[u"York"] : u"Yark",
            ids[u"York City"] : u"Yerk Town",
            ids[u"City"] : u"Country",
            ids[u"City is"] : u"Province are"
        }
        res = trie.replace_longest(u"New York  City isA", lambda x, start, end: replaced[x])
        self.assertEqual(res, u"Beijing  Province areA")

        sep = set([ord(" ")]) # space as seperator
        res = trie.replace_longest(u"New York  City isA", lambda x, start, end: replaced[x], sep)
        self.assertEqual(res, u"Beijing  Country isA")

    def test_ignore_case_replace_longest(self):
        if sys.version_info.major < 3:
            return
        trie = Trie(ignore_case=True)
        ids = {w : trie.insert(w) for w in [u"aİİ", u"aai̇", u"aai̇bİ"]}
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

    def test_reuse_id(self):
        trie = Trie()
        ids = {w : trie.insert(w) for w in [u"abc", u"abd", u"abe"]}
        trie.remove(u"abc")
        trie.remove(u"abe")
        v = trie.insert(u"abf")
        self.assertEqual(v, ids[u"abe"])
        v = trie.insert(u"abg")
        self.assertEqual(v, ids[u"abc"])
        v = trie.insert(u"abh")
        self.assertEqual(v, 3)
        v = trie.insert(u"abi")
        self.assertEqual(v, 4)

    def test_remove_words(self):
        dir_ = os.path.dirname(__file__)
        trie = Trie()
        for i in range(3):
            ids = []
            words = []
            with open(os.path.join(dir_, "../bench/words.txt")) as fi:
                for l in fi:
                    l = l.strip()
                    if isinstance(l, bytes):
                        l = l.decode("utf8")
                    if len(l) > 0:
                        words.append(l)
                        ids.append(trie.insert(l))
            for id_, w in zip(ids, words):
                self.assertEqual(id_, trie.remove(w))


    def test_match_words(self):
        dir_ = os.path.dirname(__file__)
        trie = Trie()
        ids = []
        with open(os.path.join(dir_, "../bench/words.txt")) as fi:
            for l in fi:
                l = l.strip()
                if isinstance(l, bytes):
                    l = l.decode("utf8")
                if len(l) > 0:
                    ids.append(trie.insert(l))
        with open(os.path.join(dir_, "../bench/words.txt")) as fi:
            txt = fi.read()
            if isinstance(txt, bytes):
                txt = txt.decode("utf8")
        sep = set([ord("\n")])
        matched = []
        for v, start, end in trie.match_longest(txt, sep):
            matched.append(v)
            self.assertEqual(txt[start:end], trie[v])
        self.assertEqual(matched, ids)

    def test_replace_words(self):
        dir_ = os.path.dirname(__file__)
        trie = Trie()
        ids = []
        with open(os.path.join(dir_, "../bench/words.txt")) as fi:
            for l in fi:
                l = l.strip()
                if isinstance(l, bytes):
                    l = l.decode("utf8")
                if len(l) > 0:
                    ids.append(trie.insert(l))
        with open(os.path.join(dir_, "../bench/words.txt")) as fi:
            txt = fi.read()
            if isinstance(txt, bytes):
                txt = txt.decode("utf8")
        sep = set([ord("\n")])
        ret = trie.replace_longest(txt, lambda v, start, end: str(v), sep).strip()
        self.assertEqual(ret, "\n".join([str(i) for i in ids]))

    def test_insert_zero_len_key(self):
        trie = Trie()
        self.assertEqual(trie.insert(u""), -1)

    def test_invalid_id(self):
        trie = Trie()
        trie.insert("hello")
        trie.insert("world")
        with self.assertRaises(AttributeError):
            trie[3]

        trie.remove("hello")
        with self.assertRaises(AttributeError):
            trie[0]
        
        trie.insert("hello2")
        trie[0]
