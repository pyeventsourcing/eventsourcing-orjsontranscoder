# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
from datetime import datetime
from json import JSONDecoder
from types import NoneType
from typing import cast
from uuid import UUID

from cpython.ref cimport PyObject

cimport cython
from orjson import dumps, loads


cdef class CTranscoding:

    cpdef object type(self):
        raise NotImplementedError()

    cpdef str name(self):
        raise NotImplementedError()

    cpdef object encode(self, object obj):
        raise NotImplementedError()

    cpdef object decode(self, object data):
        raise NotImplementedError()


cdef class CTupleAsList(CTranscoding):
    cpdef object type(self):
        return tuple

    cpdef str name(self):
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

    cpdef str name(self):
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

    cpdef str name(self):
        return "uuid_hex"

    cpdef object encode(self, object obj):
        return obj.hex

    cpdef object decode(self, object data):
        return UUID(data)


cdef class EncoderFrame:
    cdef object node
    cdef NodeTypeCode node_type_code
    cdef EncoderFrame parent
    cdef list keys    # for dict node
    cdef list values  # for dict node
    cdef long i_child  # state of frame iteration over child nodes
    cdef long node_len  # length of node

    def __cinit__(self, object node, NodeTypeCode node_type_code, EncoderFrame parent):
        self.node = node
        self.node_type_code = node_type_code
        self.parent = parent


cdef NodeTypeCode get_type_code(object node):
    cdef object node_type = type(node)
    if node_type is str:
        return node_type_str
    elif node_type is int:
        return node_type_int
    elif node_type is float:
        return node_type_float
    elif node_type is bool:
        return node_type_bool
    elif node_type is NoneType:
        return node_type_null
    elif node_type is list:
        return node_type_list
    elif node_type is dict:
        return node_type_dict
    else:
        return node_type_custom


cdef enum NodeTypeCode:
    node_type_str = 1
    node_type_int = 2
    node_type_float = 3
    node_type_bool = 4
    node_type_null = 5
    node_type_list = 6
    node_type_dict = 7
    node_type_custom = 8


