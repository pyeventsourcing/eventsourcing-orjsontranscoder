import timeit
from time import sleep
from typing import Any, Dict, List, Tuple, Union, cast
from uuid import NAMESPACE_URL, UUID, uuid5

import orjson as orjson
from eventsourcing.domain import DomainEvent
from eventsourcing.persistence import (
    DatetimeAsISO,
    JSONTranscoder,
    Transcoder,
    Transcoding,
    UUIDAsHex,
)
from eventsourcing.tests.persistence import (
    CustomType1,
    CustomType1AsDict,
    CustomType2,
    CustomType2AsDict,
    TranscoderTestCase,
)

from eventsourcing_orjsontranscoder import OrjsonTranscoder


class TupleAsList(Transcoding):
    type = tuple
    name = "tuple_as_list"

    def encode(self, obj: Tuple[Any, ...]) -> List[Any]:
        return list(obj)

    def decode(self, data: List[Any]) -> Tuple[Any, ...]:
        return tuple(data)


class OrjsonTranscoder_Recursive(Transcoder):

    native_types = (str, int, float)

    def __init__(self):
        super().__init__()
        self.register(TupleAsList())
        self._encoders = {
            int: self._encode_pass,
            str: self._encode_pass,
            float: self._encode_pass,
            dict: self._encode_dict,
            list: self._encode_list,
        }

    @staticmethod
    def _encode_pass(obj: Union[int, str, float]) -> Union[int, str, float]:
        return obj

    def _encode_dict(self, obj: dict):
        return {k: self._encode(v) for (k, v) in obj.items()}

    def _encode_list(self, obj: list):
        return [self._encode(v) for v in obj]

    def _encode(self, obj):
        obj_type = type(obj)
        try:
            _encoder = self._encoders[obj_type]
        except KeyError:
            try:
                transcoding = self.types[obj_type]
            except KeyError:
                raise TypeError(
                    f"Object of type {obj_type} is not "
                    "serializable. Please define and register "
                    "a custom transcoding for this type."
                )
            else:
                return self._encode(
                    {
                        "_type_": transcoding.name,
                        "_data_": transcoding.encode(obj),
                    }
                )
        else:
            obj = _encoder(obj)
        return obj

    def encode(self, obj: Any) -> bytes:
        return orjson.dumps(self._encode(obj))

    def _decode(self, obj: Any):
        if type(obj) is dict:
            for key, value in obj.items():
                if not isinstance(value, self.native_types):
                    obj[key] = self._decode(value)
            return self._decode_obj(obj)
        elif type(obj) is list:
            for i, value in enumerate(obj):
                if not isinstance(value, self.native_types):
                    obj[i] = self._decode(value)
            return obj
        return obj

    def _decode_obj(self, d: Dict[str, Any]) -> Any:
        if set(d.keys()) == {
            "_type_",
            "_data_",
        }:
            t = d["_type_"]
            t = cast(str, t)
            try:
                transcoding = self.names[t]
            except KeyError:
                raise TypeError(
                    f"Data serialized with name '{t}' is not "
                    "deserializable. Please register a "
                    "custom transcoding for this type."
                )

            return transcoding.decode(d["_data_"])
        else:
            return d

    def decode(self, data: bytes) -> Any:
        return self._decode(orjson.loads(data))


class TestOrjsonTranscoder(TranscoderTestCase):
    transcoder_class = OrjsonTranscoder

    def test_performance(self):
        sleep(0.1)
        self._test_performance(OrjsonTranscoder)
        sleep(0.1)
        self._test_performance(JSONTranscoder)
        print("")
        print("")
        print("")
        sleep(0.1)

    def _test_performance(self, transcoder_cls):
        transcoder = transcoder_cls()
        transcoder.register(DatetimeAsISO())
        transcoder.register(UUIDAsHex())
        transcoder.register(CustomType1AsDict())
        transcoder.register(CustomType2AsDict())

        obj = {
            "originator_id": uuid5(NAMESPACE_URL, "some_id"),
            "originator_version": 123,
            "timestamp": DomainEvent.create_timestamp(),
            "a_str": "hello",
            "b_int": 1234567,
            "c_tuple": (1, 2, 3, 4, 5, 6, 7),
            "d_list": [1, 2, 3, 4, 5, 6, 7],
            "e_dict": {"a": 1, "b": 2, "c": 3},
            "f_valueobj": CustomType2(
                CustomType1(UUID("b2723fe2c01a40d2875ea3aac6a09ff5"))
            ),
        }
        data = transcoder.encode(obj)

        # Warm up.
        timeit.timeit(lambda: transcoder.encode(obj), number=100)
        timeit.timeit(lambda: transcoder.decode(data), number=100)

        number = 100000
        duration = timeit.timeit(lambda: transcoder.encode(obj), number=number)
        print(f"{transcoder_cls.__name__} encode: {1000000 * duration / number:.1f} μs")

        duration = timeit.timeit(lambda: transcoder.decode(data), number=number)
        print(f"{transcoder_cls.__name__} decode: {1000000 * duration / number:.1f} μs")


del TranscoderTestCase
