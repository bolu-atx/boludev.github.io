---
layout: post
title:  "Achieving Rust-like enums in C++ via Recursive Structs Definition"
date:   2021-07-10 8:06:06 -0700
tags: cpp programming
author: bolu-atx
categories: cpp programming
---

While browsing the excellent modern C++ based console GUI library [FTXUI][1], I noticed this piece of clever code.

```cpp
// event.hpp
struct Event {
  // --- Constructor section ---------------------------------------------------
  static Event Character(char);
  static Event Character(wchar_t);
  static Event Character(std::string);
  static Event Special(std::string);
  static Event Mouse(std::string, Mouse mouse);
  static Event CursorReporting(std::string, int x, int y);

  // --- Arrow ---
  static const Event ArrowLeft;
  static const Event ArrowRight;
  static const Event ArrowUp;
  static const Event ArrowDown;
  // .... Other definitions etc....
```
My immediate reaction to this is that this feels *weird*. If `Event` is instantiated, then it will contain all these static `Event` members.., and those members will contain more children members, how is this not causing a stack overflow? 

<img src="/assets/posts-media/matryoshika-doll.jpg" width="70%" />

that enables modern C++ programs to have expressive of Rust [enums][2]:

<!--more-->
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

// --- Arrow ---
const Event Event::ArrowLeft = Event::Special("\x1B[D");
```



[1]: https://github.com/ArthurSonzogni/FTXUI/blob/master/include/ftxui/component/event.hpp#L25
[2]: https://doc.rust-lang.org/rust-by-example/custom_types/enum.html