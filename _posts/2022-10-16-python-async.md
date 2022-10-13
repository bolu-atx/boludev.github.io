---
layout: post
title:  "Dive into Python Async"
date:   2022-10-10 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---

## Notes on learning Python `asyncio`

For as long as I have worked in Python land, I never had to touch the async part of the language. I know that `asyncio` library has gotten a lot of love in the past few years. Recently I've came across an opportunity to do a lot of IO and non-cpu bound work in Python. I decided to take a deep dive into the `asyncio` library and see what it has to offer.


### 1. Basic example, async hello world


```py
import asyncio

async def hello_world():
    asyncio.sleep(1)
    print("Hello world")

asyncio.run(hello_world())

>>> Hello world
```

Running two async functions in parallel
```py
import asyncio

async def foo():
    while True:
        asyncio.sleep(1)
        print("foo")

async def bar():
    while True:
        asyncio.sleep(1)
        print("bar")

asyncio.run(asyncio.gather(foo(), bar()))
```

Wrapping a synchronous function in an async function can be done via a decorator. 

```py
def async_wrap(
    func: Callable, loop: Optional[asyncio.BaseEventLoop] = None, executor: Optional[Executor] = None
) -> Callable:
    def _async_wrap(func: Callable) -> Callable:
        @wraps(func)
        async def run(*args, loop=loop, executor=executor, **kwargs):
            if loop is None:
                loop = asyncio.get_event_loop()
            pfunc = partial(func, *args, **kwargs)
            return await loop.run_in_executor(executor, pfunc)

        return run

    return _async_wrap
```

The above decorator is a higher order decorator (it takes arguments and then generates another decorator), example usage is the following:

```py
import asyncio
import time

@async_wrap()
def foo():
    while True:
        time.sleep(1)
        print("foo from sync")

async def bar():
    while True:
        asyncio.sleep(1)
        print("bar from async")

asyncio.run(asyncio.gather(foo(), bar()))
```
