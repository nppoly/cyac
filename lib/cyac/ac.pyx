#cython: language_level=3, boundscheck=False, overflowcheck=False
#    , profile=True, linetrace=True
from .trie cimport Trie, ignore_case_alignment, ignore_case_offset, array_to_bytes, bytes_to_array, trie_from_buff
from .xstring cimport xstring
from .utf8 cimport byte_t
from .util cimport check_buffer
from libcpp.deque  cimport deque
from libc.stdlib cimport malloc, free, realloc
from libc.string cimport memcpy 
from libc.stdio cimport *
from libcpp cimport bool
from libc.string cimport memset
from libc.stdint cimport uint32_t
from libcpp.vector cimport vector
from cpython.buffer cimport PyObject_GetBuffer, PyObject_CheckBuffer, PyBuffer_Release, PyBuffer_GetPointer, Py_buffer, PyBUF_WRITABLE, PyBUF_SIMPLE
from .version import magic_number, ac_binary_version, legacy_magic_number

def new_object(obj):
    return obj.__new__(obj)

cdef struct OutNode:
    int next_
    int value

cdef struct Matched:
    int val
    int start
    int end

cdef struct QueueNode:
    int node_id
    int node_label
    int len

cdef class AC(object):
    cdef Trie trie
    # cdef OutNode* output
    cdef int* fails
    cdef unsigned int* key_lens
    cdef Py_buffer* buff

    property ignore_case:
        def __get__(self):
            return self.ignore_case
    
    property size:
        def __get__(self):
            return self.trie.key_num

    def __getitem__(self, key):
        return self.trie[key]

    def prefix(self, unicode s not None):
        """
        return the prefix of given string which is in the trie.
        Args:
            key : string
                keyword that you want to searh
        Iterates:
            prefixes : tuple(id, end_offset)
                s[:end_offset] matches id
        Examples:
            >>> for id_, offset in ac.prefix("python"):
            >>>     print(id_, offset)
        """
        for x in self.trie.prefix(s):
            yield x

    def predict(self, unicode s not None):
        """
        return the string in the trie which starts with given string
        Args:
            key : string
                keyword that you want to searh
        Iterates:
            predicts : id
        Examples:
            >>> for id_ in ac.predict("python"):
            >>>     print(id_)
        """
        for x in self.trie.predict(s):
            yield x
    
    def __iter__(self):
        for id_ in self.trie:
            yield id_

    def items(self):
        """
        return all key and id ordered by id
        Iterates:
            items : (unicode, int)
        Examples:
            >>> for key, id_ in ac.items():
            >>>     print(id_, key)
        """
        for x in self.trie.items():
            yield x

    def __contains__(self, unicode t):
        t in self.trie

    def match_longest(self, unicode s not None, sep = None):
        """
        extract trie's keys from given string. only return the longest.
        Args:
            s : unicode
            sep : set(int) | None
                If you specify seperators. e.g. set([ord(' ')]), 
                it only matches strings tween seperators.
        Iterates:
            matched: tuple(id, start_offset, end_offset)
        Examples:
            >>> for id_, start_offset, end_offset in ac.match_longest("python", set([ord(" ")])):
            >>>     print(id_, start_offset, end_offset)
        """
        for x in self.trie.match_longest(s, sep):
            yield x

    def replace_longest(self, unicode s not None, callback not None, sep = None):
        """
        replace trie's keys from given string. only replace the longest.
        Args:
            s : unicode
            callback : lambda | list | dict
            sep : set(int) | None
                If you specify seperators. e.g. set([ord(' ')]), 
                it only matches strings tween seperators.
        Returns:
            replaced text
        Examples:
            >>> python_id = ac.get("python")
            >>> text = ac.replace_longest("python", {python_id: "hahah"}, set([ord(" ")]))
        """
        return self.trie.replace_longest(s, callback, sep)

    def __cinit__(self):
        self.trie = None
        # self.output = NULL
        self.fails = NULL
        self.key_lens = NULL
        self.buff = NULL

    def __dealloc__(self):
        if self.buff == NULL:
            # if self.output:
            #     free(self.output)
            if self.fails:
                free(self.fails)
            if self.key_lens:
                free(self.key_lens)
        else:
            PyBuffer_Release(self.buff)
            free(self.buff)

    # cdef inline void __fetch(self, int idx, int nid, vector[Matched]& res):
    #     cdef OutNode *e = &self.output[nid]
    #     cdef int val, len_, start_offset, end_offset
    #     while e[0].value >= 0:
    #         val = e[0].value
    #         len_ = self.key_lens[val]
    #         start_offset = idx - len_ + 1
    #         end_offset = idx + 1
    #         res.push_back(Matched(val, start_offset, end_offset))
    #         if e[0].next_ < 0:
    #             break
    #         e = &self.output[e[0].next_]

    @classmethod
    def build(cls, pats, ignore_case=False, ordered=False):
        """
        Build AC automata
        Args:
            pats : list(unicode)
            ignore_case : bool
                Defaults False
                see Trie's constructor for details.
            ordered : bool
                Defaults False
                see Trie's constructor for details.
        Returns:
            ac : AC
                ac automata
        Examples:
            >>> AC.build(["python"])
        """
        cdef int idx, id_, l, vk, fid, nid, fs
        cdef byte_t label
        cdef Trie trie = Trie(ignore_case, ordered)
        for s in pats:
            trie.insert(s)
        cdef QueueNode queue_node, queue_node2
        cdef int nlen = trie.array_size
        cdef int* fails = <int*> malloc(sizeof(int)*nlen)
        memset(fails, -1, sizeof(int)*nlen)
        # cdef OutNode* output = <OutNode*> malloc(sizeof(OutNode)*nlen)
        # memset(output, -1, sizeof(OutNode)*nlen)
        cdef deque[QueueNode] q = deque[QueueNode]()
        key_lens = <unsigned int*> malloc(sizeof(unsigned int) * trie.leaf_size)
        memset(key_lens, 0, sizeof(unsigned int) * trie.leaf_size)
        cdef int ro = 0
        fails[ro] = ro
        cdef byte_t children[256]
        cdef int children_nodes[256]
        child_num = trie.children(ro, children, children_nodes, 256)
        for idx in range(child_num):
            label = children[idx]
            id_ = children_nodes[idx]
            # print("child[%s][%s] = %s" % (ro, label, id_))
            queue_node.node_id = id_
            queue_node.node_label = label
            queue_node.len = 1
            q.push_back(queue_node)
            fails[id_] = ro
        while q.size() > 0:
            queue_node2 = q.front()
            q.pop_front()
            # print("queue_node2", queue_node2)
            nid = queue_node2.node_id
            l = queue_node2.len
            vk = trie.value(nid)
            if vk >= 0:
                key_lens[vk] = l
                # print("output[%s].value = %s, label: %s" % (nid, vk, queue_node2.node_label))
                # output[nid].value = vk
            child_num = trie.children(nid, children, children_nodes, 256)
            for idx in range(child_num):
                # print("child_idx %d of %d" % (idx, nid))
                label = children[idx]
                id_ = children_nodes[idx]
                # print("child[%s][%s] = %s" % (nid, label, id_))
                queue_node.node_id = id_
                queue_node.node_label = label
                queue_node.len = l + 1
                q.push_back(queue_node)
                fid = nid
                while fid != ro:
                    fs = fails[fid]
                    if trie.has_label(fs, label):
                        fid = trie.child(fs, label)
                        break
                    fid = fails[fid]
                fails[id_] = fid
                # if trie.has_value(fid):
                #     output[id_].next_ = fid
                #     # print("output[%s].next_ = %s" % (id_, fid))
        ac = AC()
        ac.trie = trie
        # ac.output = output
        ac.fails = fails
        ac.key_lens = key_lens
        return ac

    cdef inline void __fetch(self, int idx, int nid, vector[Matched]& res, bool return_all):
        cdef int val, len_, start_offset, end_offset
        while nid > 0:
            val = self.trie.value(nid)
            if val >= 0:
                len_ = self.key_lens[val]
                start_offset = idx - len_ + 1
                end_offset = idx + 1
                res.push_back(Matched(val, start_offset, end_offset))
            if not return_all:
                break
            nid = self.fails[nid]

    def match(self, unicode text not None, sep = None, return_all = True):
        """
        extract trie's keys from given string. 
        Args:
            text : unicode
            sep : set(int) | None
                If you specify seperators. e.g. set([ord(' ')]), 
                it only matches strings between seperators.
            return_all: if it's false, only return the longest substring in substrings with same suffix. it's useful only when sep is None
        Iterates:
            matched: tuple(id, start_offset, end_offset)
        Examples:
            >>> for id_, start_offset, end_offset in ac.match_longest("python", set([ord(" ")])):
            >>>     print(id_, start_offset, end_offset)
        """
        cdef xstring xstr = xstring(text)
        cdef xstring prev_xstr = xstr
        cdef ignore_case_alignment align = None
        cdef vector[Matched] vect
        cdef Matched m
        if self.trie.ignore_case:
            align = ignore_case_alignment(xstr)
            xstr = align.lowercase
        cdef byte_t *bytes_ = xstr.bytes_
        cdef int byte_num = xstr.byte_num
        cdef int nid_, i, chr_
        cdef int nid = 0
        cdef byte_t b
        cdef bool return_all_ = return_all

        if sep is None:
            for i in range(byte_num):
                b = bytes_[i]
                while True:
                    nid_ = self.trie.child(nid, b)
                    if nid_ >= 0:
                        nid = nid_
                        vect.clear()
                        self.__fetch(i, nid, vect, return_all_)
                        for m in vect:
                            yield m.val, ignore_case_offset(align, xstr, m.start), ignore_case_offset(align, xstr, m.end - 1) + 1
                        break
                    if nid == 0:
                        break
                    nid = self.fails[nid]
        else:
            for i in range(byte_num):
                b = bytes_[i]
                while True:
                    nid_ = self.trie.child(nid, b)
                    if nid_ >= 0:
                        nid = nid_
                        if i + 1 < byte_num:
                            chr_ = xstr.chars[xstr.char_idx_of_byte[i + 1]]
                            if chr_ not in sep:
                                break
                        vect.clear()
                        self.__fetch(i, nid, vect, return_all_)
                        for m in vect:
                            if m.start > 0:
                                chr_ = xstr.chars[xstr.char_idx_of_byte[m.start - 1]]
                                if chr_ not in sep:
                                    continue
                            yield m.val, ignore_case_offset(align, xstr, m.start), ignore_case_offset(align, xstr, m.end - 1) + 1
                        break
                    if nid == 0:
                        break
                    nid = self.fails[nid]

    def __reduce__(self):
        return (new_object, (AC,), self.__getstate__())

    def __getstate__(self):
        return (self.trie,
            int(ac_binary_version),
            array_to_bytes(<char*>self.fails, self.trie.array_size * sizeof(int)),
            array_to_bytes(<char*>self.key_lens, self.trie.leaf_size * sizeof(unsigned int)),
        )

    def __setstate__(self, data):
        self.trie, version, fails, key_lens = data
        if isinstance(version, int) and version > ac_binary_version:
            raise Exception("data is generated by new cyac, please update cyac module.")
        # if self.output != NULL:
        #     free(self.output)
        if self.fails != NULL:
            free(self.fails)
        if self.key_lens != NULL:
            free(self.key_lens)
        # self.output = <OutNode*> bytes_to_array(output, self.trie.array_size * sizeof(OutNode))
        self.fails = <int*> bytes_to_array(fails, self.trie.array_size * sizeof(int))
        self.key_lens = <unsigned int*> bytes_to_array(key_lens, self.trie.leaf_size * sizeof(unsigned int))


    cdef write(self, FILE* ptr_fw):
        cdef uint32_t magic = magic_number
        cdef int version = ac_binary_version
        fwrite(<void*>&magic, sizeof(magic), 1, ptr_fw)
        fwrite(<void*>&version, sizeof(version), 1, ptr_fw)
        cdef int size = self.buff_size()
        fwrite(<void*>&size, sizeof(size), 1, ptr_fw)
        self.trie.write(ptr_fw)
        # fwrite(<void*>self.output, sizeof(OutNode), self.trie.array_size, ptr_fw)
        fwrite(<void*>self.fails, sizeof(int), self.trie.array_size, ptr_fw)
        fwrite(<void*>self.key_lens, sizeof(unsigned int), self.trie.leaf_size, ptr_fw)

    def save(self, fname):
        """
        save data into binary file
        """
        cdef FILE *ptr_fw
        cdef bytes bfname = fname.encode("utf8")
        cdef char* path = bfname
        ptr_fw = fopen(path, "wb")
        if ptr_fw==NULL:
            raise Exception("Cannot open file: %s" % fname)
        self.write(ptr_fw)
        fclose(ptr_fw)


    def buff_size(self):
        """
        return the memory size of buffer needed for exporting to external buffer.
        """
        return self.trie.buff_size() + sizeof(uint32_t) + sizeof(int) + sizeof(int) + (sizeof(int)) * self.trie.array_size + sizeof(unsigned int) * self.trie.leaf_size


    def to_buff(self, buff):
        """
        copy data into buff
        Args:
            buff: object satisfy Python buff protocol
        """
        check_buffer(buff)
        cdef Py_buffer view
        if PyObject_GetBuffer(buff, &view, PyBUF_WRITABLE) != 0:
            raise Exception("cannot get writable buffer: https://docs.python.org/zh-cn/3/c-api/buffer.html")
        if self.buff_size() < view.len:
            raise Exception("buff size is smaller than needed.")
        cdef void* buf = view.buf
        self._to_buff(buf)
        PyBuffer_Release(&view)


    @classmethod
    def from_buff(cls, buff, copy = True):
        """
        init ac from buff
        Args:
            buff: object satisfy Python buff protocol https://docs.python.org/zh-cn/3/c-api/buffer.html
            copy: whether copy data, by default, it copies data from buff
        """
        check_buffer(buff)
        cdef Py_buffer* view = <Py_buffer*>malloc(sizeof(Py_buffer))
        cdef Py_buffer* view2 = <Py_buffer*>malloc(sizeof(Py_buffer))
        if PyObject_GetBuffer(buff, view, PyBUF_SIMPLE) != 0 or PyObject_GetBuffer(buff, view2, PyBUF_SIMPLE) != 0:
            free(view)
            free(view2)
            raise Exception("cannot get readable buffer: https://docs.python.org/zh-cn/3/c-api/buffer.html")
        ac = ac_from_buff(view.buf, view.len, copy)
        if copy:
            ac.buff = NULL
            ac.trie.buff = NULL
            PyBuffer_Release(view)
            PyBuffer_Release(view2)
            free(view)
            free(view2)
        else:

            ac.buff = view
            ac.trie.buff = view2
        return ac

    cdef void _to_buff(self, void* buf):
        cdef int offset = 0

        cdef char* buff = <char*>buf
        cdef uint32_t magic = magic_number
        memcpy(buff, <void*>&magic, sizeof(magic))
        offset += sizeof(magic)

        cdef int version = ac_binary_version
        memcpy(buff + offset, <void*>&version, sizeof(version))
        offset += sizeof(version)

        cdef int size = self.buff_size()
        memcpy(buff + offset, <void*>&size, sizeof(size))
        offset += sizeof(size)

        self.trie._to_buff(buff + offset)
        offset += self.trie.buff_size()

        # memcpy(buff + offset, <void*>self.output, sizeof(OutNode) * self.trie.array_size)
        # offset += sizeof(OutNode) * self.trie.array_size

        memcpy(buff + offset, <void*>self.fails, sizeof(int) * self.trie.array_size)
        offset += sizeof(int) * self.trie.array_size

        memcpy(buff + offset, <void*>self.key_lens, sizeof(unsigned int) * self.trie.leaf_size)
        offset += sizeof(unsigned int) * self.trie.leaf_size


