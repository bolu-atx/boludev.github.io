---
layout: post
title:  "Rust like enums in C++"
date:   2021-07-10 8:06:06 -0700
tags: cpp programming
author: bolu-atx
categories: cpp programming
---

While browsing the excellent modern C++ reactive console UI library [FTXUI][1], I noticed this piece of code in how the events are typed/handled.

```cpp
// event.hpp
struct Event {
  // --- Constructor section ---------------------------------------------------
  static Event Character(char);
  static Event CursorReporting(std::string, int x, int y);
  // Other constructor methods

  // --- Arrow ---
  static const Event ArrowLeft;
  static const Event ArrowRight;
  static const Event ArrowUp;
  static const Event ArrowDown;
  // .... Other definitions etc....
```

My immediate reaction to this is that this feels *weird* - partially because I am not used to the author's C++ style, in addition, the combination of static member variables sharing the parent-type, and static methods for constructors are really confusing to read.

Let's dive into it to see how things work.

<!--more-->

### Real Use-Case of the `Event` struct type

Figuring how to used in the actual code often helps me contextualize the design decisions went into the code, so let's take a look at how this `Event` class is being used in the library.

In the cpp definition file for the `Event` class, there are several static constructor methods that takes different arguments and returns different Event types.

```cpp
// static
Event Event::Special(std::string input) {
  Event event;
  event.input_ = std::move(input);
  return event;
}

// static
Event Event::CursorReporting(std::string input, int x, int y) {
  Event event;
  event.input_ = std::move(input);
  event.type_ = Type::CursorReporting;
  event.cursor_.x = x;
  event.cursor_.y = y;
  return event;
}
```

This is a pretty common constructor pattern; on my team, we overload the constructor with different argument types which sometimes creates confusion. I actually like this "named" constructor method better, as it makes clear what type of constructor function is being called without needing to rely on deciphering the constructor method call signature to figure out which one is being invoked.

After defininig these methods, the `cpp` definition file for the `Events` then instantiates the defined static member special Event constants as follows:

```cpp
// --- Arrow ---
const Event Event::ArrowLeft = Event::Special("\x1B[D");
// Other instantiating definitions omitted here...
```

Note that, even though the type of `Event::ArrowLeft` is already defined to be of type `Event`, the initialization statement above repeats the type of the variable being initialized. I suspect this is because the cpp file is compiled in its own translation unit which does not have access to the type information at compile time.

The events define equality operators, allowing us to check if the events are of the same type

```cpp
  bool operator==(const Event& other) const { return input_ == other.input_; }
  bool operator!=(const Event& other) const { return !operator==(other); }
```

Then, various UI compnents can then define if they want to handle certain events by checking the type of event:

```cpp
bool ContainerBase::VerticalEvent(Event event) {
  int old_selected = *selector_;
  if (event == Event::ArrowUp || event == Event::Character('k'))
    (*selector_)--;
  if (event == Event::ArrowDown || event == Event::Character('j'))
    (*selector_)++;
  if (event == Event::Tab && children_.size())
    *selector_ = (*selector_ + 1) % children_.size();
  if (event == Event::TabReverse && children_.size())
    *selector_ = (*selector_ + children_.size() - 1) % children_.size();

  *selector_ = std::max(0, std::min(int(children_.size()) - 1, *selector_));
  return old_selected != *selector_;
}
```
In the above context, the event handler definition looks *just like* a Rust `enum` [pattern matching][3]! (Of course, the C++ implementation here does not benefit from the stricter Rust compiler which warns us of unhandled branches in the pattern matching.

#### Static Recursive Structs

To explore why we can define structs that contain static members of themselves, let's create a toy C++ program:

```cpp
#include <iostream>

struct SomeStruct {
    static SomeStruct nested;
    int id {0};

    void printID() {
        std::cout << "ID: " << id << ", addr: " << this << std::endl;
    }
};

int main()
{
    SomeStruct a;
    a.printID();
    return 0;
}

// Outputs:
// ID: 0, addr: 0x7ffc8921899c
```

```cpp
#include <iostream>

struct SomeStruct {
    static SomeStruct nested;
    int id {0};
    
    SomeStruct() {};
    SomeStruct(int id) : id(id) {};
    
    void printID() {
        std::cout << "ID: " << id << ", addr: " << this << std::endl;
    }
};

SomeStruct SomeStruct::nested = SomeStruct(1);

int main()
{
    SomeStruct a;
    a.printID();
    SomeStruct::nested.printID();
    return 0;
}

// Outputs:
// ID: 0, addr: 0x7fffa27d02ec
// ID: 1, addr: 0x601194
```


[1]: https://github.com/ArthurSonzogni/FTXUI/blob/master/include/ftxui/component/event.hpp#L25
[2]: https://doc.rust-lang.org/rust-by-example/custom_types/enum.html
[3]: https://doc.rust-lang.org/book/ch18-03-pattern-syntax.html
[4]: https://github.com/ArthurSonzogni/FTXUI/blob/82adc3b4109a13fdbdff89aeb5808faa625b80eb/src/ftxui/component/screen_interactive.cpp#L393