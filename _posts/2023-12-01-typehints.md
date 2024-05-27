---
layout: post
title:  "Build a strong type system via Python typehints"
date:   2023-12-01 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---

Python typehinting system is getting more powerful by each Python version. Projects I'm involved with are now enforcing typehints on all new code. This has been great for a variety of reasons:

- Improves IDE support in terms of linting, autocompletion, and refactoring
- Makes the codebase more readable and maintainable
- Helps catch bugs early in the development cycle

In this post, I'll share some of the additional features we've been able to enable now that most of our codebases are typehinted.

<!--more-->

## Typehinting in Python

Python typehinting syntax is pretty simple, we add the type of the variable after the variable name with a colon. For example:

```python
def add(a: int, b: int) -> int:
    return a + b
```

For people that worked with strongly typed languages such as C++ or C# or Java would know, this gets crazy complicated once you go a little bit beyond the trivial examples. You have to deal with:

- Union types, i.e. `int | float`
- Optional types, i.e. `Animal | None`
- Type variables or generic types, `List[T]` where `T` is a type variable
- Type aliases, i.e. `StrList = List[str]`
- Type annotations for functions, i.e. `Callable[[int, int], int]` for a function that takes 2 ints and returns an int
- Annotated types (i.e. has additional meta information about the type), i.e. `Annotated[int, 'positive']` for an integer that is positive

In the last few years, Python typehinting for these have matured a lot and the API has mostly stablized. This has allowed us to build a strong type system in our codebases. For more details on how to typehint correctly, see the [official Python documentation](https://docs.python.org/3/library/typing.html).

## Typehint queries in Python code

To make the typehints truly useful, we have to be able to retrieve the typehint information in code and then make use of that code. This is where the `typing` module comes in. The `typing` module provides a set of functions that allow you to query the typehint information in your code. For example, you can use the `get_type_hints()` function to get the typehint information for a function. Here's an example:

```python

def add(a: int, b: int) -> int:
    return a + b

from typing import get_type_hints

typehints = get_type_hints(add)
print(typehints)

# Output: {'a': <class 'int'>, 'b': <class 'int'>, 'return': <class 'int'>}
```

### Querying container types (types that have `[]` in the typehint, such as `Optional[Foo]`).

The `typing` module provides `get_origin` and `get_args` functions that allow you to query the container types in your code. For example, you can use the `get_origin` function to get the origin type of a container type, and the `get_args` function to get the arguments of a container type. Here's an example:

```python
from typing import get_origin, get_args

def foo(bar: Optional[int]) -> List[str]:
    pass

typehints = get_type_hints(foo)
print(typehints)
# Output: {'bar': typing.Union[NoneType, int], 'return': typing.List[str]}
```


### Typehints for classes

For classes, the `get_type_hints` can take both the class or the constructor of the class. When called on the class, the default behavior is to return the class variables. When called on the constructor, it returns the constructor signature. Here's an example:

```python
class MockClass:
    Config: ClassVar[str] = "test"

    def __init__(self, a: list[int], b: str | None) -> None:
        pass


def test_get_typehints_on_class() -> None:
    # this returns the class variables
    res = get_type_hints(MockClass)
    # "Config" is a ClassVar in the PydanticComponent baseclass
    assert "Config" in res

    # for class we have to use it on the constructor to get the cosntructor signature
    res = get_type_hints(MockClass.__init__)
    assert "a" in res
    assert "b" in res

    print(res)
    # Output: {'a': typing.List[int], 'b': typing.Union[NoneType, str]}
```

### Class variables and annotated types

THis is inspired by `pydantic` which uses annotated types to provide additional meta information about the type. Here's an example:



```python
class MockClass2(PydanticComponent):
    annotated_class_var: ClassVar[Annotated[str, RegexValidator(".*")]] = "test"
    b: Annotated[str, RegexValidator(".*")]

def test_annotated_class_var() -> None:
    # need to have `include_extras=True` to get the annotated class var
    typehints = get_type_hints(MockClass2, include_extras=True)
    print(typehints["annotated_class_var"])

    # removes classvar, then remove the annotated, then look at the 2nd element (which is regex validator)
    extracted_validator = get_args(get_args(typehints["annotated_class_var"])[0])[1]
    assert isinstance(extracted_validator, RegexValidator)
    assert extracted_validator.regex == ".*"


def test_get_typehints_from_annotations() -> None:
    annotations = mock_method1.__annotations__
    print(annotations)

```

### Callables and `type[]` typehints 

```python
# this tests class and callable typehints
def mock_method6(a: type[PydanticComponent], b: Callable[[int], bool]) -> None:
    pass

def test_typehint_on_callable_and_class() -> None:
    typehints = get_type_hints(mock_method6)

    a = typehints["a"]
    b = typehints["b"]

    # test a class definition first
    origin, args = get_origin(a), get_args(a)
    # container of a `type` is a `type`
    assert origin is type
    assert args == (PydanticComponent,)

    # callable container is a `Callable`
    origin, args = get_origin(b), get_args(b)
    from collections.abc import Callable as CallableType

    assert origin is CallableType
    # the first element is the input type, the second element is the return type
    assert len(args) == 2
    input_args = args[0]
    return_type = args[1]
    assert tuple(input_args) == (int,)
    assert return_type == bool

```


## Using the type queries to do useful things

One of the first things we can now do is to write a typechecker that can check if the typehints are correct, similar to that found in the library [enforce](https://github.com/RussBaz/enforce).

### Runtime type validation

```python
from typing import get_type_hints

def typecheck(func):
    def wrapper(*args, **kwargs):
        typehints = get_type_hints(func)
        # NOTE, do not use in production systems, this is just a trivial example
        for arg, arg_type in typehints.items():
            if not isinstance(args[arg], arg_type):
                raise TypeError(f"Expected {arg_type} for {arg}, got {type(args[arg])}")
        return func(*args, **kwargs)
    return wrapper
```

This is just a trivial example, do not use this in production, for example, this would fail pretty catastrophically if the typehint is a Union type. But you get the idea that it is POSSIBLE to do this.



### Dependency injection or resolution

We can also use the typehints to do dependency injection or resolution. For example, we can use the typehints to automatically resolve the dependencies of a function or class. Here's an example:

```python

things = {
    typing.List: [1, 2, 3],
    typing.Dict: {"a": 1, "b": 2},
    Foo: Foo(),
}

# TRIVIAL EXAMPLE, DO NOT USE IN PRODUCTION
def resolve_dependencies(func):
    typehints = get_type_hints(func)
    dependencies = {}
    for arg, arg_type in typehints.items():
        if arg_type in dependencies:
            dependencies[arg] = dependencies[arg_type]
        else:
            dependencies[arg] = arg_type()
    return func(**dependencies)
```

Here, the available dependnecies are stored in a dictionary hashed by the type, for functions that require a dependency, we can resolve the dependency by looking up the type in the dictionary. Again, this is a trivial example, do not use this in production.

## Conclusion

Hopefully this post shows you the power of typehinting beyond basic static typechecking with `mypy`. I hope this has been helpful. In projects at work, we've successfully deployed complex dependency injection frameworks utilizing typehints. This has made our codebase more modular and easier to test. I hope you can find similar use cases in your projects. 
