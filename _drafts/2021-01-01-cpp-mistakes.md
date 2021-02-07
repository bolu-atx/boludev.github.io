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

This code is syntatically correct, it will compile (on C++11 or newer), and in debug mode, you will even get the expected result. 

```
lambda callback                                                                                                                            
value is 3                                                           
```

But is it correct? The answer is obviously.. No, it's not correct! Can you see what's wrong with it?

the `get_callback` method here returns a lambda function that captures the `some_val` by reference. Which will be pop-offed the stack of the `get_callback` once it completes execution. As a result, this code has *undefined* behavior depending on the compiler and the build mode (release vs debug) of your code.

You will be surprised how often this happens in large callback functions or threadpools where there are multiple things in flight with limited apriori information on the life-time of these objects.

How to solve this? use capture by value on light-weight objects, and wrap heavy objects with a `shared_ptr` and then explicitly capture the pointer by value to make sure the reference count on the object gets properly incremented.

### 2. Modifying an iterable data structure during iteration

Say you have an collection of data in an unordered map (could be a bunch of buffers, or a bunch of objects), being a good programmer, you want to iterate over this map but do a bunch of actions at once instead of iterating over it multiple times, you write the following loop:

```cpp

std::unordered_map<ktype, val>::iterator itr = items.begin();
std::unordered_map<ktype, val>::iterator end = items.end();

for (;itr!=end;++itr)
{
    if condition_check(*itr)
    {
        //do stuff
    }
    else {
        // delete stuff
        items.erase(itr);
    }
}
```

Will this compile? Yes!  Will this work? No!

What's wrong with it? Well, the `erase` method, as defined by `std::unordered_map` will invalidate all iterators, pointers when called. As a result, you will be incremeting a nullptr in the next iteration of the data.

This one is not too bad - if you are good at writing unit tests, you should catch this fairly quickly - since it tends to lead to segfaults of your program.

A more sinister analog of this iteration issue could arise if you work with custom data structures and tries to iterate over a bunch of identically sized structures in one loop to be efficient, something like this:

```cpp
ASSERT(customStructure.size() == vecB.size())

for (size_t i = 0; i < listA.size(); ++i)
{
    if (vecB[i].condition_fn_check())
    {
        customStructure.remove(i); 
        // BAD - i is no longer synchronized
        // If there's no bound check on the index operator for customStructure
        // this will result in undefined behavior!!
    }
}

```

### 3. Use `size_t` in a data structure definition

When communicating with other programs, clients, servers, or file system, we often need to define a structure with a relatively straight forward memory layout to facilitate data serialization / deserialization / io.

```cpp
#pragma pack
struct DataSpec {
    uint8_t version;
    char[256] description;
    size_t element_count;
    uint8_t per_element_bytes;
}    

    
public:
    DataSpec() {}

}
```


### 4. `pragma pack` and then forgot to unpack

See [GNU compiler documentation on pragma packing][1]

### 5. Throwing an exception in the destructor


### 6. Implicit mutexes in multi-threaded programs


[1]:https://gcc.gnu.org/onlinedocs/gcc-4.4.4/gcc/Structure_002dPacking-Pragmas.html