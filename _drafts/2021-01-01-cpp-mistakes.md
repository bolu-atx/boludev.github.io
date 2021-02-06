---
layout: post
title:  "Common C++ mistakes I made"
date:   2021-02-02 15:06:06 -0700
tags: blog cpp programming
author: bolu-atx
categories: blog cpp programming
---

Internet consensus tends to label C++ as a hard language; I like to think Cpp is a "deep" language. There are always rooms for improvement - doesn't matter how long you have been coding in C++. The expressiveness and the depth of the language is double-edged. It is what makes C++ great, but also makes it daunting for new users. These are the mistakes I've made in my daily usage of C++. I hope they can be useful for other people to avoid them in the future.

### 1. Capture by reference on transient objects

Callbacks (lambda functions, function pointers, functors, or `std::bind` on static functions) are a common paradigm when you work with message queues, thread pools, or event based systems. Lambda and closures give you a lot of power - but too much power could often cause problems, consider the following code:

Example:

```cpp
#include <iostream>
#include <functional>

typedef std::function<void()> callback_t;

callback_t get_callback() {
    int some_val = 1337;
    
    return [&some_val](){
        some_val = 3;
        std::cout << "lambda callback\n value is " << some_val;
        
    };
}

int main()
{
    auto cb = get_callback();
    // do some other work
    cb();
    return 0;
}
```

This code is syntatically correct, it will compile (on C++11 or newer), and in debug mode, you will even get the expected result. But is it correct?

The answer is obviously.. No, it's not correct! Can you see what's wrong with it?

```
lambda callback                                                                                                                            
value is 3                                                           
```

the `get_callback` method would return a lambda function that make use of `some_val` inside the scope of the lambda function generator method. However, this code could have *undefined* behavior depending on the compiler and the build mode (release vs debug) of your code since the compiler doesn't need to make any guarantee of the lifetime of the referrenced variable.

How to solve this? use capture by value on light-weight objects, and wrap heavy objects with a `shared_ptr` and then explicitly capture the pointer by value to make sure the reference count on the object gets properly incremented.


### 2. Modifying an iterable data structure during iteration


### 3. Use `size_t` in a data structure definition


### 4. `pragma pack` and then forgot to unpack


### 5. Throwing an exception in the destructor


### 6. Implicit mutexes in multi-threaded programs