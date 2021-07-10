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

### How is this  `Event` struct used?

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


### How do static members in structs/classes work?

Another puzzling piece in this `Event` struct is the recursive static members in the defintion (i.e. the `static const` Event ArrowLeft is of type `Event`, which is the parent type). To explore why we can define structs that contain static members of themselves, let's create a toy C++ program:

```cpp
#include <iostream>

struct SomeStruct {
    SomeStruct nested;
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
```
The program is prety simple, we define a struct `SomeStruct` and then tries to print its `id` and the memory address pointer. However, the above example does not actually compile,  it produces the following error:

```
     SomeStruct nested;
                ^~~~~~
main.cpp:3:8: note: definition of ‘struct SomeStruct’ is not complete until the closing brace
 struct SomeStruct {
        ^~~~~~~~~~
```

To make this program compile, we have to define the `nested` member as static.

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

`static` keyword when used in conjunction with a data member basically "forward" declares the member variable of certain type - it does not instantiate that variable. As a result, this modified version of the toy example compiles fine, since we did not initialize the `nested` variable anywhere and did not make reference of it in the main program. If we change the main function slightly to reference the nested member, we will get a linker error saying that the symbol is undefined.

```cpp
int main()
{
    SomeStruct a;
    a.printID();

    // Now print the ID of the nested static struct
    SomeStruct::nested.printID();
    return 0;
}

// Linker error:
// /tmp/cc4m112m.o: In function `main':
// main.cpp:(.text+0x21): undefined reference to `SomeStruct::nested'
// collect2: error: ld returned 1 exit status
```

How do we define this static symbol?  We can try to initialize it at declaration:

```cpp
struct SomeStruct {
    static SomeStruct nested = SomeStruct();
    int id {0};
    
    SomeStruct() {};
    SomeStruct(int id) : id(id) { };
    
    void printID() {
        std::cout << "ID: " << id << ", addr: " << this << std::endl;
    }
};

// Compiler error:
// main.cpp:12:43: error: invalid use of incomplete type ‘struct SomeStruct’
//      static SomeStruct nested = SomeStruct();
//                                            ^
// main.cpp:11:8: note: definition of ‘struct SomeStruct’ is not complete until the closing brace
//  struct SomeStruct {
//         ^~~~~~~~~~
// main.cpp:12:23: error: in-class initialization of static data member ‘SomeStruct SomeStruct::nested’ of incomplete type
//      static SomeStruct nested = SomeStruct();
//                        ^~~~~~
// main.cpp:12:23: error: ‘SomeStruct SomeStruct::nested’ has incomplete type
```

Yikes, the compiler does not like it, I won't go into why here, but you are welcome to take a look at [this page][5]. The proper way to initialize a static member variable is to initialize it explicitly outside of the class definition like so:

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

This now works as expected - notice that the nested static struct is pointing at a different segment of the program memory (0x601194 instead of 0x7fffa). This is because variables declared as static either goes into the .BSS (block started by symbol) or the .DATA section of the compiled binary. The [wikipedia entry][6] explains it better.

So far, everything's pretty vanilla. We declared static members a class/struct, and we defined it outside of the class definition, and we accessed it via the scope accessor `::` to refer to it in the program.
Where does the recrusive part come in? Well, it turned out, static variables can also be referred to via the `.` operator on any instantiated instances of the class/struct. So this makes `a.nested` equivalent to `SomeStruct::nested` in the example code above. As a result, the following is actually valid and compiles:

```cpp
int main()
{
    SomeStruct a;
    a.printID();
    SomeStruct::nested.printID();
    a.nested.printID();
    a.nested.nested.printID();
    return 0;
}

// Outputs:
// ID: 0, addr: 0x7ffc89acde4c
// ID: 1, addr: 0x601194
// ID: 1, addr: 0x601194
// ID: 1, addr: 0x601194
```

As we can see from the outputs of the above toy program, doesn't matter how many levels you nest, it all refers to the same underlying member variable in memory. Conceptually this is similar to a linked-list where the `next` node points to the node itself.

The next question we can ask is: how does the addition of the static member change the memory layout? below is another toy program to try to answer this question - we set the structured packing to 1 to prevent the compiler from byte-aligning the structs in memory.

```cpp
#pragma pack(1)
struct SomeStruct {
    int id {0};
    SomeStruct() {};
    SomeStruct(int id) : id(id) {};
};

struct SomeNestedStruct {
    static SomeNestedStruct nested;
    int id {0};
    SomeNestedStruct() {};
    SomeNestedStruct(int id) : id(id) { };
};

SomeNestedStruct SomeNestedStruct::nested = SomeNestedStruct(1);

