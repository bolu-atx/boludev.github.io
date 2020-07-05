---
layout: post
title:  "Go channels in Cpp, part 1"
date:   2020-06-28 12:06:06 -0700
tags: cpp multithreading
author: bolu-atx
categories: programming
---


Go channels is the de-facto synchronization mechanism in Go. They are the pipes that connect concurrent go routines.
You can send values into channels from one goroutine and receive those values into another goroutine.
Having channels have made writing multi-threaded concurrent programs really simple in Go. 
In this series, I wanted to see if it's possible to re-create it in cpp.

<!--more-->

Before I start, I wanted to just mention there are already plenty of amazing cpp libraries out there that recreates Go channels, such as:

- [ahorn/cpp-channel](https://github.com/ahorn/cpp-channel)
- [Balnian/ChannelsCPP](https://github.com/Balnian/ChannelsCPP)

My write-up is not meant to recreate these libraries, but to dissect the fundamental building blocks of Go channel and examine how they can be re-created in C++.


## Introduction to Go Channels

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
- Channels are used in concurrent multi-threaded scenarios, as indicated by the asynchronous goroutine 
- Channels have operators similar to streams in c++, where we can "push" and "pull"
- Channels by default have blocking send/receive - otherwise, the `msg := <- messages` would be executed right away before go-routine spawned in the line above had a chance to finish
- By default, channels do not hold memory and only allow for one thing to be sent/received

## Implementing Channels in Cpp

Now, with that introduction, let's see if we can build a Go channel in Cpp. I am using c++11 standard for this exercise.

### Defining the C++ interface

First, let's define a basic interface for our cpp `Channel<T>`:

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

Synchronization mechanisms of channels can be implemented using mutex and condition variables. A mutex is a mutual exclusion mechanism provided by hardware that ensures only one thread can access a block of code at any given time. Condition variable, as the name indicates, is a signaling mechanism to allow threads to obtain said mutex based on some condition. The implementation of a very very trivial channel (that only allows for one message at a time) is below:

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

        m_cv.wait(the_lock, [this]
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
        m_cv.notify_all();
    };

    void close();

protected:
    T m_val;
    bool m_has_value {false};

    std::mutex m_mutex;
    std::condition_variable m_cv;
};
```

In the above code, when a thread tries to either `send` or `receive` on a message, we will first need to obtain the `mutex`. For the receiver, then we need to check if `m_has_value` boolean flag is true in the `m_cv.wait()` method. This condition variable clause will let go of the mutex as long as the predicate (the second argument, a function) is returning false. 

Running the main test program with this implementation gives us the following outputs:
```
Channel created.
Main thread about to call receive on channel:
Async about to send ping
Async send done
Got:ping

Process finished with exit code 0
```

This looks exactly like what we expected - main thread kicks off an concurrent thread to execute, and then listens on the channel, when the task thread sends a message, we then receive it on the main thread. *However, this Channel implementation is buggy, since it only allows for a single send/receive* - if we try to send and receive again, we will get the previous value. To expand this to allow for multiple send/receives, we will need to flesh out the logic a little more, and also add another `wait` step in the sender:

```cpp
    T receive_blocking()
    {
        std::unique_lock<std::mutex> the_lock(m_mutex);

        m_cv.wait(the_lock, [this]
            {
                return m_has_value;
            });

        m_has_value = false;
        my_cv.notify_all();
        return m_val;
    };
    void send(T&& val)
    {
        {
            std::unique_lock<std::mutex> the_lock(m_mutex);
            m_cv.wait(the_lock, [this]
            {
                return !m_has_value;
            });
            m_val = val;
            m_has_value = true;
        }
        m_cv.notify_all();
    };
```
In this updated implementation, we add another condition variable on the sender side to ensure that the current channel does not contain a value before overwriting the `m_val`. 

To test this implementation, the test program needs to be updated to send and receive twice:

```cpp
int main() {
    std::cout << "Channel created.\n";
    Channel<std::string> chan;

    auto future = std::async(std::launch::async,
            [&chan](){
        std::cout << "Async about to send ping\n";
        chan.send("ping");
        std::cout << "Async ping sent, sending pong next\n";
        chan.send("pong");
        std::cout << "Async pong sent\n";
    });

    std::cout << "Main thread about to call receive on channel:\n";
    auto val = chan.receive_blocking();
    std::cout << "Got:" << val << std::endl;

    std::cout << "Main thread about to call receive on channel:\n";
    val = chan.receive_blocking();
    std::cout << "Got:" << val << std::endl;
    future.get();
    return 0;
}
```

If our logic worked correctly, the second message "pong" can only be sent after the first message "ping" has been received.

Indeed, this is what we see:
```
Channel created.
Main thread about to call receive on channel:
Async about to send ping
Async ping sent, sending pong next
Got:ping
Async pong sent

Main thread about to call receive on channel:
Got:pong

Process finished with exit code 0
```

However, this implementation, while correct in behavior, does not fully mimic Go's definition of a channel. In Go, both the send and receive are blocking operations - which means, if a thread is sending data into the channel, it will "block" at the send operation until there's is another thread that is ready to receive on the other end. To illustrate this point, here's a Go program where we delay the receive operation by 2 seconds after launching the thread to send the "ping".

```go
package main
import (
  "fmt"
  "time"
)
func elapsed(what string) func() {
    start := time.Now()
    return func() {
        fmt.Printf("%s took %v\n", what, time.Since(start))
    }
}
func main() {

  messages := make(chan string)

  go func() {
    defer elapsed("send")()
    fmt.Println("thread: about to ping")
    messages <- "thread: ping"
    fmt.Println("thread: ping done")
  }()

  {
    defer elapsed("receive")()
    time.Sleep(2 * time.Second)
    fmt.Println("main: about to receive")
    msg := <-messages
    fmt.Println("main: receive done")
    fmt.Println("got: " + msg)
  }
  time.Sleep(10 * time.Millisecond)
}
```
The `defer elapsed(label)()` in this program is an utility function that reports the time took. The output of this program is:
```
about to ping
main: about to receive
main: receive done
got: ping
ping done

send took 2.0010819s
receive took 2.0116594s
```

Note that the send operation took just as long as the receive operation, even though the "send" thread was launched without any delays.

Modifying our test program with a simple timer function to report out the timing in our cpp implementation:
```cpp
#define THREADSAFE(MESSAGE) \
        ( static_cast<std::ostringstream&>(std::ostringstream().flush() << MESSAGE).str())

struct timer {
    timer(const std::string& label)
    {
        m_label = label;
        m_start = std::chrono::high_resolution_clock::now();
    }
    ~timer()
    {
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::seconds>( end - m_start ).count();
        std::cout << THREADSAFE(m_label << " took " << duration << " s.\n");
    }

    std::chrono::time_point<std::chrono::steady_clock> m_start;
    std::string m_label;
};
```

 we'll get the following output:
```
Channel created.
Async about to send ping
send1 took 0 s.
Async ping sent, sending pong next
Async pong sent
Main thread about to call receive on channel:
Got:pong
receive1 took 2 s.
Main thread about to call receive on channel:
Got:pong
```
Note that the first send returned right away and took 0s - this is different from the Go implementation, since it allows for a sender to send something without having a receiver on the other end.

To implement the Go channel synchronization behavior, we not only need to have a flag to track whether we have a value to be received, also another flag to track whether both sender / receiver are on the channel. With these two flags, we also need to update the wait Predicate function to reflect that:

- If the receiver thread is holding the mutex, we will need to have a receiver and have a value set before we proceed to read from the channel internal data member
- If the sender thread has the mutex, the CV will only acquire the lock if we have a receiver, and the channel currently does not have another value in place
- If the receiver thread acquires the mutex, we need to ensure we broadcast via the condition variable that a receiver is available to senders that are waiting

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
        m_has_receiver = true;
        m_cv.notify_all();
        m_cv.wait(the_lock, [this]
        {
            return (m_has_receiver && m_has_value);
        });

        m_has_value = false;
        m_has_receiver = false;
        return std::move(m_val);
    };
    void send(T&& val)
    {
        std::unique_lock<std::mutex> the_lock(m_mutex);
        m_cv.wait(the_lock, [this]
        {
            return (m_has_receiver && !m_has_value);
        });
        m_val = val;
        m_has_value = true;
        m_cv.notify_all();
    };

    void close();

protected:
    T m_val;
    bool m_has_value {false};
    bool m_has_receiver {false};

    std::mutex m_mutex;
    std::condition_variable m_cv;
};
```

To verify that this works, we needed to update our test program to add ability to track how long the send/receive operation took, below is the updated test program where we will now report the first "ping"'s send duration and also receive duration.

```cpp
#include <iostream>
#include <string>
#include <future>
#include <chrono>
#include <thread>
#include <sstream>

#include "Channel.h"

#define THREADSAFE(MESSAGE) \
        ( static_cast<std::ostringstream&>(std::ostringstream().flush() << MESSAGE).str())

struct timer {
    timer(const std::string& label)
    {
        m_label = label;
        m_start = std::chrono::high_resolution_clock::now();
    }
    ~timer()
    {
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::seconds>( end - m_start ).count();
        std::cout << THREADSAFE(m_label << " took " << duration << " s.\n");
    }

    std::chrono::time_point<std::chrono::steady_clock> m_start;
    std::string m_label;
};

int main() {
    using namespace std::chrono_literals;

    std::cout << "Channel created.\n";
    Channel<std::string> chan;

    auto future = std::async(std::launch::async,
            [&chan](){
                {
                    auto t = timer("send1");
                    std::cout << "Async about to send ping\n";
                    chan.send("ping");
                }
        std::cout << "Async ping sent, sending pong next\n";
        chan.send("pong");
        std::cout << "Async pong sent\n";
    });

    // we only care about the first send for this exercise
    {
        auto t2 = timer("receive1");
        std::this_thread::sleep_for(2s);
        std::cout << "Main thread about to call receive on channel:\n";
        auto val = chan.receive_blocking();
        std::cout << THREADSAFE("Got:" << val << std::endl);
    }

    std::cout << "Main thread about to call receive on channel:\n";
    auto val = chan.receive_blocking();
    std::cout << THREADSAFE("Got:" << val << std::endl);

    future.get();
    return 0;
}
```


Running this code yields the following output:
```
Channel created.
Async about to send ping
Main thread about to call receive on channel:
Got:ping
send1 took 2 s.
Async ping sent, sending pong next
receive1 took 2 s.
Main thread about to call receive on channel:
Async pong sent
Got:pong
```

Just as we expected, with these changes, the updated program now behaves fully like a Go channel now.

## Summary
Now, we have a basic Channel that can be used for mutli-threaded synchronization in cpp:

- We gradually built up the synchronization, and then introduced additional components
- Condition variables and mutex used together implements the synchronization machinery behind the scene in our channel
- Through the use of `r-value` references and `std::move`, we ensure that our channel does not copy by value and is extremely performant.
 We also enforce "ownership" of the data to be single owner in our implementation, thereby suppressing data races and other multi-threading bugs.

This concludes the part 1 of my Go channel series. In the next part, we will explore how to make a buffered channel that support range for loops, predefined sizes, and async operations

## Source Code

All source code for this write-up is available on my Github @ [bolu-atx/go-channels-in-cpp](https://github.com/bolu-atx/go-channels-in-cpp)