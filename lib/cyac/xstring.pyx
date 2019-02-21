#cython: language_level=3, boundscheck=False, overflowcheck=False
#     profile=True, linetrace=True
# If return NULL then it's invalid utf8
from libc.stdlib cimport malloc, free, realloc
from cython cimport typeof
from .utf8 cimport fill_char_info, char_num
from cython cimport Py_UCS4
cdef extern from "unicode_portability.cpp":
    pass
cdef extern int _PyUnicode_ToLowerFull(Py_UCS4 ch, Py_UCS4* res)

# from libc.wctype cimport towlower, towupper, iswlower, iswupper


cdef class xstring(object):
    def __cinit__(self, unicode text):
        cdef bytes py_bytes = text.encode("utf8")
        self.py_unicode = text
        self.py_bytes = py_bytes
        self.bytes_ = py_bytes
        self.byte_num = len(py_bytes)
        self.char_num = char_num(self.bytes_)
        if self.char_num < 0:
            raise Exception("Invalid UTF8 string")
        self.char_idx_of_byte = <int*> malloc((self.byte_num + 1  + self.char_num + self.char_num + 1) * sizeof(int))
        self.chars = self.char_idx_of_byte + self.byte_num + 1
        self.char_offsets =self.chars + self.char_num
        fill_char_info(self.bytes_, self.char_idx_of_byte, self.chars, self.char_offsets)
    
    property byte_num:
        def __get__(self):
            return self.byte_num

    property char_num:
        def __get__(self):
            return self.char_num
        
    cpdef int char_at(self, int i):
        if i >= self.char_num:
            return 0
        return self.chars[i]

    property bytes:
        def __get__(self):
            return self.py_bytes

    def __dealloc__(self):
        if self.char_idx_of_byte:
            free(self.char_idx_of_byte)

    def __repr__(self):
        return repr(self.py_bytes)

    def __str__(self):
        return str(self.py_bytes)

  
cdef class ignore_case_alignment(object):
    def __cinit__(self, xstring original):
        self.original = original
        self.lowercase = xstring(original.py_unicode.lower())
        self.lowercase_char_index_mapping =  <int*> malloc((len(self.lowercase.py_unicode) + 1) * sizeof(int))
        cdef Py_UCS4 buf[4]
        cdef int offset = 0
        cdef int n
        for ori_char_idx in range(len(original.py_unicode)):
            n = _PyUnicode_ToLowerFull(original.chars[ori_char_idx], buf)
            for i in range(n):
                self.lowercase_char_index_mapping[offset + i] = ori_char_idx
            offset += n
        self.lowercase_char_index_mapping[offset] = original.char_num

    property lowercase_xstring:
        def __get__(self):
            return self.lowercase

    property original_xstring:
        def __get__(self):
            return self.original

    

    def alignment_array(self):
        return [self.lowercase_char_index_mapping[cidx] for cidx in range(len(self.lowercase.py_unicode))]


    def __dealloc__(self):
        if self.lowercase_char_index_mapping:
            free(self.lowercase_char_index_mapping)

