#cython: language_level=3, boundscheck=False, overflowcheck=False
#    , profile=True, linetrace=True

from libc.stdlib cimport malloc, free, realloc
from libc.string cimport memcpy 
from libc.stdio cimport FILE, fopen, fwrite, fclose
from libcpp.string cimport string
from cython cimport typeof
from .util cimport check_buffer, magic_number
from cpython.buffer cimport PyObject_GetBuffer, PyObject_CheckBuffer, PyBuffer_Release, PyBuffer_GetPointer, Py_buffer, PyBUF_WRITABLE, PyBUF_SIMPLE

def new_object(obj):
    return obj.__new__(obj)

cdef extern from "<algorithm>" namespace "std" nogil:
    void reverse[T](T a, T b);

cdef int CHILD_NUM_MASK = (1 << 9) -1
cdef int END_MASK = 1 << 9
cdef int value_limit = (1 << 31) - 1

cdef inline int ignore_case_byte_index_mapping(ignore_case_alignment align, int byte_idx):
    if align is None:
        return byte_idx
    cdef int char_offset = align.lowercase.char_idx_of_byte[byte_idx]
    char_offset = align.lowercase_char_index_mapping[char_offset]
    cdef int ret = align.original.char_offsets[char_offset]
    return ret


cdef class Trie(object):

    """Trie
    Attributes:
        ignore_case (bool): if the trie should be case sensitive or not. 
            if it's true, all inserted keys will be converted to lowercase.
            Defaults to False
        ordered     (bool): the child list of each node should be ordered.
            Defaults to False
    Examples:
        >>> # import module
        >>> from cyac import Trie
        >>> # Create an object of Trie
        >>> trie = Trie()
        >>> # add keywords
        >>> keys = [u'abc', u'cde', u'efg']
        >>> for key in keys:
        >>>     trie.insert(key)
    """

    cdef inline void _node_init(self, Node* n, int value, int check):
        n.value = value
        n.check = check
        n.flags = 0
        n.child = 0
        n.sibling = 0

    cdef inline int _node_child_num(self, Node *n):
        return n.flags
    
    cdef inline void _node_set_child_num(self, Node *n, int val):
        n.flags = val

    cdef inline int _node_base(self, Node *n):
        return -(n.value + 1)

    cdef inline bool _node_is_child(self, Node *n, int par):
        return n.check == par

    cdef inline byte_t* _node_child_ptr(self, Node *n):
        return &n.child

    cdef inline byte_t* _node_sibling_ptr(self, Node *n):
        return &n.sibling

    
    cdef inline void _block_init(self, Block* block, int prev, int next_, int trial, int ehead, int num, int reject):
        block.prev = prev
        block.next_ = next_
        block.trial = trial
        block.ehead = ehead
        block.num = num
        block.reject = reject

    def arr_size(self):
        return self.array_size

    property key_num:
        def __get__(self):
            return self.key_num
    
    property size:
        def __get__(self):
            return self.key_num

    def __len__(self):
        return self.key_num
    
    cdef inline Node* _node(self, int nid):
        return self.array + nid

    def __cinit__(self, bool ignore_case = False, bool ordered = False):
        cdef int i
        self.last_remove_leaf = value_limit
        self.ignore_case = ignore_case
        self.ordered = ordered
        self.capacity = 256
        self.key_num = 0
        self.leaf_size = 0
        self.key_capacity = self.capacity
        self.leafs = <int*> malloc(self.key_capacity * sizeof(int))
        self.array = <Node*> malloc(self.capacity * sizeof(Node))
        self.array_size = self.capacity
        self.blocks = <Block*> malloc((self.capacity >> 8) * sizeof(Block))
        self.max_trial = 1
        self._node_init(self.array, -1, -1)
        for i in range(1, 256):
            self._node_init(&self.array[i], -(i - 1), -(i + 1))
        self.array[1].value = -255
        self.array[255].check = -1
        self._block_init(self.blocks, 0, 0, 0, 1, 256, 257)
        for i in range(0, 257):
            self.reject[i] = i + 1
        
        self.bheadF = 0
        self.bheadC = 0
        self.bheadO = 0
        self.buff = NULL
    
    cdef inline int _get(self, byte_t *key, int key_size, int from_, int start):
        cdef int pos, value, to
        for pos in range(start, key_size):
            value = self.array[from_].value
            if value >= 0 and value != value_limit:
                to = self.follow(from_, 0)
                self.array[to].value = value
                self.leafs[value] = to
            from_ = self.follow(from_, key[pos])
        if self.array[from_].value < 0:
            return self.follow(from_, 0)
        else:
            return from_

    cdef inline int follow(self, int from_, byte_t label):
        cdef int base = self._node_base(&self.array[from_])
        cdef int to = base ^ label
        cdef bool has_child
        if base < 0  or self.array[to].check < 0:
            has_child = base >= 0 and self.array[base ^ self.array[from_].child].check == from_
            to = self.pop_enode(base, label, from_)
            self.push_sibling(from_, to^label, label, has_child)
        elif self.array[to].check != from_:
            to = self.resolve(from_, base, label)
        return to
    
    cdef inline void pop_block(self, int bi, int* head_in, bool last):
        if last:
            head_in[0] = 0
        else:
            self.blocks[self.blocks[bi].prev].next_ = self.blocks[bi].next_
            self.blocks[self.blocks[bi].next_].prev = self.blocks[bi].prev
            if bi == head_in[0]:
                head_in[0] = self.blocks[bi].next_
    
    cdef inline void push_block(self, int bi, int* head_out, bool empty):
        cdef Block *tail_out
        cdef Block *b = self.blocks + bi
        if empty:
            head_out[0] = bi
            b.prev = bi
            b.next_ = bi
        else:
            tail_out = &self.blocks[head_out[0]]
            b.prev = tail_out[0].prev
            b.next_ = head_out[0]
            self.blocks[tail_out.prev].next_ = bi
            head_out[0] = bi
            tail_out[0].prev = bi

    cdef int add_block(self):
        cdef int i
        if self.array_size == self.capacity:
            self.capacity *= 2
            self.blocks = <Block*> realloc(self.blocks, sizeof(Block) * (self.capacity >> 8))
            self.array = <Node*> realloc(self.array, sizeof(Node) * self.capacity)
        self._block_init(&self.blocks[self.array_size >> 8], 0,0,0, self.array_size, 256, 257)
        for i in range(0, 256):
            self._node_init(
                &self.array[self.array_size + i],
                 -(((i + 255) & 255) + self.array_size), 
                 -(((i + 1) & 255) + self.array_size))
        self.push_block(self.array_size >> 8, &self.bheadO, self.bheadO == 0)
        self.array_size += 256
        return (self.array_size >> 8) - 1

    cdef inline void transfer_block(self, int bi, int* head_in, int* head_out):
        self.pop_block(bi, head_in, bi == self.blocks[bi].next_)
        self.push_block(bi, head_out, head_out[0] == 0 and self.blocks[bi].num != 0)

    cdef inline int pop_enode(self, int base, byte_t label, int from_):
        cdef int e = self.find_place() if base < 0 else (base ^ label)
        cdef int bi = e >> 8
        cdef Node *n = &self.array[e]
        cdef Block *b = &self.blocks[bi]
        b.num -= 1
        if b.num == 0:
            if bi != 0:
                self.transfer_block(bi, &self.bheadC, &self.bheadF)
        else:
            self.array[-n.value].check = n.check
            self.array[-n.check].value = n.value
            if e == b.ehead:
                b.ehead = -n.check
            if bi != 0 and b.num == 1 and b.trial != self.max_trial:
                self.transfer_block(bi, &self.bheadO, &self.bheadC)
        n.value = value_limit
        n.check = from_
        if base < 0:
            self.array[from_].value = -(e^label) - 1
        return e

    cdef void push_enode(self, int e):
        cdef Node *e_ptr = &self.array[e]
        cdef int bi = e >> 8
        cdef Block *b = &self.blocks[bi]
        cdef int prev, next_
        cdef Node *prev_ptr
        b.num += 1
        if b.num == 1:
            b.ehead = e
            e_ptr[0].value = -e
            e_ptr[0].check = -e
            if bi != 0:
                self.transfer_block(bi, &self.bheadF, &self.bheadC)
        else:
            prev = b.ehead
            prev_ptr = &self.array[prev]
            next_ = -prev_ptr[0].check
            e_ptr[0].value = -prev
            e_ptr[0].check = -next_
            prev_ptr[0].check = -e
            self.array[next_].value = -e
            if b.num == 2 or b.trial == self.max_trial:
                if bi != 0:
                    self.transfer_block(bi, &self.bheadC, &self.bheadO)
            b.trial = 0
        if b.reject < self.reject[b.num]:
            b.reject = self.reject[b.num]
        e_ptr[0].child = 0
        e_ptr[0].sibling = 0
        e_ptr[0].flags = 0
    
    cdef inline void push_sibling(self, int from_, int base, byte_t label, bool has_child):
        cdef Node *from_ptr = &self.array[from_]
        cdef byte_t *child_ptr = self._node_child_ptr(from_ptr)
        cdef bool keep_order = (label > child_ptr[0]) if self.ordered else (child_ptr[0] == 0)
        if has_child and keep_order:
            child_ptr = self._node_sibling_ptr(&self.array[base ^ child_ptr[0]])
            while self.ordered and child_ptr[0] != 0 and child_ptr[0] < label:
                c = self._node_sibling_ptr(&self.array[base ^ child_ptr[0]])
        
        self.array[base^label].sibling = child_ptr[0]
        child_ptr[0] = label
        self._node_set_child_num(from_ptr, self._node_child_num(from_ptr) + 1)

    cdef inline void pop_sibling(self, int from_, byte_t label):
        cdef Node *from_ptr = &self.array[from_]
        cdef int base = self._node_base(&from_ptr[0])
        cdef byte_t *child_ptr = self._node_child_ptr(from_ptr)
        while child_ptr[0] != label:
            child_ptr = self._node_sibling_ptr(&self.array[base ^ child_ptr[0]])
        child_ptr[0] = self.array[base ^ child_ptr[0]].sibling
        self._node_set_child_num(from_ptr, self._node_child_num(from_ptr) - 1)


    cdef inline bool consult(self, Node *nref, Node *pref):
        return self._node_child_num(nref) < self._node_child_num(pref)

    cdef bool has_label(self, int id_, byte_t label):
        return self.child(id_, label) >= 0

    cdef inline int child(self, int id_, byte_t label):
        cdef Node *parent_ptr = &self.array[id_]
        cdef int base = self._node_base(&parent_ptr[0])
        cdef int cid = base ^ label
        # print("cid[%s][%s] = %s, check[%s] = %s" % (id_, label, cid, cid, self.array[cid].check))
        if cid < 0  or  cid >= self.array_size  or not self._node_is_child(&self.array[cid], id_):
            return -1 
        return cid

    cdef inline int children(self, int id_, byte_t *labels, int *children_arr, int first_n):
        cdef Node *parent_ptr = &self.array[id_]
        cdef int base = self._node_base(&parent_ptr[0])
        cdef byte_t s = parent_ptr[0].child
        if s == 0 and base > 0:
            s = self.array[base].sibling
        cdef int num = 0
        while s != 0:
            to = base ^ s
            if to < 0:
                break
            labels[num] = s
            children_arr[num] = to
            num += 1
            if num >= first_n:
                break
            s = self.array[to].sibling
        return num

    
    cdef inline int sibling(self, int to):
        if to < 0:
            return -1
        cdef int base = self._node_base(&self.array[self.array[to].check])
        cdef byte_t s = self.array[to].sibling
        if s == 0:
            return -1
        to = base ^ s
        return to

    # 返回children个数
    cdef int set_child(self, int base, byte_t c, byte_t label, bool append_label, byte_t *children):
        cdef int idx = 0
        if c == 0:
            children[idx] = c
            idx += 1
            c = self.array[base ^ c].sibling
        
        if self.ordered:
            while c != 0 and c <= label:
                children[idx] = c
                idx += 1
                c = self.array[base ^c].sibling
        
        if append_label:
            children[idx] = label
            idx += 1
        
        while c != 0:
            children[idx] = c
            idx += 1
            c = self.array[base ^ c].sibling
        return idx

    cdef inline int find_place(self):
        if self.bheadC != 0:
            return self.blocks[self.bheadC].ehead 
        if self.bheadO != 0:
            return self.blocks[self.bheadO].ehead 
        return self.add_block() << 8

    cdef inline int find_places(self, byte_t *child, int child_num):
        cdef int bi = self.bheadO
        cdef int bz, e, i
        cdef Block *b
        if bi != 0:
            bz = self.blocks[self.bheadO].prev
            nc = child_num
            while True:
                b = &self.blocks[bi]
                if b.num >= nc  and  nc < b.reject:
                    e = b.ehead
                    while True:
                        base = e ^ child[0]
                        i = 0
                        for i in range(0, child_num):
                            c = child[i]
                            if not self.array[base ^ c].check < 0:
                                break
                            if i == child_num - 1:
                                b.ehead = e
                                return e
                        e = - self.array[e].check
                        if e == b.ehead:
                            break
                b.reject = nc
                if b.reject < self.reject[b.num]:
                    self.reject[b.num] = b.reject
                bin_ = b.next_
                b.trial += 1
                if b.trial == self.max_trial:
                    self.transfer_block(bi, &self.bheadO, &self.bheadC)
                if bi == bz:
                    break
                bi = bin_
        return self.add_block() << 8

    cdef inline int resolve(self, int from_n, int base_n, byte_t label_n):
        cdef int to_pn = base_n ^ label_n
        cdef int from_p = self.array[to_pn].check
        cdef Node *from_p_ptr = &self.array[from_p]
        cdef Node *from_n_ptr = &self.array[from_n]
        cdef int base_p = self._node_base(&self.array[from_p])
        # cdef Node *to_ptr 
        cdef Node *to_ptr_
        cdef Node *ptr
        cdef Node *n_
        cdef Node *from_ptr
        cdef bool flag = self.consult(from_n_ptr, from_p_ptr)
        cdef byte_t children[256]
        cdef int from_, i, child_num, base
        if flag:
            child_num = self.set_child(base_n, from_n_ptr[0].child, label_n, True, children)
        else:
            child_num = self.set_child(base_p, from_p_ptr[0].child, 255, False, children)
        base = self.find_place() if child_num == 1 else self.find_places(children, child_num)
        base ^= children[0]
        if flag:
            from_ = from_n
            from_ptr = &self.array[from_n]
            base_ = base_n
        else:
            from_ = from_p
            from_ptr = &self.array[from_p]
            base_ = base_p
        if flag  and  children[0] == label_n:
            from_ptr[0].child = label_n
        from_ptr[0].value = -base - 1
        for i in range(0, child_num):
            chl = children[i]
            to = self.pop_enode(base, chl, from_)
            to_ = base_ ^ chl
            n = &self.array[to]
            if i == child_num - 1:
                n.sibling = 0
            else:
                n.sibling = children[i + 1]
            if flag  and  to_ == to_pn:
                continue
            n_ = &self.array[to_]
            n.value = n_.value
            if n_.value >= 0  and  n_.value != value_limit:
                self.leafs[n_.value] = to
            n.flags = n_.flags
            if n.value < 0  and  chl != 0:
                c = self.array[to_].child
                self.array[to].child = c
                ptr = &self.array[self._node_base(n) ^ c]
                ptr[0].check = to
                c = ptr[0].sibling
                while c != 0:
                    ptr = &self.array[self._node_base(n)^ c]
                    ptr[0].check = to
                    c = ptr[0].sibling
            
            if not flag and to_ == from_n:
                from_n = to
            if not flag and to_ == to_pn:
                self.push_sibling(from_n, to_pn ^ label_n, label_n, True)
                to_ptr_ = &self.array[to_]
                to_ptr_[0].child = 0
                n_.value = value_limit
                n_.check = from_n
            else:
                self.push_enode(to_)
        if flag:
            return base ^ label_n
        else:
            return to_pn
    
    cdef inline int jump(self, byte_t byte, int from_):
        from_ptr = &self.array[from_]
        if from_ptr[0].value >= 0:
            return -1
        to = self._node_base(&from_ptr[0]) ^ byte
        if self.array[to].check != from_:
            return -1
        return to

    cdef inline int jump_bytes(self, byte_t *bytes_, int byte_num, int from_):
        cdef int i
        cdef byte_t byte
        for i in range(byte_num):
            byte = bytes_[i]
            from_ = self.jump(byte, from_)
            if from_ < 0:
                return -1
        return from_

    cdef inline int jump_uchar(self, xstring text, int char_idx, int from_):
        cdef byte_t *start = text.bytes_ + text.char_offsets[char_idx]
        cdef int num = text.char_offsets[char_idx+1] - text.char_offsets[char_idx]
        return self.jump_bytes(start, num, from_)


    cdef bytes substring(self, int id_, int start_id): # end_id is included, start_id is excluded
        cdef stringbuf sb
        cdef int from_
        cdef byte_t chr_
        while id_ > 0 and id_ != start_id:
            from_ = self.array[id_].check
            if from_ < 0:
                return None
            chr_ = self._node_base(&self.array[from_]) ^ id_
            if chr_ >= 256:
                return None
            if chr_ != 0:
                sb.put(chr_)
            id_ = from_
        if id_ != start_id:
            return None
        cdef string ret = sb.to_string()
        reverse(ret.begin(), ret.end())
        return ret

    cdef bytes key(self, int id_):
        return self.substring(id_, 0)

    cdef inline int value(self, int id_):
        cdef Node *ptr = &self.array[id_]
        cdef int val = ptr[0].value
        if val >= 0:
            return val
        cdef int to = self._node_base(ptr)
        cdef Node *to_ptr = &self.array[to]
        if to_ptr[0].check == id_  and  to_ptr[0].value >= 0  and  to_ptr[0].value != value_limit:
            return to_ptr[0].value
        return -1

    cdef inline bool has_value(self, int id_):
        cdef Node *ptr = &self.array[id_]
        cdef int val = ptr[0].value
        if val >= 0:
            return True
        cdef int to = self._node_base(ptr)
        cdef Node *to_ptr = &self.array[to]
        if to_ptr[0].check == id_  and  to_ptr[0].value >= 0:
            return True
        return False

    def __contains__(self, unicode t):
        return self.get(t) >= 0

    def __iter__(self):
        cdef int id_
        cdef int lnode
        for id_ in range(0,self.leaf_size):
            lnode = self.leafs[id_]
            if lnode >= 0:
                yield id_

    def __getitem__(self, sid):
        """
        get key by id, or get id by key, raise exception if cannot find.
        Args:
            sid (unicode | int): key or id

        Examples:
            >>> trie["python"]
        Raises:
            AttributeError: If `sid` is not unicode or int
        """
        cdef int lnode
        if isinstance(sid, int):
            if sid >= self.leaf_size:
                raise AttributeError("index out of range: %d >= %d" % (sid, self.leaf_size))
            lnode = self.leafs[sid]
            if lnode < 0:
                raise AttributeError("Cannot find with id: %d" % sid)
            bs = self.key(lnode)
            bs = bs.decode("utf8")
            return bs
        elif isinstance(sid, unicode):
            ret = self.get(sid)
            if ret < 0:
                raise Exception("Cannot find: %s" % repr(sid))
            return ret
        raise AttributeError("Index type is not supported")

    cpdef int insert(self, unicode key):
        """insert key into the trie, return the id of this key.
        Args:
            key : string, Cannot be empty.
        Returns:
            id  : int
                The id is continuously increasing. you can use this id to index other values.
                If some key is removed, and a new key is inserted, the old key's id will be assigned to the new key.
        Examples:
            >>> trie.insert("python")
        """
        if self.ignore_case:
            key = key.lower()
        cdef bytes bkey = key.encode("utf8")
        cdef int bkey_len = len(bkey)
        if bkey_len == 0:
            return -1
        cdef byte_t *ckey = bkey
        val = self.get_bytes(ckey, bkey_len)
        if val >= 0:
            return val
        cdef int p = self._get(ckey, bkey_len, 0, 0)
        cdef int id_
        if self.last_remove_leaf != value_limit:
            id_ = self.last_remove_leaf
            self.last_remove_leaf = -(self.leafs[id_] + 1)
        else:
            id_ = self.leaf_size
            if self.leaf_size == self.key_capacity:
                self.key_capacity *= 2
                self.leafs = <int*> realloc(self.leafs, self.key_capacity*sizeof(int))
            self.leaf_size += 1
        cdef Node *p_ptr = &self.array[p]
        p_ptr[0].value = id_
        self.leafs[id_] = p
        self.key_num += 1
        return id_

    cpdef int remove(self, unicode key):
        """
        remove the given key from the trie
        Args:
            key : string
                keyword that you want to remove if it's present.
        Returns:
            id : bool
                the id of key.
                if this key doesn't exist in trie, then return -1.
        Examples:
            >>> trie.remove("python")
        """
        if self.ignore_case:
            key = key.lower()
        cdef Node *from_ptr
        cdef bytes bkey = key.encode("utf8")
        cdef byte_t* cbkey = bkey
        cdef int to = self.jump_bytes(cbkey, len(bkey), 0)
        cdef int base, from_
        cdef byte_t label
        if to < 0:
            return -1
        cdef int vk = self.value(to)
        if vk < 0:
            return -1
        cdef Node *to_ptr = &self.array[to]
        if to_ptr[0].value < 0:
            base = self._node_base(to_ptr)
            if self.array[base].check == to:
                to = base
        while to > 0:
            to_ptr = &self.array[to]
            from_ = to_ptr[0].check
            from_ptr = &self.array[from_]
            base = self._node_base(from_ptr)
            label = (to ^ base)
            if to_ptr[0].sibling != 0  or  from_ptr[0].child != label:
                self.pop_sibling(from_, label)
                self.push_enode(to)
                break
            self.push_enode(to)
            to = from_
        self.key_num -= 1
        self.leafs[vk] = -self.last_remove_leaf - 1
        self.last_remove_leaf = vk
        return vk

    cpdef int get(self, unicode key):
        """
        get id of given key, if it doesn't exist, return -1.
        Args:
            key : string
                keyword that you want to get if it's present.
        Returns:
            id : bool
                the id of key.
                if this key doesn't exist in trie, then return -1.
        Examples:
            >>> trie.get("python")
        """
        if self.ignore_case:
            key = key.lower()
        cdef bytes bkey = key.encode("utf8")
        cdef byte_t* ckey = bkey
        return self.get_bytes(ckey, len(bkey))

    cdef inline int get_bytes(self, byte_t* key, int size):
        cdef int to = self.jump_bytes(key, size, 0)
        if to < 0:
            return -1
        cdef int vk = self.value(to)
        if vk < 0:
            return -1
        return vk


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
            >>> for id_, offset in trie.prefix("python"):
            >>>     print(id_, offset)
        """
        cdef ignore_case_alignment align = None
        cdef xstring xs = xstring(s)
        if self.ignore_case:
            align = ignore_case_alignment(xs)
            xs = align.lowercase
        cdef byte_t b
        cdef int node = 0
        cdef int bi
        for bi in range(xs.byte_num):
            b = xs.bytes_[bi]
            node = self.jump(b, node)
            if node >= 0:
                vk = self.value(node)
                if vk >= 0:
                    yield vk, ignore_case_offset(align, xs, bi) + 1
            else:
                break

    def predict(self, unicode s not None):
        """
        return the string in the trie which starts with given string
        Args:
            key : string
                keyword that you want to searh
        Iterates:
            predicts : id
        Examples:
            >>> for id_ in trie.predict("python"):
            >>>     print(id_)
        """
        cdef ignore_case_alignment align = None
        cdef xstring xs = xstring(s)
        if self.ignore_case:
            align = ignore_case_alignment(xs)
            xs = align.lowercase
        cdef int node = self.jump_bytes(xs.bytes_, xs.byte_num, 0)
        if node < 0:
            return
        cdef int cid, vk, idx
        cdef deque[int] q = deque[int]()
        cdef int child_num = 0
        cdef byte_t children[256]
        cdef int children_nodes[256]
        q.push_back(node)
        while q.size() > 0:
            node = q.front()
            q.pop_front()
            vk = self.value(node)
            if vk >= 0:
                yield vk
            num = self.children(node, children, children_nodes, 256)
            for idx in range(num):
                q.push_back(children_nodes[idx])

    def items(self):
        """
        return all key and id ordered by id
        Iterates:
            items : (unicode, int)
        Examples:
            >>> for key, id_ in trie.items():
            >>>     print(id_, key)
        """
        cdef int id_
        cdef int lnode
        for id_ in range(0,self.leaf_size):
            lnode = self.leafs[id_]
            if lnode >= 0:
                key_ = self.key(lnode)
                yield key_.decode("utf8"), id_


    def __dealloc__(self):
        if self.buff == NULL:
            free(self.leafs)
            free(self.array)
            free(self.blocks)
        else:
            PyBuffer_Release(self.buff)
            free(self.buff)
    
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
            >>> for id_, start_offset, end_offset in trie.match_longest("python", set([ord(" ")])):
            >>>     print(id_, start_offset, end_offset)
        """
        cdef ignore_case_alignment align = None
        cdef xstring xs = xstring(s)
        if self.ignore_case:
            align = ignore_case_alignment(xs)
            xs = align.lowercase
        cdef int offset = 0 # byte offset
        cdef int node = 0
        cdef int bi
        cdef int last_vk
        cdef int last_b
        while offset < xs.byte_num:
            last_vk = -1
            last_b = 0
            if sep is not None:
                while offset < xs.byte_num and xs.chars[xs.char_idx_of_byte[offset]] in sep:
                    offset += xs.char_byte_num(xs.char_idx_of_byte[offset])
                if offset >= xs.byte_num:
                    break
            node = 0
            for bi in range(offset, xs.byte_num):
                b = xs.bytes_[bi]
                node = self.jump(b, node)
                if node >= 0:
                    vk = self.value(node)
                    if vk >= 0:
                        if sep is not None:
                            if bi + 1 < xs.byte_num and xs.chars[xs.char_idx_of_byte[bi+1]] not in sep:
                                continue
                        last_vk = vk
                        last_b = bi
                else:
                    break
            if last_vk == -1:
                offset += xs.char_byte_num(xs.char_idx_of_byte[offset])
                if sep is not None:
                    while offset < xs.byte_num and xs.chars[xs.char_idx_of_byte[offset]] not in sep:
                        offset += xs.char_byte_num(xs.char_idx_of_byte[offset])
                continue
            yield last_vk, ignore_case_offset(align, xs, offset), ignore_case_offset(align, xs, last_b) + 1
            offset = last_b + 1

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
            >>> python_id = trie.insert("python")
            >>> text = trie.replace_longest("python", {python_id: "hahah"}, set([ord(" ")]))
        """
        cdef stringbuf sb
        cdef ignore_case_alignment align = None
        cdef xstring xs = xstring(s)
        cdef xstring prev_xs = xs
        if self.ignore_case:
            align = ignore_case_alignment(xs)
            xs = align.lowercase
        cdef int offset = 0 # byte offset
        cdef int node = 0
        cdef int bi
        cdef int last_vk = -1
        cdef int last_b = 0
        cdef int prev_offset, prev_offset2, offset2
        cdef byte_t *byte_code
        cdef bytes encoded_replaced
        cdef int char_byte_num
        cdef bool callback_list_or_dict = isinstance(callback, dict) or isinstance(callback, list)

        while offset < xs.byte_num:
            last_vk = -1
            last_b = 0
            if sep is not None:
                prev_offset = offset
                while offset < xs.byte_num and xs.chars[xs.char_idx_of_byte[offset]] in sep:
                    offset += xs.char_byte_num(xs.char_idx_of_byte[offset])
                if offset > prev_offset:
                    prev_offset2 = ignore_case_byte_index_mapping(align, prev_offset)
                    offset2 = ignore_case_byte_index_mapping(align, offset)
                    sb.write(<char*>prev_xs.bytes_ + prev_offset2, offset2 - prev_offset2)
                if offset >= xs.byte_num:
                    break
            node = 0
            for bi in range(offset, xs.byte_num):
                b = xs.bytes_[bi]
                node = self.jump(b, node)
                if node >= 0:
                    vk = self.value(node)
                    if vk >= 0:
                        if sep is not None:
                            if bi + 1 < xs.byte_num and xs.chars[xs.char_idx_of_byte[bi + 1]] not in sep:
                                continue
                        last_vk = vk
                        last_b = bi
                else:
                    break
            if last_vk == -1:
                prev_offset = offset
                offset += xs.char_byte_num(xs.char_idx_of_byte[offset])
                if sep is not None:
                    while offset < xs.byte_num and xs.chars[xs.char_idx_of_byte[offset]] not in sep:
                        offset += xs.char_byte_num(xs.char_idx_of_byte[offset])
                prev_offset2 = ignore_case_byte_index_mapping(align, prev_offset)
                offset2 = ignore_case_byte_index_mapping(align, offset)
                sb.write(<char*>prev_xs.bytes_ + prev_offset2, offset2 - prev_offset2)
                continue
            if callback_list_or_dict:
                replaced_ = callback[last_vk]
            else:
                replaced_ = callback(last_vk, ignore_case_offset(align, xs, offset), ignore_case_offset(align, xs, last_b) + 1)
            if isinstance(replaced_, unicode):
                encoded_replaced = replaced_.encode("utf8")
                byte_code = encoded_replaced
            elif isinstance(replaced_, bytes):
                encoded_replaced = replaced_
                byte_code = replaced_
            else:
                raise Exception("Replaced result should be bytes or unicode")
            sb.write(<char*>byte_code, len(encoded_replaced))
            offset = last_b + 1
        return sb.to_string().decode("utf8")

    def _dump_array(self, fname):
        """
        Used for debug
        """
        cdef Node* n
        cdef int i
        with open(fname, "w") as fo:
            for i in range(self.array_size):
                n = &self.array[i]
                fo.write("value=%s, check=%s, flags=%s, child=%s, sibling=%s\n" % (n.value, n.check, n.flags, n.child, n.sibling))

    def __reduce__(self):
        return (new_object, (Trie,), self.__getstate__())

    def __getstate__(self):
        return (self.key_num, self.key_capacity, 
            self.bheadF, self.bheadC, self.bheadO, 
            self.array_size, self.capacity, self.ordered, self.ignore_case,
            self.max_trial, self.leaf_size,
            array_to_bytes(<char*>self.array, self.array_size * sizeof(Node)),
            array_to_bytes(<char*>self.blocks, (self.array_size >> 8) * sizeof(Block)),
            array_to_bytes(<char*>self.leafs, self.leaf_size * sizeof(int)),
            array_to_bytes(<char*>self.reject, 257 * sizeof(int))
        )
    
    def __setstate__(self, data):
        self.key_num, self.key_capacity, \
        self.bheadF, self.bheadC, self.bheadO, \
        self.array_size, self.capacity, self.ordered, self.ignore_case, \
        self.max_trial, self.leaf_size, \
        array, blocks, leafs, reject = data
        if self.array != NULL:
            free(self.array)
        if self.blocks != NULL:
            free(self.blocks)
        if self.leafs != NULL:
            free(self.leafs)
        self.array = <Node*> bytes_to_array(array, (self.capacity * sizeof(Node)))
        self.blocks = <Block*> bytes_to_array(blocks, (self.capacity >> 8) * sizeof(Block))
        self.leafs = <int*> bytes_to_array(leafs, self.key_capacity * sizeof(int))
        cdef int i
        for i in range(257):
            self.reject[i] = reject[i]

    cdef write(self, FILE* ptr_fw):
        fwrite(<void*>&magic_number, sizeof(magic_number), 1, ptr_fw)
        cdef int size = self.buff_size()
        fwrite(&size, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.key_num, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.key_capacity, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.bheadF, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.bheadC, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.bheadO, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.array_size, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.capacity, sizeof(int), 1, ptr_fw)
        # for arm processor, we should align data in 4bytes.
        cdef int val = self.ordered
        fwrite(<void*>&val, sizeof(int), 1, ptr_fw)
        val = self.ignore_case
        fwrite(<void*>&val, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.max_trial, sizeof(int), 1, ptr_fw)
        fwrite(<void*>&self.leaf_size, sizeof(int), 1, ptr_fw)
        
        fwrite(<void*>self.array, sizeof(Node), self.capacity, ptr_fw)
        fwrite(<void*>self.blocks, sizeof(Block), self.capacity >> 8, ptr_fw)
        fwrite(<void*>self.leafs, sizeof(int), self.key_capacity, ptr_fw)
        fwrite(<void*>&self.reject, sizeof(int), 257, ptr_fw)

    def buff_size(self):
        """
        return the memory size of buffer needed for exporting to external buffer.
        """
        return sizeof(magic_number) +  sizeof(int) + sizeof(self.key_num) + sizeof(self.key_capacity) + sizeof(self.bheadF) + sizeof(self.bheadC) + sizeof(self.bheadO) + \
            sizeof(self.array_size) + sizeof(self.capacity) + sizeof(int) + sizeof(int) + sizeof(self.max_trial) + sizeof(self.leaf_size) + \
            sizeof(Node) * self.capacity + sizeof(Block) * (self.capacity >> 8) + sizeof(int) * self.key_capacity + sizeof(int) * 257


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

    cdef void _to_buff(self, void* buf):
        cdef int offset = 0

        cdef char* buff = <char*>buf
        memcpy(buff, <void*>&magic_number, sizeof(magic_number))
        offset += sizeof(magic_number)

        cdef int size = self.buff_size()
        memcpy(buff + offset, &size, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.key_num, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.key_capacity, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.bheadF, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.bheadC, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.bheadO, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.array_size, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.capacity, sizeof(int))
        offset += sizeof(int)

        cdef int val = self.ordered
        memcpy(buff + offset, <void*>&val, sizeof(int))
        offset += sizeof(int)

        val = self.ignore_case
        memcpy(buff + offset, <void*>&val, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.max_trial, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>&self.leaf_size, sizeof(int))
        offset += sizeof(int)

        memcpy(buff + offset, <void*>self.array, sizeof(Node) * self.capacity)
        offset += sizeof(Node) * self.capacity

        memcpy(buff + offset, <void*>self.blocks, sizeof(Block) * (self.capacity >> 8))
        offset += sizeof(Block) * (self.capacity >> 8)

        memcpy(buff + offset, <void*>self.leafs, sizeof(int) * self.key_capacity)
        offset += sizeof(int) * self.key_capacity

        memcpy(buff + offset, <void*>&self.reject, sizeof(int) * 257)
        

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
        cdef void *buf = view.buf
        self._to_buff(buf)
        PyBuffer_Release(&view)




    @classmethod
    def from_buff(cls, buff, copy = True):
        """
        init trie from buff
        Args:
            buff: object satisfy Python buff protocol https://docs.python.org/zh-cn/3/c-api/buffer.html
            copy: whether copy data, by default, it copies data from buff
        """
        check_buffer(buff)
        cdef Py_buffer* view = <Py_buffer*>malloc(sizeof(Py_buffer))
        if PyObject_GetBuffer(buff, view, PyBUF_SIMPLE) != 0:
            free(view)
            raise Exception("cannot get readable buffer: https://docs.python.org/zh-cn/3/c-api/buffer.html")
        cdef Trie trie = trie_from_buff(view.buf, view.len, copy)
        if copy:
            trie.buff = NULL
            PyBuffer_Release(view)
            free(view)
        else:
            trie.buff = view
        return trie


cdef Trie trie_from_buff(void* buf, int buf_size, bool copy):
    cdef int offset = 0
    cdef Trie trie = new_object(Trie)
    cdef int magic, size
    cdef char* buff = <char*>buf
    memcpy(buff, <void*>&magic, sizeof(magic))
    if magic != magic_number:
        raise Exception("invalid data, magic number is not correct")
    offset += sizeof(magic)

    memcpy(&size, buff + offset, sizeof(int))
    offset += sizeof(int)
    if size > buf_size:
        raise Exception("invalid data, buf size is not correct")

    cdef int value = 0
    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.key_num = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.key_capacity = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.bheadF = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.bheadC = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.bheadO = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.array_size = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.capacity = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.ordered = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.ignore_case = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.max_trial = value
    offset += sizeof(int)

    memcpy(<void*>&value, buff + offset, sizeof(int))
    trie.leaf_size = value
    offset += sizeof(int)

    if copy:
        trie.array = <Node*>malloc(sizeof(Node) * trie.capacity)
        memcpy(<void*>trie.array, buff + offset, sizeof(Node) * trie.capacity)
        offset += sizeof(Node) * trie.capacity

        trie.blocks = <Block*>malloc(sizeof(Block) * (trie.capacity >> 8))
        memcpy(<void*>trie.blocks, buff + offset, sizeof(Block) * (trie.capacity >> 8))
        offset += sizeof(Block) * (trie.capacity >> 8)

        trie.leafs = <int*>malloc(sizeof(int) * trie.key_capacity)
        memcpy(<void*>trie.leafs, buff + offset, sizeof(int) * trie.key_capacity)
        offset += sizeof(int) * trie.key_capacity
    else:
        trie.array =  <Node*>(buff + offset)
        offset += sizeof(Node) * trie.capacity

        trie.blocks = <Block*>(buff + offset)
        offset += sizeof(Block) * (trie.capacity >> 8)

        trie.leafs = <int*>(buff + offset)
        offset += sizeof(int) * trie.key_capacity


    memcpy(<void*>&trie.reject, buff + offset, sizeof(int) * 257)
    return trie







