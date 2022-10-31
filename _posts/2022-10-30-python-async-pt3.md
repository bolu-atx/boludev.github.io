---
layout: post
title:  "Dive into Python asyncio - part 3, practical issues and system design considerations"
date:   2022-10-30 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---


In the third part of my write-up of using Python asyncio in a real project. I will discuss some practical issues and system design trade-offs I ran into while using asyncio.

- Dealing with tasks (cancellation, timeout, and handling OS signals)
- Shielding tasks from cancellation and where it's used
- Using asyncio in a multi-threaded, multiprocess environment
- Error handling and propagation with event loops

<!--more-->


## Dealing the `unhpapy` path when using `asyncio.create_task`

### Exceptions or unexpected error states

Because coroutines are run in an event loop - the exceptions cannot be bubbled up the callstack in a traditional way. Instead, the exception is caught by the event loop and logged. This is a problem because it makes it hard to debug and handle errors in a systematic way.

Asyncio official documentation recommends registering a global exception handler to the event loop to handle exceptions. 

```python
def handle_exception(loop, context):
    # context["message"] will always be there; but context["exception"] may not
    msg = context.get("exception", context["message"])
    logging.error(f"Caught exception: {msg}")
    logging.info("Shutting down...")
    asyncio.create_task(shutdown(loop))
```

This handler will be called whenever an exception is thrown in the event loop.

For `asyncio.Task`, it depends on whether we are letting the task run in a background or calling `await` on it in another coroutine. For the background tasks, when an exception is hit - the task is considered "done" with exception. We can monitor for this event via a `done_callback`

```python
def test_exception_with_handler_in_task():
    ctx = { "hit_exception_handler": False }

    def task_result_done(task : asyncio.Task):
        print("Task result done called")
        ctx["hit_exception_handler"] = True
        try:
            r = task.result()
        except Exception as e:
            print(f"Exception occured: {e}")
            pass

    async def coro():
        raise RuntimeError("intentional exception")

    async def test_fn():
        print("Spawning task")
        task = asyncio.create_task(coro())
        # add a callback
        task.add_done_callback(task_result_done)
        try:
            await task
        except:
            pass
        print(f"task done? {task.done()}, task cancelled? {task.cancelled()}, exception? {task.exception()}")
        assert ctx['hit_exception_handler']
        
    asyncio.run(test_fn())
```

Running the above code will generate something like this:

```
tests/asyncio_tests/test_async_exception_handling.py::test_exception_with_handler_in_task Spawning task
Task result done called
Exception occured: intentional exception
task done? True, task cancelled? False, exception? intentional exception
PASSED
```

Note that even though we have the `done` callback registered with the task, we still need to `try`/`catch` the spawning function that is calling `await` on the task. Because the return type of the task when you call `await` and the task had an exception is an Exception type - which will terminate the entire program if you do not handle it.


### Handling OS signals and graceful shutdown

Asyncio allows us to register signal handlers for the common POSIX signal types, a common pattern I've seen used is to spawn a shutdown task when these signals are received - this ensures that all the tasks are cancelled and the event loop is closed gracefully.

```python
signals = (signal.SIGHUP, signal.SIGTERM, signal.SIGINT)
for s in signals:
    loop.add_signal_handler(
        s, lambda s=s: asyncio.create_task(shutdown(s, loop)))
```

The `shutdown` method can then be used to gracefully shutdown the application.

```python
async def shutdown(signal, loop):
    logging.info(f"Received exit signal {signal.name}...")

    # cancel all tasks except the current one
    tasks = [t for t in asyncio.all_tasks() if t is not
             asyncio.current_task()]

    [task.cancel() for task in tasks]

    logging.info(f"Cancelling {len(tasks)} outstanding tasks")
    await asyncio.gather(*tasks, return_exceptions=True)
    loop.stop()
```