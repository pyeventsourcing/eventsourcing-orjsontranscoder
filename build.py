import os
from distutils.command.build_ext import build_ext

# See if Cython is installed
from Cython.Build import cythonize
from setuptools import Extension
from setuptools.dist import Distribution


# This function will be executed in setup.py:
def build(setup_kwargs):
    # The file you want to compile
    extensions = [
        "_eventsourcing_orjsontranscoder.pyx",
    ]

    # gcc arguments hack: enable optimizations
    os.environ["CFLAGS"] = "-O3"

    # Build
    setup_kwargs.update(
        {
            "ext_modules": cythonize(
                extensions,
                language_level=3,
                compiler_directives={"linetrace": True},
            ),
            "cmdclass": {"build_ext": build_ext},
        }
    )
