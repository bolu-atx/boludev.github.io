---
layout: post
title:  "What is copiable?"
date:   2022-10-10 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---

## What is copiable anyway?

Python is garbage collected and has a reference counting system. This means that when you create an object, it is stored in memory and a reference to it is stored in a variable. When you assign a variable to another variable, the reference count for the object is incremented. When you delete a variable, the reference count is decremented. When the reference count reaches zero, the object is deleted from memory.

This is a very simple explanation of how Python works. There are many more details that I will not go into here. The point is that when you assign a variable to another variable, you are not creating a copy of the object. You are creating a new reference to the same object. This is important to understand because it can lead to some unexpected behavior.

## Questions I had:

- What happens when you assign a variable to another variable?
- What happens when you return a complex object (i.e. a class) as part of a tuple from a function?
- What happens when you spin up a subprocess, call a method you defined in one class, and give it an object as an argument?

## Toy models:

Let's create a super simple class that allows us to print the underlying ID (i.e. a pointer address kind of unique assignment for each object). 

```py
class Copyable:
    def id(self):
        return id(self)
    def __repr__(self):
        return f"Copyable({self.id()})"
```


### Simple copy assignments

```py
a = Copyable()
b = a
print(a)
print(b)
>>>   Copyable(140703000000000)
>>>   Copyable(140703000000000)
```

As we can see, normal assignments just do a "pointer" copy and both variables point to the same object. This is what we expect.


### What about a list of objects?

```py
a = [Copyable(), Copyable()]
b = a
print(a)
print(b)
>>>  [Copyable(140703000000000), Copyable(140703000000001)]
>>>  [Copyable(140703000000000), Copyable(140703000000001)]
```

As we can see, list of objects do a simple element wise `pointer` copy.


### What about returning from functions?


```py
def return_copyable():
    a = Copyable()
    print(a)
    return a

b = return_copyable()
print(b)

>>> Copyable(140703000000000)
>>> Copyable(140703000000000)
```

As we can see, returning from functions does a simple `pointer` copy and the lifetime of the function scoped variable gets extended to the lifetime of the returned variable.


### What about returning from functions with a tuple instead of a single object?

Tuples are non-mutable, but that does not mean they are storing a copy of the object. They are still just storing a reference to the object. In C++ lingo, this is like storing a const pointer to the object.


```py
def return_copyable() -> Tuple[Copyable, str]:
    a = Copyable()
    print(a)
    return a, "hello"

b, c = return_copyable()
print(b)

>>> Copyable(140703000000000)
>>> Copyable(140703000000000)
```

As we can see, even wrapping it with a tuple does not change the behavior.

### So, how do we actually make a true copy?

`copy` module in Python does just that:

```py
from copy import deepcopy

a = Copyable()
b = deepcopy(a)

print(a)
print(b)

>>> Copyable(140703000000000)
>>> Copyable(140703000000001)
```

As we can see, `deepcopy` will construct a new object and assign it to the new variable, and then ensure that the fields of this new object matches the previous one. This is a true copy.