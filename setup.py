#!/usr/bin/env python3

from setuptools import setup
from distutils.extension import Extension

ext_modules = [
    Extension(
        'util',
        sources=["lib/cyac/util.pyx"],
    ),
    Extension(
        'utf8',
        sources=["lib/cyac/utf8.pyx"],
    ),
    Extension(
        'xstring',
        sources=["lib/cyac/xstring.pyx"],
    ),
    Extension(
        'trie',
        sources=["lib/cyac/trie.pyx"],
    ),
    Extension(
        'ac',
        sources=["lib/cyac/ac.pyx"],
    ),]

# import os
# os.environ['CFLAGS'] = '-O0'
try:
    long_description = open("README.md", encoding="utf8").read()
except IOError:
    long_description = ""

setup(
    version="1.5",
    description="High performance Trie and Ahocorasick automata (AC automata) for python",
    name="cyac",
    url="https://github.com/nppoly/cyac",
    author="nppoly",
    author_email="nppoly@foxmail.com",
    packages=["cyac"],
    package_dir={'cyac': 'lib/cyac'},
    package_data={'cyac': ['*.pxd', 'cyac/unicode_portability.cpp']},
    include_package_data=True,
    long_description_content_type="text/markdown",
    long_description=long_description,
    install_requires=["cython"],
    setup_requires=['Cython'],
    ext_modules = ext_modules,
    classifiers=[
        'Operating System :: POSIX :: Linux',
        'Operating System :: MacOS :: MacOS X',
        'Operating System :: Microsoft :: Windows',
        "Programming Language :: Python",
        "Topic :: Text Processing",
        "Topic :: Text Processing :: Linguistic",
        "Programming Language :: Python :: 2.7",
        "Programming Language :: Python :: 3.4",
        "Programming Language :: Python :: 3.5",
        "Programming Language :: Python :: 3.6",
        "Programming Language :: Python :: 3.7",
    ]
)
