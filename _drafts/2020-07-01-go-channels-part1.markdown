---
layout: post
title:  "Go channels in Cpp, part 1"
date:   2020-06-25 15:06:06 -0700
tags: cpp multithreading
author: bolu-atx
categories: programming
---


Go channels is the de-factor synchronization mehcanisms in Go. They are the pipes that connect concurrent goroutines.
You can send values into channels from one goroutine and receive those values into another goroutine.
Having channels have made writing multi-threaded concurrent programs really simple in Go. 
In this series, I wanted to see if it's possible to re-create it in cpp.

### Introduction to Go Channels

Let's look at the most basic version of a Go channel usage from this [gobyexample article](https://gobyexample.com/channels).
```go
package main

import "fmt"

func main() {

    messages := make(chan string)

    go func() { messages <- "ping" }()

    msg := <-messages
    fmt.Println(msg)
}
```

In this example, we first create a channel, then kick off a separate thread to send the message "ping" into the channel, and then receives that message in the main thread.

- Channels have a type, in this case, string
- Channels are used in concurrent multithreaded scenarios, as indicated by the asynchronous goroutine 
- Channels have operators similar to streams in c++, where we can "push" and "pull"
- Channels by default have blocking reads - otherwise, the `msg := <- messages` would be executed right away before go-routine spawned in the line above had a chance to finish
- By default, channels in go can contain any number of elements

Here's a more complicated example to show multiple items and blocking of Go channels

```go
package main

import "fmt"

func main() {

    queue := make(chan string, 2)
    queue <- "one"
    queue <- "two"
    close(queue)

    for elem := range queue {
        fmt.Println(elem)
    }
}
```

- In this example, we made a channel with a fixed size of 2
- We also called `close` on the channel, otherwise, the `for` loop in the main thread receiving the channel messages will loop over the existing results, and then block indefinitely waiting for the 3rd item (which will never come).

### Implementing Channels in Cpp

Now, with that introduction, let's see if we can build a Go channel in Cpp. I am using c++11 standard for this exercise.

#### Defining the C++ interface

First, let's define a skeleton structure of our Cpp channel:

```cpp
//
// Created by Bo Lu on 6/28/20.
//
#pragma once

template<class T>
class Channel {
public:
    Channel() {};
    virtual ~Channel() {};

protected:
    Channel& operator=(const Channel& other ) = delete;
    Channel(const Channel& other) = delete;

public:
    T receive_blocking();
    bool receive_async(T& val);
    void send(T&& val);
    void close();
    bool is_closed() const;
};
```

- We have a template class here with type parameter `T` to denote the type of data going into our channel
- We also disabled copy constructor and assignment operator to ensure that channels are not copied by accident
- The main methods to implement are:
    - `receive_blocking` - which blocks until a message can be received
    - `send` - which is called by the "senders" to push data into the channel
    - I also added `close()` and `is_closed()` methods to close the channel / check if the channel is closed.
    - Also note that the `send()` method takes a r-value instead of a reference. This is to ensure that things that get shoved into the channel are no longer accessible (similar to Rust ownership rules)

### Setting up a basic test first

To verify that the Channel class is working as expected, we setup a little test program below. Here, I use the `std::async` class provided in C++11 to launch a lambda function on a separate thread. This lambda captures the channel `chan` by reference. 
After launching the async thread, we then call `receive_blocking()` to try to obtain a message. The `std::cout` prints are used as marker messages to illustrate the timing of two threads.

```cpp
#include <iostream>
#include <string>
#include <future>

#include "Channel.h"

int main() {
    std::cout << "Channel created.\n";
    Channel<std::string> chan;

    auto future = std::async(std::launch::async,
            [&chan](){
        std::cout << "Async about to send ping\n";
        chan.send("ping");
        std::cout << "Async send done\n";
    });

    std::cout << "Main thread about to call receive on channel:\n";
    auto val = chan.receive_blocking();
    std::cout << "Got:" << val << std::endl;

    future.get();
    return 0;
}
```

With this test program ready, we are now ready to work on our `Channel.h`. Let's build it up step by step.

### Single element channel with synchronization

Synchronization mechanisms of channels can be implemented using classic mutex and condition variables. A mutex is a mutual exclusion mechanism provided by hardware that ensures only one thread can access a block of code at any given time. Condition variable, as the name indicates, is a signaling mechanism to allow threads to obain said mutex based on some condition. The implementation of a very very trivial channel (that only allows for one message at a time) is below:

```cpp
template<class T>
class Channel {
public:
    Channel() {};
    virtual ~Channel() {};

protected:
    Channel& operator=(const Channel& other ) = delete;
    Channel(const Channel& other) = delete;

public:
    T receive_blocking()
    {
        std::unique_lock<std::mutex> the_lock(m_mutex);

        m_value_update.wait(the_lock, [this]
            {
            return m_has_value;
        });

        return m_val;
    };
    void send(T&& val)
    {
        {
            std::unique_lock<std::mutex> the_lock(m_mutex);
            m_val = val;
            m_has_value = true;
        }
        m_value_update.notify_all();
    };

    void close();

protected:
    T m_val;
    bool m_has_value {false};

    std::mutex m_mutex;
    std::condition_variable m_value_update;
};
```

In the above code, when a thread tries to either `send` or `receive` on a message, we will first need to obain the `mutex`. For the receiver, then we need to check if `m_has_value` boolean flag is true in the `m_value_update.wait()` method. This condition variable clause will let go of the mutex as long as the predicate (the second argument, a function) is returning false. 

Running the main test program with this implementation gives us the following outputs:
```
Channel created.
Main thread about to call receive on channel:
Async about to send ping
Async send done
Got:ping

Process finished with exit code 0
```

However, this Channel implementation is buggy, since it only allows for a single send/receive. If we want to expand this to allow for multiple send/receives, we will need to flesh out the logic a little more with another condition variable in the sender:

```cpp
    T receive_blocking()
    {
        std::unique_lock<std::mutex> the_lock(m_mutex);

        m_value_update.wait(the_lock, [this]
            {
                return m_has_value;
            });

        m_has_value = false;
        return m_val;
    };
    void send(T&& val)
    {
        {
            std::unique_lock<std::mutex> the_lock(m_mutex);
            m_value_update.wait(the_lock, [this]
            {
                return !m_has_value;
            });
            m_val = val;
            m_has_value = true;
        }
        m_value_update.notify_all();
    };
```

The condition variable in the `send` function will wait if the receiver has not yet removed the previously stored value.