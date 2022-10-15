---
layout: post
title:  "Dive into Python asyncio - part 1"
date:   2022-09-30 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---

For as long as I have worked in Python land, I never had to touch the async part of the language. I know that `asyncio` library has gotten a lot of love in the past few years. Recently I've came across an opportunity to do a lot of IO and non-cpu bound work in Python. I decided to take a deep dive into the `asyncio` library and see what it has to offer.

In part 1 of this series (I originally just wanted to write one post and realized the scope is way too big), we'll cover:

- How async code interfaces with synchronous code in Python
- How to convert synchronous code to asynchronous code, including how to prevent blocking of the event loop via custom `ThreadPoolExecutor`
- How to use `asyncio` to run multiple tasks concurrently


### Basic example, async hello world


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

### What if I have existing synchronous methods?

We can wrap a synchronous function in an async function, an example implementation would be a decorator (i love decorators, btw):

```py
def async_wrap(
    loop: Optional[asyncio.BaseEventLoop] = None, executor: Optional[Executor] = None
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

<!--more-->

Above code will work exactly the same to the user as the previous example. The only difference is that the `foo` function is now synchronous. This is useful when you have a synchronous function that you want to run in parallel with an async function.

Wait, but how? Doesn't async / event loop based concurrency require `awaitable` locations to be able to context switch? We addd the thread id and the process id to the print statement to see what's going on.

```py
import time, os, asyncio, threading

@async_wrap()
def foo():
    while True:
        time.sleep(1)
        # get event loop id
        loop = asyncio.get_event_loop()
        print(f"foo from sync pid: {os.getpid()} tid: {threading.get_ident()}, loop id: {loop.get_debug()}")

async def bar():
    while True:
        asyncio.sleep(1)
        # get event loop id
        loop = asyncio.get_event_loop()
        print(f"bar from sync pid: {os.getpid()} tid: {threading.get_ident()}, loop id: {loop.get_debug()}")

asyncio.run(asyncio.gather(foo(), bar()))
```

Side note - the above code doesn't actually work, if we run it we get something like this:
```
../../miniconda3/lib/python3.8/asyncio/tasks.py:813: in gather
    fut = ensure_future(arg, loop=loop)
../../miniconda3/lib/python3.8/asyncio/tasks.py:660: in ensure_future
    loop = events.get_event_loop()
