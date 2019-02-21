# distutils: language=c++

import cython
from cpython.version cimport PY_MAJOR_VERSION
from libcpp.string cimport string
from .utf8 cimport byte_t

ctypedef fused text_t:
    unicode
    bytes

ctypedef fused unicode_int_t:
    unicode
    int

cdef class xstring(object):
    cdef unicode py_unicode
    cdef bytes py_bytes
    cdef byte_t* bytes_ 
    # byte num 和 char_num 都不包括结尾的\0
    cdef int byte_num
    cdef int char_num
    cdef int* char_idx_of_byte # 每个byte对应的char
    cdef int* char_offsets # 每个char 在bytes中的offset
    cdef int* chars # char的数组
    cpdef int char_at(self, int i)

    cdef inline int char_byte_num(self, int i):
        return self.char_offsets[i+1] - self.char_offsets[i]

cdef class ignore_case_alignment(object):
    cdef xstring original
    cdef xstring lowercase
    cdef int* lowercase_char_index_mapping # char的 index 到 index 的转换

cdef extern from "<sstream>" namespace "std" nogil:
    ctypedef int streamsize
    cdef cppclass stringbuf:
        streamsize write "sputn" (const char* s, streamsize n);
        int put "sputc" (char c);
        stringbuf()
        string to_string "str" () const



# default_seperator = set([ord(c) for c in " \t\n\r'\"{}[]().,?!;<>+~#$%^&*-|\\/"])
