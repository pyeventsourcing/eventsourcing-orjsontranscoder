# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
cdef class CTranscoding:
    cdef object name, type
    cdef object encode(self, object obj)
    cdef object decode(self, object data)
