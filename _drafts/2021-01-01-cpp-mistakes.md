---
layout: post
title:  "Common mistakes in C++"
date:   2021-01-01 15:06:06 -0700
tags: blog cpp programming
author: bolu-atx
categories: blog cpp programming
---

Cpp is a hard language - just when you think you've know the quirks of it, something new will pop up and make you in awe of how much expressiveness and power the language enables the user. These are the mistakes I've made in my daily usage of Cpp. I hope they can be useful for other people to avoid them in the future.

### Capture by reference transient objects

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

This code compiles, and in debug mode, you will likely get the right answer, for example:

```
lambda callback                                                                                                                            
value is 3                                                           
```

the `get_callback` method would return a lambda function that make use of `some_val` inside the scope of the lambda function generator method. However, this code could have *undefined* behavior depending on the compiler and the build mode (release vs debug) of your code since the compiler doesn't need to make any guarantee of the lifetime of the referrenced variable.

How to solve this? use capture by value on light-weight objects, and wrap heavy objects with a `shared_ptr` and then explicitly capture the pointer by value to make sure the reference count on the object gets properly incremented.