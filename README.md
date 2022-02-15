# Welcome to the orjson transcoder project

This package provides a `Transcoder` class for use with
the Python eventsourcing library that uses the [orjson
library](https://pypi.org/project/orjson).

It improves on the default `JSONTranscoder` class by allowing
subclasses of `str`, `int`, `dict` and `tuple` to
be transcoded without losing type information. Encoding
is also slightly faster (almost twice as fast). This package
uses Cython so relevant build tools may need to be installed
before this package can be installed successfully.

## Installation

Use pip to install the [stable distribution](https://pypi.org/project/eventsourcing-orjsontranscoder/)
from the Python Package Index. Please note, it is recommended to
install Python packages into a Python virtual environment.

    $ pip install eventsourcing_orjsontranscoder

## Usage

To use this transcoder in your application, override the `construct_transcoder()`
and `register_transcodings()` methods.

```python

from eventsourcing.application import Application
from eventsourcing_orjsontranscoder import (
    CDatetimeAsISO,
    CTupleAsList,
    CUUIDAsHex,
    OrjsonTranscoder,
)


class MyApplication(Application):

    def construct_transcoder(self):
        transcoder = OrjsonTranscoder()
        self.register_transcodings(transcoder)
        return transcoder

    def register_transcodings(self, transcoder):
        transcoder.register(CUUIDAsHex())
        transcoder.register(CDatetimeAsISO())
        transcoder.register(CTupleAsList())
```

Implement and register the transcodings required by the custom value objects in your domain model.

You can either import and extend the ``CTranscoding`` class in a normal Python module (a ``.py``) file.

```python
from eventsourcing_orjsontranscoder import CTranscoding

class CMyIntAsInt(CTranscoding):

    def type(self):
        return MyInt

    def name(self):
        return "myint_as_int"

    def encode(self, obj):
        return int(obj)

    def decode(self, data):
        return MyInt(data)
```

Alternatively, for greater speed you can write and compile a Cython module (a ``.pyx`` file).

```python
from _eventsourcing_orjsontranscoder cimport CTranscoding

from my_domain_model import MyInt

cdef class CMyIntAsInt(CTranscoding):
    cpdef object type(self):
        return MyInt

    cpdef object name(self):
        return "myint_as_int"

    cpdef object encode(self, object obj):
        return int(obj)

    cpdef object decode(self, object data):
        return MyInt(data)
```

```commandline
$ cythonize -i my_transcodings.pyx
```

See the tests folder in this project repo for examples.

See the Cython documentation for more information about Cython.

See the [library docs](https://eventsourcing.readthedocs.io/en/stable/topics/persistence.html#transcodings)
for more information about transcoding, but please note the `CTranscoder` uses a slightly
different API.


## Developers

After cloning the repository, you can set up a virtual environment and
install dependencies by running the following command in the root
folder.

    $ make install

After making changes, please run the tests.

    $ make test

Check the formatting of the code.

    $ make lint

You can automatically reformat the code by running the following command.

    $ make fmt

Please submit changes for review by making a pull request.
