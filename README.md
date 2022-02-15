# Welcome to the orjson transcoder project

This package provides a `OrjsonTranscoder` class for use with
the Python eventsourcing library that uses the [orjson
library](https://pypi.org/project/orjson).

It improves on the default `JSONTranscoder` class by allowing
subclasses of `str`, `int`, `dict` and `tuple` to be transcoded
without losing type information. It is also faster (approximately
x3 encoding speed and x2 decoding speed). This package uses
Cython, so relevant build tools may need to be installed
before this package can be installed successfully.

## Installation

Use pip to install the [stable distribution](https://pypi.org/project/eventsourcing-orjsontranscoder/)
from the Python Package Index. Please note, it is recommended to
install Python packages into a Python virtual environment.

    $ pip install eventsourcing_orjsontranscoder

## Usage

You can define custom transcodings for your custom value object type by subclassing
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

See the Cython documentation for more information
about Cython.


To use the ``OrjsonTranscoder`` in a Python eventsourcing application object,
override  the `construct_transcoder()` and `register_transcodings()`
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
        transcoder.register(CUUIDAsHex())
        transcoder.register(CDatetimeAsISO())
        transcoder.register(CTupleAsList())
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

Please submit changes for review by making a pull request.
