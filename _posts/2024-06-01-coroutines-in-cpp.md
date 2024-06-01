---
layout: post
title:  "coroutines in C++20"
date:   2024-06-01 15:06:06 -0700
tags: cpp coroutines async
author: bolu-atx
categories: programming
---

Coroutines are a new feature in C++20 that allows you to write asynchronous code in a synchronous manner. It is a way to write code that can be paused and resumed at a later time. In this post, I wanted to talk about coroutines in C++20 and how they can make asynchronous code in networking and file I/O much easier to write and understand.


<!--more-->

## Introduction to coroutines

Just like Python generators and `async/await` syntax, with C++20, we can now write asynchronous code in a synchronous manner. This is done using the `co_await` keyword and the `generator` and `async` types.

Here's a simple example of a coroutine that generates a sequence of numbers:

```cpp
#include <iostream>
#include <coroutine>

struct generator {
    struct promise_type {
        int current_value;
        auto initial_suspend() { return std::suspend_always{}; }
        auto final_suspend() noexcept { return std::suspend_always{}; }
        generator get_return_object() { return generator{this}; }
        void unhandled_exception() { std::terminate(); }
        std::suspend_always yield_value(int value) {
            current_value = value;
            return {};
        }
    };

    bool move_next() { return true; }
    int current_value() { return 0; }
};


generator numbers() {
    co_yield 1;
    co_yield 2;
    co_yield 3;
}

int main() {
    auto gen = numbers();
    while (gen.move_next()) {
        std::cout << gen.current_value() << std::endl;
    }
    return 0;
}

```

Compare and contrast this to the Python version:

```python
def numbers():
    yield 1
    yield 2
    yield 3
```

It begs the question, what the hell? Why is the C++ version so verbose? This is because the C++ coroutines allow for much finer grained control at the expense of user experience.