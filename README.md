# Welcome to the OrjsonTranscoder project

This package provides a `OrjsonTranscoder` class for use with
the Python eventsourcing library that uses the [orjson
library](https://pypi.org/project/orjson).

Most importantly, `OrjsonTranscoder` supports custom transcoding of instances
of `tuple` and subclasses of `str`, `int`, `dict` and `tuple`. This is an
important improvement on the core library's `JSONTranscoder` class which converts
`tuple` to `list` and loses type information for subclasses of `str`, `int`, `dict`
and `tuple`.

It is also faster than `JSONTranscoder`, encoding approximately x3 faster
and decoding approximately x2 faster. This is less important than the preservation
of type information (see above) because latency in your application will
usually be dominated by database interactions. However, it's nice that it
is not slower.

| class            | encode  | decode  |
|------------------|---------|---------|
| OrjsonTranscoder | 6.8 μs  | 13.8 μs |
| JSON Transcoder  | 20.1 μs | 25.7 μs |


This package uses Cython, so relevant build tools may need to be
installed before this package can be installed successfully.

## Installation

Use pip to install the [stable distribution](https://pypi.org/project/eventsourcing-orjsontranscoder/)
from the Python Package Index.

    $ pip install eventsourcing_orjsontranscoder

Please note, it is recommended to install Python packages into a Python virtual environment.

## Custom Transcodings

Define custom transcodings for your custom value object types by subclassing
``CTranscoding``. The prefix ``C`` is used to distinguish these classes from the
``Transcoding`` classes provided by the core Python eventsourcing library.

For example, consider the custom value object ``MyInt`` below.

```python
class MyInt(int):
    def __repr__(self):
        return f"{type(self).__name__}({super().__repr__()})"

    def __eq__(self, other):
        return type(self) == type(other) and super().__eq__(other)
```

You can define a custom transcoding for ``MyInt`` as a normal Python class in a
normal Python module (``.py`` file) using the ``CTranscoding`` class.

```python
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

Alternatively for greater speed, you can define a custom transcoding for ``MyInt``
as a Cython extension type class in a Cython module (``.pyx`` file) using the
``CTranscoding`` extension type. See this project's Git repository for examples.

```cython
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

If you define Cython modules, you will need to build them in-place before you
can use them. If you are distributing your code, you will also need to configure
your distribution to build the Cython module when your code is installed.

```commandline
$ cythonize -i my_transcodings.pyx
```

See the Cython documentation for more information about Cython.


## Using the OrjsonTranscoder

To use the ``OrjsonTranscoder`` class in a Python eventsourcing application
object, override  the `construct_transcoder()` and `register_transcodings()`
methods.

```python

from eventsourcing.application import Application
from eventsourcing.domain import Aggregate, event
from eventsourcing_orjsontranscoder import (
    CDatetimeAsISO,
    CTupleAsList,
    CUUIDAsHex,
    OrjsonTranscoder,
)


class DogSchool(Application):
    def construct_transcoder(self):
        transcoder = OrjsonTranscoder()
        self.register_transcodings(transcoder)
        return transcoder

    def register_transcodings(self, transcoder):
        transcoder.register(CDatetimeAsISO())
        transcoder.register(CTupleAsList())
        transcoder.register(CUUIDAsHex())
        transcoder.register(CMyIntAsInt())

    def register_dog(self, name, age):
        dog = Dog(name, age)
        self.save(dog)
        return dog.id

    def add_trick(self, dog_id, trick):
        dog = self.repository.get(dog_id)
        dog.add_trick(trick)
        self.save(dog)

    def update_age(self, dog_id, age):
        dog = self.repository.get(dog_id)
        dog.update_age(age)
        self.save(dog)

    def get_dog(self, dog_id):
        dog = self.repository.get(dog_id)
        return {"name": dog.name, "tricks": tuple(dog.tricks), "age": dog.age}


class Dog(Aggregate):
    @event("Registered")
    def __init__(self, name, age):
        self.name = name
        self.age = age
        self.tricks = []

    @event("TrickAdded")
    def add_trick(self, trick):
        self.tricks.append(trick)

    @event("AgeUpdated")
    def update_age(self, age):
        self.age = age


def test_dog_school():
    # Construct application object.
    school = DogSchool()

    # Evolve application state.
    dog_id = school.register_dog("Fido", MyInt(2))
    school.add_trick(dog_id, "roll over")
    school.add_trick(dog_id, "play dead")
    school.update_age(dog_id, MyInt(5))

    # Query application state.
    dog = school.get_dog(dog_id)
    assert dog["name"] == "Fido"
    assert dog["tricks"] == ("roll over", "play dead")
    assert dog["age"] == MyInt(5)

    # Select notifications.
    notifications = school.notification_log.select(start=1, limit=10)
    assert len(notifications) == 4
```

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

If the project dependencies change, you can update your packages by running
the following command.

    $ make update-packages

Please submit changes for review by making a pull request.
