---
layout: post
title:  "Passing by const reference"
date:   2020-08-21 15:06:06 -0700
tags: blog
author: bolu-atx
categories: programming cpp
---

While working in any large C++ project, we often deal with having to write small utility functions that takes in some temporary and then perform some operation on it to return a transformed variable. For example

```cpp
std::string append_path(const std::string& basepath, const std::string& child_path)
{
    return basepath + "/" + child_path;
}

// Invoking this function:
const std::string basepath = "/var/tmp";
const std::string text_file = "some_file.txt";
const std::string new_path = append_path(basepath, text_file); // this works
const std::string other_new_path = append_path(basepath, "some_other_file.txt"); // this also works
```

Does this seems strange to you? We are requiring the variable to be passed in by reference. The `"some_other_file.txt"` argument in the 2nd invocation of the argument is a "r-value", and we are able to refer to the content of this r-value string as a reference to some variable.

It turned out, as Herb Sutter [explained it here](https://herbsutter.com/2008/01/01/gotw-88-a-candidate-for-the-most-important-const/):

> The C++ language says that a local const reference prolongs the lifetime of temporary values until the end of the containing scope, but saving you the cost of a copy-construction (i.e. if you were to use an local variable instead). 

So, effectively, the r-value life-time is extended to the function scope when it is being invoked as an argument to a function immediately after its definition.

Now I can rest easy, knowing that the behavior of my program won't depend on how aggressive the compilers optimize or reuse the memory of variables that are no longer considered "needed" by scoping rules.