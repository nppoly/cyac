# distutils: language=c++
from libc.string cimport strlen, memcpy, memset
from libc.stdlib cimport malloc, free, realloc
from libcpp cimport bool
from libcpp.deque  cimport deque
from libc.stdio cimport *
from libcpp cimport bool
import cython
from .xstring cimport xstring, byte_t, ignore_case_alignment, unicode_int_t, stringbuf


cdef struct Block:
    int prev
    int next_
    int num
    int reject
    int trial
    int ehead


cdef struct Node:
    int value
    int check
    byte_t sibling
    byte_t child
    unsigned short flags

cpdef inline bytes array_to_bytes(char* ptr, int size):
    return <bytes>ptr[:size]

cpdef inline char* bytes_to_array(bytes data, int capacity):
    cdef char* ptr = <char*> malloc(capacity)
    memcpy(ptr, <char *>data, len(data))
    return ptr


cdef inline int ignore_case_offset(ignore_case_alignment align, xstring xs, int byte_idx):
    cdef int char_offset = xs.char_idx_of_byte[byte_idx]
    if align is None:
        return char_offset
    return align.lowercase_char_index_mapping[char_offset]

cdef class Trie(object):
    cdef int key_num
    cdef int key_capacity
    cdef Node* array
    cdef Block* blocks
    cdef int reject[257]
    cdef int bheadF
    cdef int bheadC
    cdef int bheadO
    cdef int array_size
    cdef int capacity
    cdef bool ignore_case
    cdef bool ordered
    cdef int max_trial
    cdef int last_remove_leaf
    cdef int* leafs
    cdef int leaf_size
    cdef Py_buffer* buff
    cdef inline int _get(self, byte_t *key, int key_size, int from_, int start)
    cdef inline int follow(self, int from_, byte_t label)
    cdef bool has_label(self, int id_, byte_t label)
    cdef inline int child(self, int id_, byte_t label)
    cdef inline int children(self, int id_, byte_t *labels, int *children_arr, int first_n)
    cdef inline int jump(self, byte_t byte, int from_)
    cdef inline int jump_bytes(self, byte_t *bytes_, int byte_num, int from_)
    cdef inline int jump_uchar(self, xstring text, int uchar_idx, int from_)
    cdef bytes substring(self, int id_, int start_id)
    cdef bytes key(self, int id_)
    cdef inline int value(self, int id_)
    cdef inline bool has_value(self, int id_)
    cpdef int insert(self, unicode key)
    cpdef int remove(self, unicode key_)
    cpdef int get(self, unicode key)
    cdef inline int get_bytes(self, byte_t* bkey, int len_)

    # Private Method, Don't Call
    cdef inline void _node_init(self, Node* n, int value, int check)
    cdef inline int _node_child_num(self, Node *n)
    cdef inline void _node_set_child_num(self, Node *n, int val)
    cdef inline int _node_base(self, Node *n)
    cdef inline bool _node_is_child(self, Node *n, int par)
    cdef inline byte_t* _node_child_ptr(self, Node *n)
    cdef inline byte_t* _node_sibling_ptr(self, Node *n)
    cdef inline void _block_init(self, Block* block, int prev, int next_, int trial, int ehead, int num, int reject)
    cdef inline Node* _node(self, int nid)
    cdef inline void pop_block(self, int bi, int* head_in, bool last)
    cdef inline void push_block(self, int bi, int* head_out, bool empty)
    cdef int add_block(self)
    cdef inline void transfer_block(self, int bi, int* head_in, int* head_out)
    cdef inline int pop_enode(self, int base, byte_t label, int from_)
    cdef void push_enode(self, int e)
    cdef inline void push_sibling(self, int from_, int base, byte_t label, bool has_child)
    cdef inline void pop_sibling(self, int from_, byte_t label)
    cdef inline bool consult(self, Node *nref, Node *pref)
    cdef inline int sibling(self, int to)
    cdef int set_child(self, int base, byte_t c, byte_t label, bool append_label, byte_t *children)
    cdef inline int find_place(self)
    cdef inline int find_places(self, byte_t *child, int child_num)
    cdef inline int resolve(self, int from_n, int base_n, byte_t label_n)
    cdef void _to_buff(self, void* buff)
    cdef write(self, FILE* ptr_fw)

cdef Trie trie_from_buff(void* buf, int buf_size, bool copy)
