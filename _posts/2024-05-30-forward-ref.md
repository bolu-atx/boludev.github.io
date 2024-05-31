---
layout: post
title:  "`std::ref` and `std::reference_wrapper` in C++"
date:   2024-05-30 15:06:06 -0700
tags: cpp template
author: bolu-atx
categories: programming
---
In refactoring legacy C++ codebases we often have to deal with a lot of functions or class methods that takes a pointer as an argument and then does a bunch of null checks. This is a common pattern in C++ codebases that are not modernized yet.

Modern C++ has introduced a few utilities to help with this pattern. One of them is `std::ref` and `std::reference_wrapper`. In this post, I wanted to talk about these tools and how they can improve the safety and readability of modern C++ code.


## Introduction to `std::reference_wrapper` and `std::ref`

`std::reference_wrapper<T>` is a class template that wraps a reference in a copyable, assignable object. It is frequently used in conjunction with `std::ref` to pass references to functions that take arguments by value. It simulates `&T` and improves null safety by allowing modern C++ code to skip using pointers.

`std::ref` is a function template that returns a `std::reference_wrapper<T>` object. It is used to pass references to functions that take arguments by value. It is a simple wrapper around `std::reference_wrapper<T>` that allows for more concise code. The const analog of `std::ref` is `std::cref`, which does similar things but returns a `std::reference_wrapper<const T>` object.

Let's look at an example to see why they are needed:

```cpp
template<typename T>
void increment(T n) {
    n++;
}


int main() {
    int n = 0;
    increment(n);
    std::cout << n << std::endl; // prints 0
    return 0;
}
```

It is no surprise that this code will print `0` because `n` is passed by value to `increment` function. Now, let's try to give it a reference:

```cpp
template<typename T>
void increment(T n) {
    n++;
}


int main()
{
    int n = 0;
    int& ref = n;
    increment(ref);
    std::cout << n << std::endl;
    return 0;
}
```

What do we get at the end here? Surprisingly we still get `0`. This is because although `ref` is a reference, it is passed by value to `increment` function since `increment` takes `T` by value. You will see the same behavior even if we pass in `&n` to `increment`.

This is where `std::ref` and `std::reference_wrapper` comes in. By wrapping `n` with `std::ref`, we can pass `n` by reference to `increment` function:

```cpp

template<typename T>
void increment(T n) {
    n++;
}

int main()
{
    int n = 0;
    auto ref = std::ref(n);
    increment(ref);
    std::cout << n << std::endl; // prints 1
    return 0;
}

```

As expected, this will print 1. The `ref` is a `std::reference_wrapper<int>` object that wraps `n` and allows us to pass `n` by reference to `increment` function. You can think of `std::reference_wrapper` as a pointer that is guaranteed to be non-null. the type `T` becomes `int&` in this case. inside `increment` function, and everything works as expected.

## Real World Use Cases

### Make a container of reference types

`std::reference_wrapper` is useful when you want to make a container of reference types. For example, you can make a vector of references to integers:

```cpp
std::vector<int> v = {1, 2, 3, 4, 5};
std::vector<std::reference_wrapper<int>> v_ref(v.begin(), v.end());

for (auto& i : v_ref) {
    i++;
}

for (auto i : v) {
    std::cout << i << " ";
}
// prints 2 3 4 5 6
```


### Packaging arguments in various queues or other containers to functions that take by reference

`std::reference_wrapper` is also useful when you want to package arguments in various queues or other containers to functions that take by reference. For example, you can use `std::reference_wrapper` to pass arguments to a function that takes by reference:

```cpp
void foo(int& n) {
    n++;
}

int main() {
    int n = 0;
    std::queue<std::reference_wrapper<int>> q;
    q.push(n);
    foo(q.front());
    std::cout << n << std::endl; // prints 1
    return 0;
}
```

This is particularly useful when combined with `std::make_tuple` or `std::tie` to pass multiple arguments to a function that takes by reference.


Example:

```cpp
void foo(int& a, int& b) {
    a++;
    b++;
}

int main() {
    int a = 0;
    int b = 0;
    auto t = std::make_tuple(std::ref(a), std::ref(b));
    // forward tuple as args
    std::apply(foo, t);
    std::cout << a << " " << b << std::endl; // prints 1 1
    return 0;
}

```

## Conclusion

`std::reference_wrapper` and `std::ref` are useful tools in modern C++ to pass references to functions that take arguments by value. They are particularly useful when you want to make a container of reference types or package arguments in various queues or other containers to functions that take by reference. They are a great way to improve the safety and readability of modern C++ code.