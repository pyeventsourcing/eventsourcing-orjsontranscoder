# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=True
from collections import deque
from typing import Any, List, Tuple, cast

import orjson as orjson
from eventsourcing.persistence import Transcoder, Transcoding


class TupleAsList(Transcoding):
    type = tuple
    name = 'tuple_as_list'

    def encode(self, obj: Tuple[Any, ...]) -> List[Any]:
        return [i for i in obj]

    def decode(self, data: List[Any]) -> Tuple[Any, ...]:
        return tuple(data)


cdef object _encode_value(object obj, object frontier, dict transcodings):
    if type(obj) in (str, int):
        pass
    elif type(obj) in (dict, list):
        obj = obj.copy()
        frontier.append(obj)
    else:
        try:
            transcoding = transcodings[type(obj)]
        except KeyError:
            raise TypeError(
                f"Object of type {type(obj)} is not "
                "serializable. Please define and register "
                "a custom transcoding for this type."
            ) from None
        else:
            obj = {
                "_type_": transcoding.name,
                "_data_": transcoding.encode(obj),
            }
            frontier.append(obj)
    return obj


cdef void _encode_values(object obj, object frontier, dict transcodings):
    cdef object value
    cdef str key
    cdef int i
    cdef int len_obj

    if type(obj) is dict:
        for key, value in obj.items():
            obj[key] = _encode_value(value, frontier, transcodings)

    elif type(obj) is list:
        len_obj = len(obj)
        for i in range(len_obj):
            obj[i] = _encode_value(obj[i], frontier, transcodings)


cdef object _encode(object obj, dict transcodings):
    cdef frontier = deque()
    obj = _encode_value(obj, frontier, transcodings)
    while frontier:
        _encode_values(frontier.popleft(), frontier, transcodings)
    return obj


cdef class Frame:
    cdef object obj
    cdef object parent
    cdef object key
    cdef Frame previous
    cdef Frame next

    def __cinit__(self, object obj, object parent, object key, Frame previous, Frame next) -> None:
        self.obj = obj
        self.parent = parent
        self.key = key
        self.previous = previous
        self.next = next


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
    if isinstance(obj, (dict, list)):
        new_frame = Frame.__new__(Frame, obj, None, None, previous_frame, None)
        previous_frame = new_frame
        frame = new_frame

    while frame is not None:
        obj = frame.obj
        if isinstance(obj, dict):
            for key, value in obj.items():
                if isinstance(value, (dict, list)):
                    new_frame = Frame.__new__(Frame, value, obj, key, previous_frame, None)
                    previous_frame.next = new_frame
                    previous_frame = new_frame

        elif isinstance(obj, list):
            len_obj = len(obj)
            for i in range(len_obj):
                value = obj[i]
                if isinstance(value, (dict, list)):
                    new_frame = Frame.__new__(Frame, value, obj, i, previous_frame, None)
                    previous_frame.next = new_frame
                    previous_frame = new_frame
        frame = frame.next

    frame = previous_frame
    while frame is not None:
        obj = frame.obj

        if isinstance(obj, dict) and len(obj) == 2:
            try:
                transcoded_type = obj["_type_"]
            except KeyError:
                return obj
            else:
                try:
                    transcoded_data = obj["_data_"]
                except KeyError:
                    return obj
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
        return orjson.dumps(_encode(obj, self.types))

    def decode(self, data: bytes) -> Any:
        return _decode(orjson.loads(data), self.names)

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
