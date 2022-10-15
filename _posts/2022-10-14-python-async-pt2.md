---
layout: post
title:  "Dive into Python asyncio - part 2"
date:   2022-10-14 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---

In the second part of this series on deep diving into `asyncio` and `async/await` in Python, we will be looking at the following topics:

- task, task groups, task cancellation
- async queues
- async locks and semaphores
- async context managers
- async error handling

<!--more-->

### Task, Task Groups, Task Cancellation

Tasks are the basic unit of work in `asyncio`. A task is a coroutine that is scheduled to run in the event loop. Tasks are created using the `asyncio.create_task()` function. The `asyncio.create_task()` function takes a coroutine as an argument and returns a `Task` object. The `Task` object is a subclass of `Future` and can be used to cancel the task.

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

async def main():
    task1 = asyncio.create_task(foo())
    task2 = asyncio.create_task(bar())
    await asyncio.sleep(5)
    task1.cancel()
    task2.cancel()

asyncio.run(main())
```

Note the above example is very similar to `asyncio.run`, the main difference is that tasks can be cancelled before they are done. When an executing async function is cancelled, a `CancelledError` exception is raised. The `CancelledError` exception can be caught and handled in the async function.

```py

import asyncio

async def foo():
    try:
        while True:
            await asyncio.sleep(1)
            print("foo")
    except asyncio.CancelledError:
        print("foo cancelled")

async def main():
    task1 = asyncio.create_task(foo())
    await asyncio.sleep(5)
    task1.cancel()


>>> asyncio.run(main())
foo
foo
foo
foo
foo
foo cancelled
```

Dispatching groups of tasks can done by simply calling `create_task` in a loop.

```py
import asyncio

async def foo(id, sleep_time = 1):
    while True:
        await asyncio.sleep(sleep_time)
        print("foo with id {}".format(id))

async def main():
    tasks = [asyncio.create_task(foo(i)) for i in range(5)]
    await asyncio.sleep(5)
    for task in tasks:
        task.cancel()

asyncio.run(main())
```

Alternatively, we can use `asyncio.gather`, but we'll lose the task handle and have to access it via the `all_tasks` method.

```py
import asyncio

async def foo(id, sleep_time = 1):
    while True:
        await asyncio.sleep(sleep_time)
        print("foo with id {}".format(id))

async def main():
    await asyncio.gather(*[foo(i) for i in range(5)])
    await asyncio.sleep(5)

    # cancel all dispatched tasks
    for task in asyncio.all_tasks():
        task.cancel()

asyncio.run(main())
```

The `asyncio.create_task` method will use the existing event loop. The current Python syntax does not support passing in a custom event loop, however, `create_task` is also a method on the event loop, so to explicitly specify the event loop, we can do the following:

```py
loop = asyncio.new_event_loop()
# task now running on event loop we just created
task = loop.create_task(foo())
```

In most cases, we will not need to explicitly create a new event loop. One of the few exceptions is if we know we'll be doing the asyncio in a background thread. In which case, we'll need to create a custom executor and pass it to the event loop as a parameter.

```py
import asyncio
import concurrent.futures

def blocking_io():
    # File operations (such as logging) can block the
    # event loop: run them in a thread pool.
    with open('/dev/urandom', 'rb') as f:
        return f.read(100)

def cpu_bound():
    # CPU-bound operations will block the event loop:
    # in general it is preferable to run them in a
    # process pool.
    return sum(i * i for i in range(10 ** 7))

async def main():
    loop = asyncio.get_running_loop()

    ## Options:

    # 1. Run in the default loop's executor:
    result = await loop.run_in_executor(
        None, blocking_io)
    print('default thread pool', result)

    # 2. Run in a custom thread pool:
    with concurrent.futures.ThreadPoolExecutor() as pool:
        result = await loop.run_in_executor(
            pool, blocking_io)
        print('custom thread pool', result)

    # 3. Run in a custom process pool:
    with concurrent.futures.ProcessPoolExecutor() as pool:
        result = await loop.run_in_executor(
            pool, cpu_bound)
        print('custom process pool', result)