cdef AC ac_from_buff(void* buf, int buf_size, bool copy):

    cdef char* buff = <char*>buf
    cdef int offset = 0
    cdef AC ac = new_object(AC)
    cdef uint32_t magic
    cdef int size, ac_version
    memcpy(<void*>&magic, buff, sizeof(magic))
    if magic != magic_number and magic != legacy_magic_number:
        raise Exception("invalid data, magic number is not correct")
    offset += sizeof(magic)

    if magic == magic_number:
        memcpy(<void*>&ac_version, buff + offset, sizeof(ac_version))
        if ac_binary_version < ac_version:
            raise Exception("reading newer binary file, please update cyac")
        offset += sizeof(ac_version)

    memcpy(&size, buff + offset, sizeof(int))
    offset += sizeof(int)
    if size > buf_size:
        raise Exception("invalid data, buf size is not correct")
    trie = trie_from_buff(buff + offset, buf_size - offset, copy)
    offset += trie.buff_size()
    if copy:
        if magic == legacy_magic_number:
            offset += sizeof(OutNode) * trie.array_size
        # ac.output = <OutNode*>malloc(sizeof(OutNode) * trie.array_size)
        # memcpy(<void*>ac.output, buff + offset, sizeof(OutNode) * trie.array_size)
        # offset += sizeof(OutNode) * trie.array_size

        ac.fails = <int*>malloc(sizeof(int) * trie.array_size)
        memcpy(<void*>ac.fails, buff + offset, sizeof(int) * trie.array_size)
        offset += sizeof(int) * trie.array_size

        ac.key_lens = <unsigned int*>malloc(sizeof(unsigned int) * trie.leaf_size)
        memcpy(<void*>ac.key_lens, buff + offset, sizeof(unsigned int) * trie.leaf_size)
        offset += sizeof(unsigned int) * trie.leaf_size
    else:
        if magic == legacy_magic_number:
            offset += sizeof(OutNode) * trie.array_size
        # ac.output = <OutNode*>(buff + offset)
        # offset += sizeof(OutNode) * trie.array_size

        ac.fails = <int*>(buff + offset)
        offset += sizeof(int) * trie.array_size

        ac.key_lens = <unsigned int*>(buff + offset)
        offset += sizeof(unsigned int) * trie.leaf_size

    ac.trie = trie
    return ac



