#-*- coding:utf-8 -*- 
import unittest, sys
from cyac.xstring import xstring, ignore_case_alignment

class TestXString(unittest.TestCase):
    def test_init(self):
        txt = u"呵呵"
        s = xstring(txt)
        self.assertEqual(s.char_num, len(txt))
        self.assertEqual(s.byte_num, len(txt.encode("utf8")))
        for i, c in enumerate(txt):
            self.assertEqual(s.char_at(i), ord(c))

    def test_lowercase(self):
        if sys.version_info.major < 3:
            return
        txt = u"aaİb"
        s = xstring(txt)
        align = ignore_case_alignment(s)
        self.assertEqual(align.lowercase_xstring.bytes, txt.lower().encode("utf8"))
        self.assertEqual(align.alignment_array(), [0,1,2,2,3])

if __name__ == '__main__':
    unittest.main()