---
layout: post
title:  "Asyncio from scratch"
date:   2024-05-30 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---


`asyncio` in Python is a library that provides a way to write concurrent code using the `async` and `await` syntax. It is built on top of the `asyncio` event loop, which is a single-threaded event loop that runs tasks concurrently. Inspired by a similar post by [Jacob](https://jacobpadilla.com/articles/recreating-asyncio), we will explore how `asyncio` works from scratch by implementing our own event loop runtime with Python generators.

<!--more-->

## Coroutine basics in Python

Before we can dive into the implementation, a quick primer on how generators work in Python, this is all with vanilla Python and does not touch upon anything with `async` keywords. David Beasly has a great talk on this called "A Curious Course on Coroutines and Concurrency" which I highly recommend.


### `yield` in Python generators / coroutines

Most people are familiar with generators that `yield` something and then we can iterate over it. For example:

```python
def iterable_dirs(regex  : str) -> Iterable[str]:
	"""Iterates over directories that match the regex"""
	for root, dirs, files in os.walk('.'):
		for dir in dirs:
			if re.match(regex, dir):
				yield os.path.join(root, dir)

# to use this
for dir in iterable_dirs(r'^[a-z]'):
	print(dir)

```

### `send` and `yield` to communicate with a coroutine

However, yield can also be used to communicate with the caller. For example, we can send values to the generator using the `send` method. This is how we can implement a simple coroutine in Python:

```python
def coroutine():
	print("coroutine started")
	while True:
		value = yield
		print(f"received value: {value}")

# to use this
c = coroutine()
next(c)
c.send(1)
c.send(2)

# we would see
# >  coroutine started
# >  received value: 1
# >  received value: 2
```

Note the first call to `next(c)` is needed to start the coroutine. This is because the first call to `send` will not work. This is because the coroutine is not yet started. The `next` call will start the coroutine and then the first `send` call will work.

### `yield from` to delegate to another coroutine

We can also use `yield from` to delegate to another coroutine. This is useful when we want to call another coroutine and then return the value back to the caller. For example:

```python
def coroutine():
	print("coroutine started")
	while True:
		value = yield from sub_coroutine()
		print(f"received value: {value}")

def sub_coroutine():
	print("sub coroutine started")
	while True:
		value = yield
		print(f"sub coroutine received value: {value}")

# to use this
c = coroutine()
next(c)
c.send(1)
c.send(2)

# we would see
# >  coroutine started
# >  sub coroutine started
# >  sub coroutine received value: 1
# >  received value: 1
# >  sub coroutine received value: 2
# >  received value: 2

```

### Returning values from a coroutine in Python

Typically values are "yielded" to the caller via the `yield` keyword. However, you can also return using the `return` keyword just like a regular function. However, the return value is wrapped in a `StopIteration` exception. For example:


```python
def corou():
	print("coroutine started")
	while value := yield:
		print(f"received value: {value}")
	return "done"
```

If we run this coroutine, we would see:

```python
c = corou()
next(c)
c.send(1)
c.send(2)
c.send(None)

# we would see
# >  coroutine started
# >  received value: 1
# >  received value: 2
# >  StopIteration: done
```






The lifetime of variables declared in a coroutine is tied to the lifetime of the coroutine, as a result, as we go back and forth between the caller and the coroutine, the variables are preserved. This is how we can implement a simple state machine using coroutines.


## Implementing a Asyncio Runtime

### Cooperative multitasking with generators and coroutines

At the heart of the asyncio runtime is an event loop, in the asyncio impl, the event loop is written in C, but here we can implement it in Python. Each event in the event loop is something that can be resumed, suspended, and fits the generator paradigm quite nicely. We can use `next()` mechanism to wake up a task, run the code until some blocking event, and then `yield` to return control back to the loop for it to work on something else.


A simple example of the above concept can be illustrated below.

```python
def task1():
	while True:
		print("task1")
		yield

def task2():
	while True:
		print("task2")
		yield


event_loop = [task1(), task2()]
while True:
	for task in event_loop:
		next(task)
```

Here we have a static event loop with only two tasks (not very useful in real life), but you can see how we can run the tasks concurrently. The `next(task)` call will run the task until the next `yield` statement and then move on to the next task. This is the basic idea behind the asyncio event loop.


### Dealing with blocking IO - `asyncio.sleep` example

Now let's see if we can impelment `asyncio.sleep` with coroutines. The idea here is we want to wake up this thread that's running the async sleep call and check if the time elapsed has reached, if not, we suspend the task and give back control.


```python
import time

def sleep_async(seconds):
	start = time.time()
	while True:
		if time.time() - start >= seconds:
			return
		yield

def task1():
	while True:
		print("task1")
		yield from sleep_async(1)

def task2():
	while True:
		print("task2")
		yield from sleep_async(2)


event_loop = [task1(), task2()]
while True:
	for task in event_loop:
		next(task)

```

You could probably guess what this is doing, the `yield from` statement here is similar to `await` in asyncio, it suspends the task until the sleep is done. The `sleep_async` function is a simple coroutine that checks if the time elapsed is greater than the time we want to sleep for, if not, it yields control back to the event loop.

At its core, the `asyncio.sleep` basically does the same thing.


## Apply syntactic sugar with `async` and `await`

What does it mean to have a `async` keyword in front of a method in Python? Well, it turned out things are `Avaiable` if it implements the `__await__` method. This is how we can implement the `sleep` function with the `async` keyword.

This is an exampel of how `await` is implemented on `asyncio.Future`:

```python
def __await__(self):
	if not self.done():
		self._asyncio_future_blocking = True
		yield self
	if not self.done():
		raise RuntimeError("Event loop stopped before done")
	return self.result()
```

Since we cannot give `__await__` to a function, we need to create a class to encapsulate the state of the coroutine. Let's create a simple `Task` wrapper for this:

```python

event_loop = Queue()

class Task:
	def __init__(self, coro):
		self.coro = coro
		self.finished = False
		self.res = None

	def done(self):
		return self.finished

	def result(self):
		return self.res

	def __await__(self):
		while not self.done():
			yield self

		return self.result()

	@staticmethod
	def new(coro : Generator) -> Task:
		"""Create a new task from a coroutine"""
		task = Task(coro)
		event_loop.put(Task(coro))
		return task
```

When we call `await` on an instance of the `Task`, it will yield until someone else sets the `finished` state to `True`. 


```python
from queue import Queue

event_loop = Queue()

def run(main: Generator) -> None:
	event_loop.put(Task(main))
	while not event_loop.empty():
		task = event_loop.get()
		try:
			# wakes up the task and runs until the next yield
			task.coro.send(None)
		except StopIteration as e:
			task.finished = True
			task.res = e.value
		else:
			event_loop.put(task)
```

This code looks more complex now, let's break it down:

- We have a `Queue` to hold the tasks (this is our simple event loop)
- We have a `run` function that takes a generator and puts it in the queue
- We then run the event loop until the queue is empty
- We then get the task from the queue and run it until the next `yield` statement
- If the task is done, we set the `finished` flag to `True`, we also extract the StopIteration value and set it to the `result` field of the task
- If the task is not done, we put it back in the queue so it can be run again


With this `run` method, we can now run our tasks with the `await` keyword. For example:

```python
def _sleep(seconds : float) -> None:
    start_time = time.time()
    while time.time() - start_time < seconds:
        yield

async def sleep(seconds : float):
    task = Task.new(_sleep(seconds))
    return await task
```

## Putting it all together

Putting it all together, we now have the following:

```python
from queue import Queue
from typing import Generator
import time


event_loop = Queue()


class Task:
	def __init__(self, coro):
		self.coro = coro
		self.finished = False
		self.res = None

	def __repr__(self) -> str:
		return f"{self.coro}, finished {self.finished}, res : {self.res}"

	def done(self):
		return self.finished

	def result(self):
		return self.res

	def __await__(self):
		while not self.done():
			yield self

		return self.result()

	@staticmethod
	def new(coro) -> 'Task':
		"""Create a new task from a coroutine"""
		task = Task(coro)
		event_loop.put(task)
		return task

def run(main: Generator) -> None:
	event_loop.put(Task(main))
	while not event_loop.empty():
		task = event_loop.get()
		# print(f"Running task {task}")
		try:
			# wakes up the task and runs until the next yield
			task.coro.send(None)
		except StopIteration as e:
			task.finished = True
			task.res = e.value
		else:
			event_loop.put(task)


def _sleep(seconds : float):
	start_time = time.time()
	while (time.time() - start_time) < seconds:
		yield

	return time.time() - start_time

async def sleep(seconds : float) -> None:
	task = Task.new(_sleep(seconds))
	return await task

async def task1():
	for _ in range(2):
		print('Task 1')
		await sleep(1)

async def task2():
	for _ in range(3):
		print('Task 2')
		await sleep(2)

async def main():
	one = Task.new(task1())
	two = Task.new(task2())
	await one
	await two
	print("done")

if __name__ == '__main__':
	run(main())

```
If we run this code, we will see the following:

```
~/Tmp » python coro.py                                                                                                                                                                                                                                                                                                                                             146 ↵ bolu@BobookAir
Task 1
Task 2
Task 1
Task 2
Task 2
done
```


You will notice that there are some commented out `print` in the code, if we uncomment them, we'll see the context switches in action on the event loop:

```
Running task <coroutine object task2 at 0x102ab82b0>, finished False, res : None
Running task <coroutine object main at 0x102827920>, finished False, res : None
Running task <generator object _sleep at 0x10284af80>, finished False, res : None
Running task <coroutine object task2 at 0x102ab82b0>, finished False, res : None
Running task <coroutine object main at 0x102827920>, finished False, res : None
Running task <generator object _sleep at 0x10284af80>, finished False, res : None
Running task <coroutine object task2 at 0x102ab82b0>, finished False, res : None
Running task <coroutine object main at 0x102827920>, finished False, res : None
```

If you got this far, I hope you have enjoyed the post. Albeit being simple (we didn't even do any epoll / io_uring or any kind of OS level IO event integration), this taught me a lot about how asyncio works behind the scenes. It is obviously not as efficient as the C implementation and would not survive any production load, but the mental model is there. I hope you enjoyed this post as much as I did writing it. 