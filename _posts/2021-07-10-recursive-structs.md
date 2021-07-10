---
layout: post
title:  "Down the recursive struct rabbit-hole"
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
My immediate reaction to this is that this feels *weird*. First, how can a type declaration self-reference itself as a member variable (exception here being pointers to something of the same type, which we see a lot in linked-list implementations)? If `Event` is instantiated, then it will contain all these static `Event` members, and these members will contain childrens of their own... Even if the static variable is on the heap, you still need to store the pointer to its children on the stack, won't this just cause infinite recursion like a set of Russian dolls?
<img src="/assets/posts-media/matryoshika-doll.jpg" width="70%" />

My attempts to trying to find some answers led me down a rabbit hole of static variable lifetimes, recursion, and parallels of this style of C++ code to Rust [enums][2].

<!--more-->

First, let's see how it is being used in the actual FTXUI code.

The events can be constructed using the declared constructor functions which fills in various fields that are appropriate for the event (such as cursor events or keyboard input events).

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
There should be a minor optimization opportunity here to use union types instead of individual POD member variables to save memory foot-print - but the saving is probably small and not worth the effort unless this is being used in some memory critical purpose.

```cpp
// --- Arrow ---
const Event Event::ArrowLeft = Event::Special("\x1B[D");
// Other instantiating definitions omitted here...
```

[1]: https://github.com/ArthurSonzogni/FTXUI/blob/master/include/ftxui/component/event.hpp#L25
[2]: https://doc.rust-lang.org/rust-by-example/custom_types/enum.html