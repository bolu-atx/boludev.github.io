---
layout: post
title:  "What is copiable?"
date:   2023-09-01 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---


It is no surprise that the GIL is one of the biggest drawbacks of using Python in performance oriented applications. The GIL, or Global Interpreter Lock, is a mutex that protects access to Python objects, preventing multiple threads from executing Python bytecodes at once. This means that even if you have multiple threads running in parallel, only one of them can execute Python code at a time. This can be a major bottleneck for applications that require high performance, as it limits the amount of parallelism that can be achieved.

To defeat the GIL, there are two commonly taken path:

- the first is to opt for multiprocessing instead of threads. 
- Re-write the core performance critical code using a lower level language such as C++ or Rust

Today, let's talk about the 2nd approach. With excellent next generation binding libraries such as `pybind11` and `pyo3`, it has become a lot simpler to support Rust/C++ code in a Python project.

However, often the porting to C++ / Rust from existing application code do not happen overnight. In the beginning, it is mostly a few performance critical functions that are ported to C++ / Rust. In such cases, it is common to see a mix of Python and C++ / Rust code in the same project. In these cases, the threading architecture / parallelism code could still be in Python, while the performance critical code is in C++ / Rust.

I've personally dealt with such systems where the GIL became a major bottleneck in the performance of the system due to ill-undertsanding of how it worked. As a result, I'm sharing my findings here.

## A simple problem to demonstrate GIL in C++

In this toy example, we create an `expensive_cpp_func()` that gets bound as a python method via `pybind`, we run this function in a threadpool executor and measures its time to complete.

```cpp
// example.cpp - naive impl, no GIL handling
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <pybind11/functional.h>


#include <iostream>
#include <chrono>

namespace py = pybind11;

int expensive_cpp_func(int n) {
    // returns cumulative sum of n
    int sum = 0;
    for (int i = 0; i < n; i++) {
        sum += i;
    }
    std::this_thread::sleep_for(std::chrono::seconds(5));
    return sum;
}

PYBIND11_MODULE(example, m) {
    m.def("expensive_cpp_func", &expensive_cpp_func);
}

```

Once we compile this code, we'll get a `.so` library that we can use in Python.

```py
import example

from concurrent.futures import ThreadPoolExecutor
import time

def run_expensive_func():
    futures = []
    with ThreadPoolExecutor(5) as executor:
        start = time.time()
        for n in range(5):
            future = executor.submit(example.expensive_cpp_func, n)
            futures.append(future)
        
        # wait for all futures to complete before printing
        res = []
        for future in futures:
            if future.done():
                print(future.result())
                futures.remove(future)
        end = time.time()
```

As we'd expect, although we have a threadpool in Python and are calling it concurrently. The GIL prevents the threads from running concurrently, each function call will take 5 seconds and in total it'll take 25 seconds to complete.



### How do we speed this up?

Well, it turned out, pybind has a whole section of tools dedicated to managing fine grained control of the GIL. One of the most common ways to release the GIL is to use `py::gil_scoped_release()` as a `call_guard` in the `def` statement. This will release the GIL before calling the function and re-acquire it after the function returns.


With this, we can modify the original example.cpp with the following code:
```cpp
// example.cpp - release GIL before calling expensive_cpp_func
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <pybind11/functional.h>


#include <iostream>
#include <chrono>

namespace py = pybind11;

int expensive_cpp_func(int n) {
    // returns cumulative sum of n
    int sum = 0;
    for (int i = 0; i < n; i++) {
        sum += i;
    }
    std::this_thread::sleep_for(std::chrono::seconds(5));
    return sum;
}

PYBIND11_MODULE(example, m) {
    m.def("expensive_cpp_func", &expensive_cpp_func, py::call_guard<py::gil_scoped_release>());
}
```

Adding the `call_guard` means the GIL release lives for the duration of the function call. When the function returns, the GIL is re-acquired, the integer return type is converted to a Python object, and then returned to the Python interpreter.

As expected, after we make this change, the total execution time will be 5 seconds, as all the threads will run concurrently.

### Big drawback of releasing GIL

Releasing the GIL is not a silver bullet. It is a double edged sword. Releasing the GIL means we can no longer safely interact with Python objects. This means we can't use any Python objects in the function that we release the GIL for. This is because Python objects are reference counted and the reference count can change in another thread, leading to memory corruption.

In the example above, we are not using any Python objects in the `expensive_cpp_func`, so it is safe to release the GIL. However, if we were to use Python objects, we would have to be very careful to ensure that we don't corrupt memory.

As a result, pybind provides scoped guards that can be used to release the GIL for a specific block of code. This is a safer way to release the GIL, as it ensures that the GIL is re-acquired when the block of code is exited.

```cpp
// example.cpp - release GIL with scope guards
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <pybind11/functional.h>


#include <iostream>
#include <chrono>

namespace py = pybind11;

int expensive_cpp_func(int n) {
    // returns cumulative sum of n
    int sum = 0;
    for (int i = 0; i < n; i++) {
        sum += i;
    }

    // release gil for just this expensive block
    {
        py::gil_scoped_release release;
        std::this_thread::sleep_for(std::chrono::seconds(5));
    }

    return sum;
}

PYBIND11_MODULE(example, m) {
    m.def("expensive_cpp_func", &expensive_cpp_func);
}
```

In the above impl, most of the compute is still done with the GIL acquired, but when we get to the "expensive" part, we release the GIl for the duration of that expensive compute, and then re-acquire it after the compute is done. In a long or complex function, this could be done many times to release the GIL for short periods of time for crtical blocking operations that needs to be parallelized.


## Conclusion

GIL-free C++ code combined with Threadpool executors in Python is a powerful combination to speed up your Python code. However, it is important to be aware of the limitations of releasing the GIL and to use it judiciously. In general, it is best to avoid releasing the GIL unless absolutely necessary, and to use scoped guards when releasing the GIL to ensure that it is re-acquired when needed.

In addition, the cost of releasing and reacquiring the GIL is non-trivial, we should avoid doing this in the hot path of our code. From a software architecture design standpoint, we should try to isolate compute heavy code to one side of the Python/C++ bridge, and cross that boundary as infrequently as possible.