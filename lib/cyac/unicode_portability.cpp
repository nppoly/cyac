#include <Python.h>

#if PY_MAJOR_VERSION < 3
static int _PyUnicode_ToLowerFull(Py_UCS4 ch, Py_UCS4* res){
    res[0] = _PyUnicode_ToLowercase(ch);
    return 1;
}
#endif