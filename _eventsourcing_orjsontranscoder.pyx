# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
from datetime import datetime
from typing import cast
from uuid import UUID


cdef int a

from orjson import dumps, loads


cdef class NullName:
    pass


cdef class NullType:
    pass


cdef class CTranscoding:

    cpdef object type(self):
        raise NotImplementedError()

    cpdef object name(self):
        raise NotImplementedError()

    cpdef object encode(self, object obj):
        raise NotImplementedError()

    cpdef object decode(self, object data):
        raise NotImplementedError()


cdef _encode_value(object obj, list stack, dict transcodings, object parent, object key):
    cdef CTranscoding transcoding
    cdef object obj_type = type(obj)

    if obj_type is str:
        pass
    elif obj_type is int:
        pass
    elif obj_type is dict:
        obj = obj.copy()
        stack.append(obj)
        parent[key] = obj
    elif obj_type is list:
        obj = obj.copy()
        stack.append(obj)
        parent[key] = obj
    else:
        try:
            transcoding = transcodings[obj_type]
        except KeyError:
            raise TypeError(
                f"Object of type {obj_type} is not "
                "serializable. Please define and register "
                f"a custom transcoding for this type."
            ) from None
        else:
            obj = {
                "_type_": transcoding.name(),
                "_data_": transcoding.encode(obj),
            }
            stack.append(obj)
            parent[key] = obj


cdef _encode(object obj, dict transcodings):
    cdef list stack = list()
    cdef int stack_pointer = 0
    cdef object next
    cdef object next_type
    cdef object dict_key
    cdef object value
    cdef int list_index
    cdef list list_obj

    cdef list objects = [obj]
    _encode_value(obj, stack, transcodings, objects, 0)
    while stack_pointer < len(stack):
        next = stack[stack_pointer]
        stack_pointer += 1
        next_type = type(next)
        if next_type is dict:
            for dict_key, value in (<dict>next).items():
                _encode_value(value, stack, transcodings, next, dict_key)

        elif next_type is list:
            list_obj = <list>next
            for list_index in range(len(list_obj)):
                _encode_value(list_obj[list_index], stack, transcodings, next, list_index)
    return objects[0]


cdef enum TypeCode:
    is_undef = 0,
    is_dict = 1,
    is_list = 2,


cdef object _decode(object obj, dict transcodings):
    cdef list stack = []
    cdef int stack_pointer = 0
    cdef list frame = None

    cdef object obj_type = type(obj)
    cdef dict dict_obj
    cdef object dict_key
    cdef list list_obj
    cdef int list_index
    cdef object value
    cdef object value_type

    cdef CTranscoding transcoding
    cdef object transcoded_type
    cdef object transcoded_data

    if obj_type is dict:
        stack.append([obj, None, None])
    elif obj_type is list:
        stack.append([obj, None, None])

    while stack_pointer < len(stack):
        frame = stack[stack_pointer]
        stack_pointer += 1
        obj = frame[0]
        obj_type = type(obj)
        if obj_type is dict:
            for dict_key, value in (<dict>obj).items():
                value_type = type(value)
                if value_type is dict or value_type is list:
                    stack.append([value, obj, dict_key])

        elif obj_type is list:
            list_obj = <list>obj
            for list_index in range(len(list_obj)):
                value = list_obj[list_index]
                value_type = type(value)
                if value_type is dict or value_type is list:
                    stack.append([value, obj, list_index])

    while stack_pointer > 0:
        stack_pointer -= 1
        frame = stack[stack_pointer]
        obj = frame[0]
        if type(obj) is dict:
            dict_obj = <dict>obj
            if len(dict_obj) == 2:
                try:
                    transcoded_type = dict_obj["_type_"]
                except KeyError:
                    pass
                else:
                    try:
                        transcoded_data = dict_obj["_data_"]
                    except KeyError:
                        pass
                    else:
                        try:
                            transcoding = transcodings[transcoded_type]
                        except KeyError:
                            raise TypeError(
                                f"Data serialized with name '{cast(str, transcoded_type)}' is not "
                                "deserializable. Please register a "
                                "custom transcoding for this type."
                            )
                        else:
                            obj = transcoding.decode(transcoded_data)
                            if frame[1] is not None:
                                frame[1][frame[2]] = obj
    return obj