../../miniconda3/lib/python3.8/asyncio/events.py:639: in get_event_loop
    raise RuntimeError('There is no current event loop in thread %r.'
E   RuntimeError: There is no current event loop in thread 'MainThread'.
```

Ater a lot of debugging - I got the following to work, it looks like in a decorated synchronous function, the standard `asyncio` methods to retrieve running loops etc doesn't work.

```py
def test_wrapped_async_ids() -> None:
    @async_wrap()
    def foo():
        while True:
            time.sleep(1)
            # get event loop id
            print(f"\nfoo from pid: {os.getpid()} tid: {threading.get_ident()}\n")

    async def bar():
        loop = asyncio.get_running_loop()
        while True:
            await asyncio.sleep(1)
            # get event loop id
            print(f"\nbar from pid: {os.getpid()} tid: {threading.get_ident()}\n")

    async def main():
        print("main")
        await asyncio.gather(foo(), bar())
    
    asyncio.run(main())
```


Anyway, if you run the above function, you will get someting like this:
```
bar from pid: 21883 tid: 140157781362496

foo from pid: 21883 tid: 140157642589952



bar from pid: 21883 tid: 140157781362496

foo from pid: 21883 tid: 140157642589952



foo from pid: 21883 tid: 140157642589952


bar from pid: 21883 tid: 140157781362496
```

The observation here is that both tasks are running on the same Python process, but coming from different threads.

What if we stopped using the async_wrap decorator? and call `gather` on two async functions?

```py
...
    async def foo():
        while True:
            await asyncio.sleep(1)
            # get event loop id
            print(f"\nfoo from pid: {os.getpid()} tid: {threading.get_ident()}\n")
...
```

Output of this code is:
```
bar from pid: 22395 tid: 140233902278464


foo from pid: 22395 tid: 140233902278464


bar from pid: 22395 tid: 140233902278464


foo from pid: 22395 tid: 140233902278464


bar from pid: 22395 tid: 140233902278464
```

As we can see, the tid and pids are all the same but we are getting prints concurrently from both async functions.

It appears asyncio `gather` is pretty smart and is changing the number of threads the executor is running on based on the number of concurrent tasks submitted - let's try to prove this.

```py
def test_wrapped_concurrent_thread_limit() -> None:
    @async_wrap()
    def foo():
        time.sleep(0.1)
        return threading.get_ident()

    async def bar():
        await asyncio.sleep(0.1)
        return threading.get_ident()

    async def main_wrapped():
        for n_concurrent_tasks in range(1, 20, 4):
            print(f"n_concurrent_tasks: {n_concurrent_tasks}")
            res = await asyncio.gather(*[foo() for _ in range(n_concurrent_tasks)])
            num_threads_used = len(set(res))
            print(f"Dispatched {n_concurrent_tasks} tasks, used {num_threads_used} threads")
            assert num_threads_used == n_concurrent_tasks

    async def main_async():
        for n_concurrent_tasks in range(1, 20, 4):
            print(f"n_concurrent_tasks: {n_concurrent_tasks}")
            res = await asyncio.gather(*[bar() for _ in range(n_concurrent_tasks)])
            num_threads_used = len(set(res))
            print(f"Dispatched {n_concurrent_tasks} tasks, used {num_threads_used} threads")
            assert num_threads_used == 1
    
    asyncio.run(main_wrapped())
    asyncio.run(main_async())
```
If we run this unit test, we'll get something like this:

```
tests/test_async_wrapper.py::test_wrapped_concurrent_thread_limit n_concurrent_tasks: 1
Dispatched 1 tasks, used 1 threads
n_concurrent_tasks: 5
Dispatched 5 tasks, used 5 threads
n_concurrent_tasks: 9
Dispatched 9 tasks, used 9 threads
n_concurrent_tasks: 13
Dispatched 13 tasks, used 13 threads
n_concurrent_tasks: 17
Dispatched 17 tasks, used 17 threads
n_concurrent_tasks: 1
Dispatched 1 tasks, used 1 threads
n_concurrent_tasks: 5
Dispatched 5 tasks, used 1 threads
n_concurrent_tasks: 9
Dispatched 9 tasks, used 1 threads
n_concurrent_tasks: 13
Dispatched 13 tasks, used 1 threads
n_concurrent_tasks: 17
Dispatched 17 tasks, used 1 threads
PASSED
```

As we can see, when we use the async_wrap decorator, we are using a different thread for each task, but when we use the async sleep, we are using the same thread for all tasks.

In other words, the event loop can use multiple threads to run tasks concurrently, but it will only use one thread if all tasks are async.


### Is there a way to limit the # of threads an event loop can use?


One way is through the executor argument of our decorator to explicitly specify a custom executor for our tasks.

```py
def test_async_limited_threads() -> None:

    # executor with only 2 threads
    executor = ThreadPoolExecutor(max_workers=2)

    @async_wrap(executor=executor)
    def foo():
        time.sleep(0.1)
        return threading.get_ident()
    
    async def main_wrapped():
        for n_concurrent_tasks in range(1, 20, 4):
            print(f"n_concurrent_tasks: {n_concurrent_tasks}")
            res = await asyncio.gather(*[foo() for _ in range(n_concurrent_tasks)])
            num_threads_used = len(set(res))
            print(f"Dispatched {n_concurrent_tasks} tasks, used {num_threads_used} threads")
            assert num_threads_used <= 2

    asyncio.run(main_wrapped())
```

Output:
```
tests/test_async_threads.py::test_async_limited_threads n_concurrent_tasks: 1
Dispatched 1 tasks, used 1 threads
n_concurrent_tasks: 5
Dispatched 5 tasks, used 2 threads
n_concurrent_tasks: 9
Dispatched 9 tasks, used 2 threads
n_concurrent_tasks: 13
Dispatched 13 tasks, used 2 threads
n_concurrent_tasks: 17
Dispatched 17 tasks, used 2 threads
```
As we can see, we are using at most 2 threads for all tasks.


### Part 1 summary

- asyncio event loop can run tasks concurrently
- asyncio event loop can run using different executors which gives you the ability to run things on different threads and different process pools
- since threads in Python is single core only due to GIL, it cannot speed up compute-bound tasks like a expensive calculation or a neural network training step - but it is handy if there's a lot of IO bound tasks.
- We can wrap existing synchronous code with decorator utilities to make it play nice with the async framework