asyncio.run(main())
```

For event loop that runs a CPU bound task, the main loop will not block while the executor is doing the work. The main loop will continue to run and process other tasks. The main loop will be blocked when it tries to get the result of the task from the executor. As a result, if there's a lot of context switching between the main loop and the executor, it may be more efficient to run the CPU bound task in a separate process.

### Async Queues

`asyncio` provides a queue implementation that can be used to schedule coroutines to run in a first-in-first-out order. The `asyncio.queue` implementation is NOT thread-safe. However, this is not an issue as long as we do not have concurrent tasks executing on different threads. A typical asyncio producer/consumer pattern looks like this:

```py

import asyncio

async def producer(queue, n):
    for x in range(n):
        print('producing {}/{}'.format(x, n))
        # simulate i/o operation using sleep
        await asyncio.sleep(1)
        item = str(x)
        # put the item in the queue
        await queue.put(item)

    # indicate the producer is done
    await queue.put(None)

async def consumer(queue):
    while True:
        # wait for an item from the producer
        item = await queue.get()

        if item is None:
            # the producer emits None to indicate that it is done
            break

        print('consuming item {}...'.format(item))
        # simulate i/o operation using sleep
        await asyncio.sleep(1)

        # Notify the queue that the item has been processed
        queue.task_done()

async def main():
    # Create a queue that we will use to store our messages
    queue = asyncio.Queue()

    # schedule the consumer
    consumer_task = asyncio.create_task(consumer(queue))

    # run the producer and wait for completion
    await producer(queue, 10)

    # wait until the consumer has processed all items
    await queue.join()

    # the consumer is still awaiting for an item, we can
    # cancel it now
    consumer_task.cancel()

asyncio.run(main())

>>> producing 0/10
>>> consuming item 0...
>>> producing 1/10
>>> consuming item 1...
>>> producing 2/10
>>> consuming item 2...
>>> producing 3/10
>>> consuming item 3...
...
```

### Async Locks

Locks are a parallel programming concept familiar to most C++/C developrs. In Python, we can use the `asyncio.Lock` class to implement a lock. The `asyncio.Lock` class is NOT thread-safe. Its purpose is to limit concurrent access to a shared resource.  Typical usage example:

```py
import asyncio

async def worker_with(lock, worker_id):
    print('worker {} is waiting for the lock'.format(worker_id))
    async with lock:
        print('worker {} has acquired the lock'.format(worker_id))
        await asyncio.sleep(1)
    print('worker {} has released the lock'.format(worker_id))

async def main():
    lock = asyncio.Lock()
    await asyncio.gather(*(worker_with(lock, i) for i in range(3)))

asyncio.run(main())

>>> worker 0 is waiting for the lock
>>> worker 1 is waiting for the lock
>>> worker 2 is waiting for the lock
>>> worker 1 has acquired the lock
>>> worker 1 has released the lock
>>> worker 2 has acquired the lock
>>> worker 2 has released the lock
>>> worker 0 has acquired the lock
>>> worker 0 has released the lock
```

Note the `asyncio.Lock` implements `__aenter__` and `__aexit__` methods, so we can use it in a `with` statement. The `asyncio.Lock` class also implements the `locked` property, which can be used to check if the lock is currently acquired.

When an async task has the lock, even during an `await` context switch, the lock is still held. Preventing other tasks that might have been context-switched to from accessing the protected resource. The resource is typically:

- a shared data structure
- a shared file
- a shared database connection 


Semaphores are similar to locks, but they allow a limited number of tasks to acquire the lock. The `asyncio.Semaphore` class implements a semaphore.

```py
import asyncio

async def worker_with(semaphore, worker_id):
    print('worker {} is waiting for the semaphore'.format(worker_id))
    async with semaphore:
        print('worker {} has acquired the semaphore'.format(worker_id))
        await asyncio.sleep(1)
    print('worker {} has released the semaphore'.format(worker_id))