int main()
{
    SomeStruct a;
    SomeNestedStruct b;
    
    std::cout << "Struct size is: " << sizeof(SomeStruct) << "\n";
    std::cout << "Nested struct size is: " << sizeof(SomeNestedStruct) << "\n";
    std::cout << "Nested struct instance size is: " << sizeof(SomeNestedStruct::nested) << "\n";
    std::cout << "a size is: " << sizeof(SomeStruct) << "\n";
    std::cout << "b size is: " << sizeof(SomeNestedStruct) << "\n";
    return 0;
}

// Outputs:
// Struct size is: 4
// Nested struct size is: 4
// Nested struct instance size is: 4
// a size is: 4
// b size is: 4
```

As we can see, the size of the struct with and without the nested variable is identical and equal to the size of the variable `id` (4 bytes due to the `int` being 32-bit). The availability of static members do not affect the object size - as a result, we can define as many of these as we like without worrying about introducing memory inefficiencies. A [detailed stack overflow thread][7] goes into why this is the case in detail.


### Implementing Rust Enum-Like Behavior in C++

A very very common pattern in Rust is the use of `enum` with some `match` selector to exhaustive handle all possible scenarios without the use of `if/else` imperative style programming. A simple example of such a pattern is shown below, where we have a method that prints the IP address:

```rust
enum IpAddr {
    V4(String),
    V6(String),
}

fn print_ip(ip: IpAddr) {
    match ip {
        IpAddr::V4(v4addr) => println!("Got v4 {}", v4addr),
        IpAddr::V6(v6addr) => println!("Got v6 {}", v6addr),
    }
}

fn main() {
    println!("Hello, world!");

    let home = IpAddr::V4(String::from("127.0.0.1"));
    print_ip(home);
    print_ip(IpAddr::V6(String::from(
        "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
    )));
}
```

Using the struct pattern above, we can do the same in C++:

```cpp
#include <iostream>

enum IpType {
    V4 = 0,
    V6
};

struct IpAddr {
    IpType type;
    std::string address;
    
    static IpAddr fromV4(const std::string& addr) {
        IpAddr ip;
        ip.type = V4;
        ip.address = addr;
        return ip;
    }
    
    static IpAddr fromV6(const std::string& addr) {
        IpAddr ip;
        ip.type = V6;
        ip.address = addr;
        return ip;
    }
};

void print_addr(const IpAddr& ip)
{
    switch (ip.type)
    {
        case V4:
            std::cout << "Got v4: " << ip.address << "\n";
        break;
        case V6:
            std::cout << "Got v6: " << ip.address << "\n";
            break;
        default:
            throw std::runtime_error("Not impelemented");
    }
}

int main()
{
    auto v4_addr = IpAddr::fromV4("127.0.0.1");
    auto v6_addr = IpAddr::fromV6("2001:0db8:85a3:0000:0000:8a2e:0370:7334");
    
    print_addr(v4_addr);
    print_addr(v6_addr);
    
    return 0;
}
```

As we can see, the C++ implementation is much more verbose - but it gets the job done. However, if we forget to handle a case, we will not get a compiler warning, but a run-time error.

Note, turned out, someone also had this question on [Stack Overflow][8], there are some really nice implementation.

### Summary

The `Event` struct pattern serves a few functional purposes in this codebase without using an OOP based-approach:

- As collection of static methods to construct different types of Events
- Defines a container of POD types that form an user input event with custom comaprison operators
- Defines a set of `static const` events that are "enum-like" to be used in dispatch methods or condition tests to implement run-time polymorphism.

In addition, we explored why the recursive member variable definition works due to how `static` variables are initialized / defined in C++. The static variables, although accessible through the struct name scope or through instantiated copies of the struct, is actually located in a different memory segment in the compiled/linked executable. As a result, we do not pay a memory penalty when defininig multiple static variables in the struct declaration.

We then explored how to impelement rust-like `enum` using structs in C++. It can serve as a nice wrapper for light/small data types without resorting to a OOP like pattern.


[1]: https://github.com/ArthurSonzogni/FTXUI/blob/master/include/ftxui/component/event.hpp#L25
[2]: https://doc.rust-lang.org/rust-by-example/custom_types/enum.html
[3]: https://doc.rust-lang.org/book/ch18-03-pattern-syntax.html
[4]: https://github.com/ArthurSonzogni/FTXUI/blob/82adc3b4109a13fdbdff89aeb5808faa625b80eb/src/ftxui/component/screen_interactive.cpp#L393
[5]: https://www.learncpp.com/cpp-tutorial/static-member-variables/
[6]: https://en.wikipedia.org/wiki/Executable_and_Linkable_Format
[7]: https://stackoverflow.com/questions/4640989/how-do-static-member-variables-affect-object-size
[8]: https://stackoverflow.com/questions/64017982/c-equivalent-of-rust-enums