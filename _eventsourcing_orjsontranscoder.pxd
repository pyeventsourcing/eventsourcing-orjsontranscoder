# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
cdef class CTranscoding:
    cpdef object type(self)
    cpdef str name(self)
    cpdef object encode(self, object obj)
    cpdef object decode(self, object data)