cdef class CTranscoder:
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

    cdef str _encode(CTranscoder self, object node):
        cdef list output = list()
        cdef NodeTypeCode obj_type_code
        cdef object child_node
        cdef NodeTypeCode child_node_type_code
        cdef CTranscoding transcoding
        cdef EncoderFrame frame = None

        obj_type_code = get_type_code(node)
        if obj_type_code == node_type_str:
            output.append('"')
            output.append(node)
            output.append('"')
        elif obj_type_code == node_type_int:
            output.append(str(node))
        elif obj_type_code == node_type_bool:
            if <bint>node == 1:
                pass
                output.append("true")
            else:
                pass
                output.append("false")
        elif obj_type_code == node_type_float:
            output.append(str(<double>node))
        elif obj_type_code == node_type_null:
            output.append(str("null"))
        else:
            frame = EncoderFrame(node=node, node_type_code=obj_type_code, parent=None)

        while frame:
            if frame.node_type_code == node_type_list:
                if frame.i_child == 0:
                    frame.node_len = len(frame.node)
                    if frame.node_len == 0:
                        output.append("[]")
                        frame = frame.parent
                    else:
                        output.append("[")
                        while 1:
                            child_node = frame.node[frame.i_child]
                            frame.i_child += 1
                            child_node_type_code = get_type_code(child_node)
                            if child_node_type_code == node_type_str:
                                output.append('"')
                                output.append(child_node)
                                output.append('"')
                            elif child_node_type_code == node_type_bool:
                                pass
                            elif child_node_type_code == node_type_int:
                                pass
                                output.append(str(child_node))
                            elif child_node_type_code == node_type_float:
                                pass
                            else:
                                frame = EncoderFrame(node=child_node, node_type_code=child_node_type_code, parent=frame)
                                break
                            if frame.i_child == frame.node_len:
                                frame = frame.parent
                                output.append("]")
                                break
                            else:
                                pass
                                output.append(",")

                elif frame.i_child < frame.node_len:
                    while 1:
                        child_node = frame.node[frame.i_child]
                        output.append(",")
                        frame.i_child += 1
                        child_node_type_code = get_type_code(child_node)
                        if child_node_type_code == node_type_str:
                            output.append('"')
                            output.append(<str>child_node)
                            output.append('"')
                        elif child_node_type_code == node_type_bool:
                            pass
                        elif child_node_type_code == node_type_int:
                            pass
                            output.append(str(child_node))
                        elif child_node_type_code == node_type_float:
                            pass
                        else:
                            frame = EncoderFrame(node=child_node,
                                                 node_type_code=child_node_type_code,
                                                 parent=frame)
                            break
                        if frame.i_child == frame.node_len:
                            output.append("]")
                            frame = frame.parent
                            break

                else:
                    output.append("]")
                    frame = frame.parent

            elif frame.node_type_code == node_type_dict:
                if frame.i_child == 0:
                    frame.node_len = len(frame.node)
                    frame.keys = [key for key in frame.node.keys()]
                    frame.values = list(frame.node.values())
                    if frame.node_len == 0:
                        output.append("{}")
                        frame = frame.parent
                    else:
                        output.append("{")
                        while 1:
                            output.append('"')
                            output.append(frame.keys[frame.i_child])
                            output.append('":')
                            child_node = frame.values[frame.i_child]
                            frame.i_child += 1
                            child_node_type_code = get_type_code(child_node)
                            if child_node_type_code == node_type_str:
                                output.append('"')
                                output.append(child_node)
                                output.append('"')
                            elif child_node_type_code == node_type_bool:
                                pass
                            elif child_node_type_code == node_type_int:
                                pass
                                output.append(str(child_node))
                            elif child_node_type_code == node_type_float:
                                pass
                            else:
                                frame = EncoderFrame(node=child_node,
                                                     node_type_code=child_node_type_code,
                                                     parent=frame)
                                break
                            if frame.i_child == frame.node_len:
                                frame = frame.parent
                                output.append("}")
                                break
                            else:
                                output.append(",")
                                pass

                elif frame.i_child < frame.node_len:
                    while 1:
                        child_node = frame.values[frame.i_child]
                        output.append(',"')
                        output.append(frame.keys[frame.i_child])
                        output.append('":')
                        frame.i_child += 1
                        child_node_type_code = get_type_code(child_node)
                        if child_node_type_code == node_type_str:
                            output.append('"')
                            output.append(child_node)
                            output.append('"')
                        elif child_node_type_code == node_type_bool:
                            pass
                        elif child_node_type_code == node_type_int:
                            pass
                            output.append(str(child_node))
                        elif child_node_type_code == node_type_float:
                            pass
                        else:
                            frame = EncoderFrame(node=child_node,
                                                 node_type_code=child_node_type_code,
                                                 parent=frame)
                            break
                        if frame.i_child == frame.node_len:
                            frame = frame.parent
                            output.append("}")
                            break


                else:
                    output.append("}")
                    frame = frame.parent
            else:
                try:
                    transcoding = self.types[type(frame.node)]
                except KeyError:
                    raise TypeError(
                        f"Object of type {type(frame.node)} is not "
                        "serializable. Please define and register "
                        f"a custom transcoding for this type."
                    ) from None
                else:
                    # obj = {
                    #     "_type_": transcoding.name(),
                    #     "_data_": transcoding.encode(obj),
                    # }

                    frame.node_len = 2
                    frame.node_type_code = node_type_dict
                    frame.keys = ["_type_", "_data_"]
                    frame.values = [transcoding.name(), transcoding.encode(frame.node)]
                    output.append('{"_type_":"')
                    output.append(transcoding.name())
                    output.append('","_data_":')
                    frame.i_child = 2
                    child_node = frame.values[1]
                    child_node_type_code = get_type_code(child_node)
                    if child_node_type_code == node_type_str:
                        output.append('"')
                        output.append(child_node)
                        output.append('"}')
                        frame = frame.parent
                    elif child_node_type_code == node_type_bool:
                        pass
                        frame = frame.parent
                    elif child_node_type_code == node_type_int:
                        pass
                        output.append(str(child_node))
                        output.append("}")
                        frame = frame.parent
                    elif child_node_type_code == node_type_float:
                        pass
                    else:
                        frame = EncoderFrame(node=child_node, node_type_code=child_node_type_code, parent=frame)

        return "".join(output)

    # cdef object _encode_value(CTranscoder self, object obj, list stack, object parent, object key):
    #     cdef CTranscoding transcoding
    #     cdef object obj_type = type(obj)
    #
    #     if obj_type is str:
    #         pass
    #     elif obj_type is int:
    #         pass
    #     elif obj_type is float:
    #         pass
    #     elif obj_type is NoneType:
    #         pass
    #     elif obj_type is bool:
    #         pass
    #     elif obj_type is dict:
    #         obj = obj.copy()
    #         stack.append(obj)
    #         parent[key] = obj
    #     elif obj_type is list:
    #         obj = obj.copy()
    #         stack.append(obj)
    #         parent[key] = obj
    #     else:
    #         try:
    #             transcoding = self.types[obj_type]
    #         except KeyError:
    #             raise TypeError(
    #                 f"Object of type {obj_type} is not "
    #                 "serializable. Please define and register "
    #                 f"a custom transcoding for this type."
    #             ) from None
    #         else:
    #             obj = {
    #                 "_type_": transcoding.name(),
    #                 "_data_": transcoding.encode(obj),
    #             }
    #             stack.append(obj)
    #             parent[key] = obj

    cdef object _decode(CTranscoder self, object obj):
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
                for dict_key, value in (<dict> obj).items():
                    value_type = type(value)
                    if value_type is dict or value_type is list:
                        stack.append([value, obj, dict_key])

            elif obj_type is list:
                list_obj = <list> obj
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
                dict_obj = <dict> obj
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
                                transcoding = self.names[transcoded_type]
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


cdef class NullTranscoder(CTranscoder):

    cpdef object encode(self, object obj):
        return self._encode(obj).encode('utf8')

    cpdef object decode(self, object data):
        return self._decode(data)


cdef class OrjsonTranscoder(CTranscoder):
    cdef object decoder

    def __cinit__(self):
        self.decoder = JSONDecoder()

    cpdef object encode(self, object obj):
        return self._encode(obj).encode('utf8')

    cpdef object decode(self, object data):
        return self._decode(self.decoder.decode(data.decode('utf8')))

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
