# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
from typing import Any, List, Tuple, cast

from orjson import loads, dumps
from eventsourcing.persistence import Transcoder, Transcoding


class TupleAsList(Transcoding):
    type = tuple
    name = 'tuple_as_list'

    def encode(self, obj: Tuple[Any, ...]) -> List[Any]:
        return [i for i in obj]

    def decode(self, data: List[Any]) -> Tuple[Any, ...]:
        return tuple(data)


cdef object _encode_value(object obj, list frontier, dict transcodings, object parent, object key):
    cdef object transcoding
    cdef object obj_type = type(obj)
    if obj_type is str:
        pass
    elif obj_type is int:
        pass
    elif obj_type is dict:
        obj = obj.copy()
        frontier.append(obj)
        parent[key] = obj
    elif obj_type is list:
        obj = obj.copy()
        frontier.append(obj)
        parent[key] = obj
    else:
        try:
            transcoding = transcodings[obj_type]
        except KeyError:
            raise TypeError(
                f"Object of type {obj_type} is not "
                "serializable. Please define and register "
                "a custom transcoding for this type."
            ) from None
        else:
            obj = {
                "_type_": transcoding.name,
                "_data_": transcoding.encode(obj),
            }
            frontier.append(obj)
            parent[key] = obj


cdef object _encode(object obj, dict transcodings):
    cdef list frontier = list()
    cdef int i = 0
    cdef object next
    cdef object next_type
    cdef str key
    cdef object value
    cdef int j
    cdef list list_obj

    cdef list objects = [obj]
    _encode_value(obj, frontier, transcodings, objects, 0)
    while i < len(frontier):
        next = frontier[i]
        i += 1
        next_type = type(next)
        if next_type is dict:
            for key, value in (<dict>next).items():
                _encode_value(value, frontier, transcodings, next, key)

        elif next_type is list:
            list_obj = <list>next
            for j in range(len(list_obj)):
                _encode_value(list_obj[j], frontier, transcodings, next, j)
    return objects[0]


cdef enum TypeCode:
    is_undef = 0,
    is_dict = 1,
    is_list = 2,


cdef class Frame:
    cdef object obj
    cdef TypeCode obj_type_code
    cdef object parent
    cdef object key
    cdef Frame previous
    cdef Frame next

    def __cinit__(self, object obj, TypeCode obj_type_code, object parent, object key, Frame previous) -> None:
        self.obj = obj
        self.obj_type_code = obj_type_code
        self.parent = parent
        self.key = key
        self.previous = previous


cdef object _decode(object obj, dict transcodings):
    cdef Frame new_frame = None
    cdef Frame previous_frame = None
    cdef Frame frame = None
    cdef object transcoding
    cdef object transcoded_type
    cdef object transcoded_data
    cdef int len_list
    cdef int i
    cdef object key
    cdef object value
    cdef object value_type
    cdef dict dict_obj
    cdef list list_obj
    cdef TypeCode obj_type_code
    cdef object obj_type = type(obj)
    if obj_type is dict:
        new_frame = Frame.__new__(Frame, obj, is_dict, None, None, previous_frame)
        previous_frame = new_frame
        frame = new_frame
    elif obj_type is list:
        new_frame = Frame.__new__(Frame, obj, is_list, None, None, previous_frame)
        previous_frame = new_frame
        frame = new_frame

    while frame is not None:
        obj = frame.obj
        obj_type_code = frame.obj_type_code
        if obj_type_code == is_dict:
            for key, value in (<dict>obj).items():
                value_type = type(value)
                if value_type is dict:
                    new_frame = Frame.__new__(Frame, value, is_dict, obj, key, previous_frame)
                    previous_frame.next = new_frame
                    previous_frame = new_frame
                elif value_type is list:
                    new_frame = Frame.__new__(Frame, value, is_list, obj, key, previous_frame)
                    previous_frame.next = new_frame
                    previous_frame = new_frame

        elif obj_type_code == is_list:
            list_obj = <list>obj
            for i in range(len(list_obj)):
                value = (list_obj)[i]
                value_type = type(value)
                if value_type is dict:
                    new_frame = Frame.__new__(Frame, value, is_dict, obj, i, previous_frame)
                    previous_frame.next = new_frame
                    previous_frame = new_frame
                elif value_type is list:
                    new_frame = Frame.__new__(Frame, value, is_list, obj, i, previous_frame)
                    previous_frame.next = new_frame
                    previous_frame = new_frame
        frame = frame.next

    frame = previous_frame
    while frame is not None:

        obj = frame.obj
        if frame.obj_type_code == is_dict:
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
                            if frame.parent is not None:
                                frame.parent[frame.key] = obj
        frame = frame.previous
    return obj


class OrjsonTranscoder(Transcoder):

    native_types = (str, int, float)

    def __init__(self):
        super().__init__()
        self.register(TupleAsList())

    def encode(self, obj: Any) -> bytes:
        return dumps(_encode(obj, self.types))

    def decode(self, data: bytes) -> Any:
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
