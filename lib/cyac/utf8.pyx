#cython: language_level=3, boundscheck=False, overflowcheck=False
#    profile=True, linetrace=True
from libc.stdlib cimport malloc, free, realloc

cdef int char_num(byte_t *src):
    cdef int ret = 0
    cdef int char_ = 0
    cdef int char_byte_num = 0
    while True:
        src = iter_unicode(src, &char_, &char_byte_num)
        if src == NULL:
            return -1
        if char_ == 0:
            break
        ret += 1
    return ret


cdef int fill_char_info(byte_t *src, int *char_idx_of_byte, int *chars, int *char_offsets):
    cdef int ret = 0
    cdef int char_ = 0
    cdef int char_byte_num = 0
    cdef int offset = 0
    cdef int i
    while True:
        src = iter_unicode(src, &char_, &char_byte_num)
        if src == NULL:
            return -1
        if char_ == 0:
            break
        char_offsets[ret] = offset
        chars[ret] = char_
        for i in range(char_byte_num):
            char_idx_of_byte[offset + i] = ret
        offset += char_byte_num
        ret += 1
    char_idx_of_byte[offset] = ret
    char_offsets[ret] = offset
    return ret
