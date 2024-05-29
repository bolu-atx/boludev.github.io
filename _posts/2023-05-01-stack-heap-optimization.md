---
layout: post
title:  "Stack optimization for small sized objects in modern C++"
date:   2023-05-01 15:06:06 -0700
tags: cpp programming
author: bolu-atx
categories: cpp programming
---


I came across a popular technique for providing a handle for storing small objects in the handle itself and larger ones on the heap. Using modern C++, this can be implemented quite nicely at compile time. Here is a simple example:

```cpp
// max bytes to store on the stack
constexpr int on_stack_max = 20;

template<typename T>
struct Scoped {     // store a T in Scoped
        // ...
    T obj;
};

template<typename T>
struct OnHeap {    // store a T on the free store
        // ...
        T* objp;
};

template<typename T>
using Handle = typename std::conditional<(sizeof(T) <= on_stack_max),
                    Scoped<T>,      // first alternative
                    OnHeap<T>      // second alternative
               >::type;

void f()
{
    Handle<double> v1;                   // the double goes on the stack
    Handle<std::array<double, 200>> v2;  // the array goes on the free store
}
```


Let's break this down

- `constexpr int on_stack_max = 20;`: This line defines a constant expression for the maximum number of bytes that can be stored on the stack.
- `template<typename T> struct Scoped { T obj; };`: This is a template struct that can store an object of any type T on the stack.
- `template<typename T> struct OnHeap { T* objp; };`: This is a template struct that can store a pointer to an object of any type T on the heap.
- `template<typename T> using Handle = typename std::conditional<(sizeof(T) <= on_stack_max), Scoped<T>, OnHeap<T>>::type;`: This line defines a template alias Handle that uses `std::conditional` to decide whether to use `Scoped<T>` or `On_heap<T>`. If the size of `T` is less than or equal to `on_stack_max`, it uses `Scoped<T>`. Otherwise, it uses `On_heap<T>`.
- `void f() { Handle<double> v1; Handle<std::array<double, 200>> v2; }`: This function demonstrates how to use the Handle template. `v1` is a Handle that stores a double on the stack, because the size of a double is less than `on_stack_max`. `v2` is a Handle that stores an `std::array<double, 200>` on the heap, because the size of `std::array<double, 200>` is greater than `on_stack_max`.

Of course, this assumes that `T` can be copied and moved around, and that it has a finite size. If `T` is not copyable or movable, you will need to adjust the implementation accordingly.

This shows how powerful modern C++ can be in terms of compile-time programming. It allows you to make decisions at compile time based on the properties of types, which can lead to more efficient and flexible code.