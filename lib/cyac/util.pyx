from cpython.buffer cimport PyObject_GetBuffer, PyObject_CheckBuffer, PyBuffer_Release, PyBuffer_GetPointer, Py_buffer, PyBUF_WRITABLE, PyBUF_SIMPLE

cdef void check_buffer(buff):
    if PyObject_CheckBuffer(buff) == 0:
        raise Exception("the argument doesn't support buff protocol https://docs.python.org/zh-cn/3/c-api/buffer.html")