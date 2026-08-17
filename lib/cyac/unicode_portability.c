#ifndef __UNICODE_PORTABILITY_H__
#define __UNICODE_PORTABILITY_H__
#include <Python.h>

#if PY_MAJOR_VERSION < 3
extern "C" {
    static int _PyUnicode_ToLowerFull(Py_UCS4 ch, Py_UCS4* res){
        res[0] = _PyUnicode_ToLowercase(ch);
        return 1;
    }
}
#endif

#if PY_VERSION_HEX >= 0x030D0000
#ifdef __cplusplus
extern "C" {
#endif
static int _PyUnicode_ToLowerFull(Py_UCS4 ch, Py_UCS4* res)
{
    PyObject *u;
    PyObject *lower;
    Py_ssize_t n;
    Py_ssize_t i;
    Py_ssize_t dummy;

    u = PyUnicode_FromOrdinal((int)ch);
    if (u == NULL) {
        PyErr_Clear();
        res[0] = ch;
        return 1;
    }

    lower = PyUnicode_Lower(u);
    Py_DECREF(u);
    if (lower == NULL) {
        PyErr_Clear();
        res[0] = ch;
        return 1;
    }

    n = PyUnicode_GetLength(lower);
    if (n > 2) {
        n = 2;
    }
    for (i = 0; i < n; i++) {
        res[i] = PyUnicode_ReadChar(lower, i, &dummy);
    }

    Py_DECREF(lower);
    return (int)n;
}
#ifdef __cplusplus
}
#endif
#endif
#endif