async def main():
    semaphore = asyncio.Semaphore(2)
    await asyncio.gather(*(worker_with(semaphore, i) for i in range(3)))

asyncio.run(main())

>>> worker 0 is waiting for the semaphore
>>> worker 1 is waiting for the semaphore
>>> worker 0 has acquired the semaphore
>>> worker 2 is waiting for the semaphore
>>> worker 1 has acquired the semaphore
>>> worker 0 has released the semaphore
>>> worker 2 has acquired the semaphore
>>> worker 1 has released the semaphore
>>> worker 2 has released the semaphore
```


### Async Events

Analogous to condition variables in C++, the `asyncio.Event` allows tasks that require a certain condition to be satisfied from proceeding to wait until said condition is ready. The `asyncio.Event` class implements the `wait` and `set`, which is analogous to `wait` and `notify` in C++.

```py
import asyncio

async def waiter(event):
    print('waiting for it...')
    await event.wait()
    print('...got it!')

async def main():
    # Create an Event.
    event = asyncio.Event()

    # Spawn a Task to wait until 'event' is set.
    await asyncio.gather(waiter(event), waiter(event), waiter(event))

    # Sleep for 1 second and set the event.
    await asyncio.sleep(1)
    event.set()

asyncio.run(main())
```

Note that an `event` can have multiple tasks waiting on it. When the event is set, all tasks waiting on the event are notified. (analogous to `cv.notify_all()` in C++)

Events can be re-used, via the `clear()` method, which will block again until the event is set again.


However, asyncio Event does not protect shared resources from concurrent access. It is only used to signal that a certain condition is ready. To enable shared resource conditional access, we can use a `asyncio.Condition` object. The `asyncio.Condition` class implements the `wait` and `notify` methods, which is analogous to `wait` and `notify` in C++.


### Async Context Managers

Context managers are a Python feature that allows us to define a block of code that will be executed before and after a block of code. A simple example would be the `asyncio.Lock` class implements the `__aenter__` and `__aexit__` methods. However, this pattern can be very powerful:

```py
async with RequestHandler(store_url) as handler:
    async with handler.open_read(obj_id, config=config) as reader:
        frames = await reader.read(720, count=480)

        # Do other things using reader
        ...

    # Do other things using handler
    ...
...
```

This is almost identical to the synchronous `with` blocks, the small caveat is that the `__enter__` method of the async version can be `awaited`, so if some resource is IO bound or blocked for other reasons, the loop can do a context switch and work on other tasks until the resource is ready.


Whew, this post is getting long, let's move onto the last topic we wanted to cover:

### Async Error Handlers

The `asyncio` module provides a way to register an error handler for all tasks. This is useful for logging errors, or for debugging purposes. The `asyncio` module provides the `set_exception_handler` function, which takes a callback function as an argument. The callback function will be called with the following arguments:


```py
import asyncio
def exception_handler(loop : asyncio.AbstractEventLoop, context : dict):
    msg = context.get('exception', context['message'])
    print('Caught exception: {}'.format(msg))
    print('Exception context: {}'.format(context))
    print('Stop the event loop')
    loop.stop()

loop = asyncio.get_event_loop()
loop.set_exception_handler(exception_handler)
```
To use a specific handler for only one task, we can use the `asyncio.Task.set_exception_handler` method. This method takes a callback function as an argument. The callback function will be called with the following arguments:

```py
import asyncio

async def task_with_exception():
    raise Exception('This exception is expected')

async def main():
    task = asyncio.create_task(task_with_exception())
    task.set_exception_handler(lambda t, c: print('Caught exception: {}'.format(c['exception'])))
    await task

asyncio.run(main())

>>> Caught exception: This exception is expected
```


Ok, I think that just about covered all the topic I wanted to go into for the part 2 of the series.

In part 3, I will try to address some of the real life challenges of using `asyncio` in a fairly complex, multiprocess code-base. Including how to interface `asyncio` with other synchornous parts of the code-base, and how to use `asyncio` in a multi-process environment.