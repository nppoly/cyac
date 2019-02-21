
# distutils: language=c++
ctypedef unsigned char byte_t
cdef inline byte_t* iter_unicode(byte_t *src, int* ret, int *char_byte_num):
    cdef int result = 0
    cdef int i
    cdef byte_t leading_byte, c
    cdef int len_
    leading_byte = src[0]
    src += 1
    if leading_byte == 0:
        ret[0] = 0
        char_byte_num[0] = 1
        return src
    if leading_byte < 0x80:
        ret[0] = leading_byte
        char_byte_num[0] = 1
        return src
    if leading_byte & 0xe0 == 0xc0:
        len_ = 2
        result = leading_byte & 0x1f
    elif leading_byte & 0xf0 == 0xe0:
        len_ = 3
        result = leading_byte & 0x0f
    elif leading_byte & 0xf8 == 0xf0:
        len_ = 4
        result = leading_byte & 0x07
    elif leading_byte & 0xfc == 0xf8:
        len_ = 5
        result = leading_byte & 0x03
    elif leading_byte & 0xfe == 0xfc:
        len_ = 6
        result = leading_byte & 0x01
    else:
        len_ = 1
        ret[0] = 0
        return NULL

    char_byte_num[0] = len_
    for i in range(len_ - 1):
        c = src[0]
        src += 1
        result <<= 6
        result += c & 0x3f
    ret[0] = result
    return src


cdef inline byte_t* encode_unicode(int c, byte_t *utf8_dst):
    if c == 0:
        return utf8_dst
    cdef byte_t ch
    if c < 0x00080:
        ch = (c & 0xFF);
        utf8_dst[0]=(ch); utf8_dst += 1
    elif c < 0x00800:
        ch = (0xC0 + ((c >> 6) & 0x1F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + (c & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
    elif c < 0x10000:
        ch = (0xE0 + ((c >> 12) & 0x0F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 6) & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + (c & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
    elif c < 0x200000:
        ch = (0xF0 + ((c >> 18) & 0x07))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 12) & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 6)  & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + (c & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
    elif c < 0x8000000:
        ch = (0xF8 + ((c >> 24) & 0x03))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 18) & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 12) & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 6)  & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + (c & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
    else:
        ch = (0xFC + ((c >> 30) & 0x01))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 24) & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 18) & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 12) & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + ((c >> 6)  & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1
        ch = (0x80 + (c & 0x3F))
        utf8_dst[0]=(ch); utf8_dst += 1

    return utf8_dst


cdef int char_num(byte_t *src)
cdef int fill_char_info(byte_t *src, int *char_idx_of_byte, int *chars, int *char_offsets)

