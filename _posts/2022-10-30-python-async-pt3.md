---
layout: post
title:  "Dive into Python asyncio - part 3, practical issues and system design considerations"
date:   2022-10-30 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---


In the third part of my write-up of using Python asyncio in a real project. I will discuss some practical issues and system design trade-offs I ran into while using asyncio.

- Dealing with task timeouts and graceful shutdown problem
- Shielding tasks from cancellation and where it's used
- Using asyncio in a multi-threaded, multiprocess environment
- Error handling and propagation with event loops

<!--more-->


## Dealing with exceptions and error states

Because coroutines are run in an event loop - the exceptions cannot be bubbled up the callstack in a traditional way. Instead, the exception is caught by the event loop and logged. This is a problem because it makes it hard to debug and handle errors in a systematic way.

Asyncio official documentation recommends registering a global exception handler to handle exception.

```python
def handle_exception(loop, context):
    # context["message"] will always be there; but context["exception"] may not
    msg = context.get("exception", context["message"])
    logging.error(f"Caught exception: {msg}")
    logging.info("Shutting down...")
    asyncio.create_task(shutdown(loop))
```

This handler will be called whenever an exception is thrown in the event loop.



## Handling signals and graceful shutdown

Asyncio allows us to register signal handlers for the common POSIX signal types.

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