cdef class CTupleAsList(CTranscoding):
    cpdef object type(self):
        return tuple

    cpdef object name(self):
        return "tuple_as_list"

    cpdef object encode(self, object obj):
        return [i for i in obj]

    cpdef object decode(self, object data):
        return tuple(data)


cdef class CDatetimeAsISO(CTranscoding):
    """
    Transcoding that represents :class:`datetime` objects as ISO strings.
    """
    cpdef object type(self):
        return datetime

    cpdef object name(self):
        return "datetime_iso"

    cpdef object encode(self, object obj):
        return obj.isoformat()

    cpdef object decode(self, object data):
        return datetime.fromisoformat(data)


cdef class CUUIDAsHex(CTranscoding):
    """
    Transcoding that represents :class:`UUID` objects as hex values.
    """
    cpdef object type(self):
        return UUID

    cpdef object name(self):
        return "uuid_hex"

    cpdef object encode(self, object obj):
        return obj.hex

    cpdef object decode(self, object data):
        return UUID(data)


cdef class OrjsonTranscoder:
    cdef dict types
    cdef dict names

    def __init__(self):
        self.types = {}
        self.names = {}

    def register(self, CTranscoding transcoding):
        """
        Registers given transcoding with the transcoder.
        """
        self.types[transcoding.type()] = transcoding
        self.names[transcoding.name()] = transcoding

    def encode(self, obj):
        return dumps(_encode(obj, self.types))

    def decode(self, data):
        return _decode(loads(data), self.names)

#
# class OrjsonTranscoderRecursive(Transcoder):
#
#     native_types = (str, int, float)
#
#     def __init__(self):
#         super().__init__()
#         self.register(TupleAsList())
#         self._encoders = {
#             int: self._encode_pass,
#             str: self._encode_pass,
#             float: self._encode_pass,
#             dict: self._encode_dict,
#             list: self._encode_list,
#         }
#
#     @staticmethod
#     def _encode_pass(obj: Union[int, str, float]) -> Union[int, str, float]:
#         return obj
#
#     def _encode_dict(self, obj: dict):
#         return {k: self._encode(v) for (k, v) in obj.items()}
#
#     def _encode_list(self, obj: list):
#         return [self._encode(v) for v in obj]
#
#     def _encode(self, obj):
#         obj_type = type(obj)
#         try:
#             _encoder = self._encoders[obj_type]
#         except KeyError:
#             try:
#                 transcoding = self.types[obj_type]
#             except KeyError:
#                 raise TypeError(
#                     f"Object of type {obj_type} is not "
#                     "serializable. Please define and register "
#                     "a custom transcoding for this type."
#                 )
#             else:
#                 return self._encode({
#                     "_type_": transcoding.name,
#                     "_data_": transcoding.encode(obj),
#                 })
#         else:
#             obj = _encoder(obj)
#         return obj
#
#     def encode(self, obj: Any) -> bytes:
#         return orjson.dumps(self._encode(obj))
#
#     def _decode(self, obj: Any):
#         if type(obj) is dict:
#             for key, value in obj.items():
#                 if not isinstance(value, self.native_types):
#                     obj[key] = self._decode(value)
#             return self._decode_obj(obj)
#         elif type(obj) is list:
#             for i, value in enumerate(obj):
#                 if not isinstance(value, self.native_types):
#                     obj[i] = self._decode(value)
#             return obj
#         return obj
#
#     def _decode_obj(self, d: Dict[str, Any]) -> Any:
#         if set(d.keys()) == {
#             "_type_",
#             "_data_",
#         }:
#             t = d["_type_"]
#             t = cast(str, t)
#             try:
#                 transcoding = self.names[t]
#             except KeyError:
#                 raise TypeError(
#                     f"Data serialized with name '{t}' is not "
#                     "deserializable. Please register a "
#                     "custom transcoding for this type."
#                 )
#
#             return transcoding.decode(d["_data_"])
#         else:
#             return d
#
#     def decode(self, data: bytes) -> Any:
#         return self._decode(orjson.loads(data))
