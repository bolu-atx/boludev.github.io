---
layout: post
title:  "Common, stupid, but non-obvious C++ mistakes I made"
date:   2021-02-06 15:06:06 -0700
tags: cpp programming
author: bolu-atx
categories: cpp programming
---

Internet consensus tends to label C++ as a hard language; I like to think Cpp is a "deep" language. There are always rooms for improvement - doesn't matter how long you have been coding in C++. The expressiveness and the depth of the language is double-edged. It is what makes C++ great, but also makes it daunting for new users. These are the mistakes I've made in my daily usage of C++. I hope they can be useful for other people to avoid them in the future.

### 1. Capture by reference on transient objects

Callbacks (lambda functions, function pointers, functors, or `std::bind` on static functions) are a common paradigm when you work with message queues, thread pools, or event based systems. Lambda and closures give you a lot of power - but too much power could often cause problems, consider the following code:

<!--more-->

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

But is it correct? The answer is obviously.. No, it's not correct 🙅‍♂️! Can you see what's wrong with it?

the `get_callback` method here returns a lambda function that captures the `some_val` by reference. Which will be pop-offed the stack of the `get_callback` once it completes execution. As a result, this code has *undefined* behavior depending on the compiler and the build mode (release vs debug) of your code.

You will be surprised how often this happens in large callback functions or threadpools where there are multiple things in flight with limited apriori information on the life-time of these objects.

How to solve this? use capture by value on light-weight objects, and wrap heavy objects with a `shared_ptr` and then explicitly capture the pointer by value to make sure the reference count on the object gets properly incremented.

### 2. Modifying an iterable data structure during iteration

Say you have an collection of data in an unordered map (could be a bunch of buffers, or a bunch of objects), being a good programmer, you want to iterate over this map but do a bunch of actions at once instead of iterating over it multiple times, you write the following loop:

```cpp

// you can also do `auto` , but the explicit iterator type is provided to improve clarity
std::unordered_map<ktype, val>::iterator itr = items.begin();
const std::unordered_map<ktype, val>::iterator end = items.end();

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
This is basically the same problem with iterators, but now you no longer have the C++ runtime libraries invalidating that pointer for you. The code will compile, it will run, but then you will get sneaky data inconsistencies and random behavior that will be hard to catch unless you are very rigorous with unit testing and integration testing.

As a result, I am now very careful doing data structure mutations while iterating. In most cases, unless you are dealing with the tightest of tight loops, you don't need to squeeze that 1-2% efficiency. In those cases, just collect the things to be deleted in a separate STL container and then operate on the items to be deleted later all at once.


### 3. Use `size_t` in a IO/serialized struct definition

When communicating with other programs, clients, servers, or file system, we often need to define a import/export data structure with a simple memory layout to make it easy to pack the data, for example:

```cpp
#pragma pack
struct DataSpecHeader {
    uint8_t version;
    char[256] description;
    size_t element_count;
    uint8_t per_element_bytes;
}    

// Skipped DataSpecBody here since it is variable lengthed, could be a pointer or a std::vec or some other type

struct DataSpecFooter {
    size_t bytes_written;
    size_t checksum;
}
```


This then allows you to define some method such as `DataSpecHeader get_header_serialization(const obj_t& obj)` to map the data members of your object to the struct defined above; when it's time to export the data, you can use it to directly write to a binary stream by `ostream.write(reinterpret_cast<char*>(data_spec_header),sizeof(data_spec_header)` in one call. I use this pattern a lot; is my preferred way of turning C++ data into bits.

This will work fine on your development machine, or even your production environment, great! Now you can move onto other things.

Is this correct? 

Well, by now you should know the answer to that question 😄, no, it's not correct 🙅‍♂️! What's wrong with it? Well.. `size_t` is a platform-dependent type defined for conveinience - on 32 bit x86 platforms, it is mapped to `uint32_t`, while on 64 bit platforms, it is mapped to `uint64_t`. However, it can also take on many other types depenending on where you are running the code (i.e. embedded devices, ARM, docker, etc). As a result, you are introducing another layer of variability into a format specification that is supposed to be **static**. At a minimum, this would cause data corruptions and errors in serialization down the line or when you communicate with another program / client that is still running on 32 bit or embedded device.


The fix? Use standard sized types that are unlikely to change in the near future. I am expecially a fan of `uint8_t, uint16_t, uint32_t, int64_t` type of notation - since it is very explicit on how many bits of memory it occupies.

### 4. `pragma pack` and then forgot to unpack

This is an extension of #3. As explained by this [StackOverflow post][2]:

> `#pragma pack` instructs the compiler to pack structure members with particular alignment. Most compilers, when you declare a struct, will insert padding between members to ensure that they are aligned to appropriate addresses in memory (usually a multiple of the type's size). This avoids the performance penalty (or outright error) on some architectures associated with accessing variables that are not aligned properly.

This is a common thing you will see before a IO/serializeable struct definition (like the exmaples #3). However, after the definition is complete, most cases people forget to do `#pragma pack(pop)` after the definition.  For example:

```cpp
#pragma pack(1)

struct ObjSerializableContainer {
    uint8_t version;
    // stuff
}

class ExportableModel : public IModel {
public:
    ExportableModel() {};
    ~ExportableModel() {};

    void exportObj(const std::string& path) {
        // method that uses ObjSerializableContainer
    }

private:
    size_t m_length;
    // etc
}
```

The side-effect of such action is that the compiler will treat all the struct and class definition after the point of the `pragma pack` statement to be following the same memory packing layout. 

Is there anything wrong with this? No, on most standalone and small programs, it will run fine without any issues. You might see a slight performance drop in niche cases since the member are not cacheline friendly / memory alignment friendly, but the program will still give you the expected behavior.

However, on larger projects, the packing could have unintended consequences. Since compilers compile each cpp file as a separate compliation unit, the effect of pragma packing will be applied to the compilation unit at the time of compilation. However, other components (static libs, or shared libs) of the same project might not be subjected to the same pragma packing directive. As a result, you might run into the same object definition across two components of a bigger project having different memory layout - causing random segmentation faults or crashes on the final linked together program!

The fix for this is obviously to limit the scope of the `#pragma pack` statement to pieces of code that really needs it. Ideally, all data structure defintions that is meant to be shared across projects and modules should be refactored into a common header file. This way, the packing definition won't live in random cpp/header files that increases the likelihood of a mistake like this.

For details of `pragma pack` compiler directives, see [GNU compiler documentation on pragma packing][1]


### Final Thoughts

- Unlke rust, C++ design philosophy is less restrictive and pedantic about things you can do or cannot do. While this enables clever programmers to do some amazing tricks. The freedom also lends itself to shoot one's foot unintentionally.
- When working in a team environment, we should really strive to improve the code clarity and follow consistent patterns and idioms of the language to minimize cognitive load in code reviews.
- These gotchas that arises as part of in-depth debugging should be captured and archived in the team's wiki or other knowledge archiving systems to prevent them from being repeated in the future.



[1]:https://gcc.gnu.org/onlinedocs/gcc-4.4.4/gcc/Structure_002dPacking-Pragmas.html
[2]:https://stackoverflow.com/questions/3318410/pragma-pack-effect