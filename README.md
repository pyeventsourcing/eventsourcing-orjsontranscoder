# Welcome to the eventsourcing_orjsontranscoder project

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
method.

```python

from eventsourcing.application import Application
from eventsourcing_orjsontranscoder import OrjsonTranscoder


class MyApplication(Application):

    ...

    def construct_transcoder(self):
        """
        Constructs a :class:`~eventsourcing.persistence.Transcoder`
        for use by the application.
        """
        transcoder = OrjsonTranscoder
        self.register_transcodings(transcoder)
        return transcoder
```

Please remember to implement and register the transcodings required by your domain model.
See the [library docs](https://eventsourcing.readthedocs.io/en/stable/topics/persistence.html#transcodings)
for more information.

For example, you may wish to use the `TupleAsList` transcoder provided
by this package.

```python
    def register_transcodings(self, transcoder):
        """
        Constructs a :class:`~eventsourcing.persistence.Transcoder`
        for use by the application.
        """
        from eventsourcing_orjsontranscoder import TupleAsList
        transcoder.register(TupleAsList())
```


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
