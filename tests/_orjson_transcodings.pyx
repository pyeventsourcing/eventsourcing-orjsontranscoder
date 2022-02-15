# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
from eventsourcing.tests.persistence import (
    CustomType1,
    CustomType2,
    MyDict,
    MyInt,
    MyList,
    MyStr,
)

from _eventsourcing_orjsontranscoder cimport CTranscoding


cdef class CCustomType1AsDict(CTranscoding):
    def __cinit__(self):
        self.type = CustomType1
        self.name = "custom_type1_as_dict"

    cdef object encode(self, object obj):
        return obj.value

    cdef object decode(self, object data):
        return CustomType1(value=data)


cdef class CCustomType2AsDict(CTranscoding):
    def __cinit__(self):
        self.type = CustomType2
        self.name = "custom_type2_as_dict"

    cdef object encode(self, object obj):
        return obj.value

    cdef object decode(self, object data):
        return CustomType2(data)


cdef class CMyDictAsDict(CTranscoding):
    def __cinit__(self):
        self.type = MyDict
        self.name = "mydict"

    cdef object encode(self, object obj):
        return obj.__dict__

    cdef object decode(self, object data):
        return MyDict(data)


cdef class CMyListAsList(CTranscoding):
    def __cinit__(self):
        self.type = MyList
        self.name = "mylist"

    cdef object encode(self, object obj):
        return list(obj)

    cdef object decode(self, object data):
        return MyList(data)


cdef class CMyStrAsStr(CTranscoding):
    def __cinit__(self):
        self.type = MyStr
        self.name = "mystr"

    cdef object encode(self, object obj):
        return str(obj)

    cdef object decode(self, object data):
        return MyStr(data)


cdef class CMyIntAsInt(CTranscoding):
    def __cinit__(self):
        self.type = MyInt
        self.name = "myint"

    cdef object encode(self, object obj):
        return int(obj)

    cdef object decode(self, object data):
        return MyInt(data)
