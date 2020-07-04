---
layout: post
title:  "Go channels in Cpp, part 2"
date:   2020-07-02 7:06:06 -0700
tags: cpp multithreading
author: bolu-atx
categories: programming
---

In this part 2 of the Go channel series, I will expand the `Channel<T>` class we developed to support multiple elements, range for loops and asynchronous operations.

Part one of this series, where we built a simple Go channel with similar synchronization behavior is available [here]({% post_url 2020-06-28-go-channels-part1 %}).

Buffered channels are desirable in many parallel applications such as work queues, worker/thread pools, MCMP (multiple consumers/producers) patterns.

Well designed, large scale complex concurrent systems are often built from a few fairly simple building blocks such as buffered channels. Even though these buffered channels are still constructed the same way in Go, they are actually entirely different in behavior from simple channels, and really behave differently. The objective for buffered channel is less so of synchronization, but more to deal with non-deterministic input/output "flow rate" into a system. As a result, in buffered channels, send/receive operations are non-blocking provided there is capacity in the channel. In addition, they have storage, whereas simple channel is more of a "pass-through" entity.

<img src="/assets/posts-media/go-channel.png" width="500" />

## Buffered Channels

### Go Example - A Buffered Channel
From [part 1]({% post_url 2020-06-28-go-channels-part1 %}), we know that if a sender/receiver is not paired together, the channel send/receive will block indefinitely. As a result, if we run the following code, we should get a deadlock panic.

```go
package main

import "fmt"

func main() {

    queue := make(chan string)
    queue <- "one"
    queue <- "two"
    close(queue)

    for elem := range queue {
        fmt.Println(elem)
    }
}
```

```
▶ go run deadlock_1thread.go
fatal error: all goroutines are asleep - deadlock!

goroutine 1 [chan send]:
main.main()
        /Users/blu/Repos/go-channels-in-cpp/go/deadlock_1thread.go:8 +0x59
exit status 2
```

 To fix this, the blocking behavior on send needs to be changed to non-blocking. **Buffered** channel offers this. When a buffered channel has free capacity, the sends are asynchronous and returns right away, as it does not require an active receiver on the channel.  To make a buffered channel, we provide a second argument of channel capacity when constructing the channel.

```go
    queue := make(chan string, 2)
```

With a buffered channel, the deadlock code no longer panics
```
▶ go run deadlock_1thread.go
one
two
```

Receive on a buffered channel behaves similar to a normal channel. If there are no items in the channel currently, the receive operation will block until something is available.

### C++ Implementation

With that brief introduction, let's return to C++ land to see what changes we need to make to implement similar behaviors.

Starting from the single element channel in our [part 1]({% post_url 2020-06-28-go-channels-part1 %}) of this series,  it is quite simple to support buffered channels by storing the elements in a STL container such as a double-ended queue via `std::deque<T>`:

we replace the `m_val` and `m_has_value` variables with a single data structure `m_data` of type `std::deque<T>`.

```cpp
protected:
    std::deque<T> m_data;
    std::mutex m_mutex;
    std::condition_variable m_cv;
```

Turned out, with this change, our send/receive logic also simplifies quite a bit - since we no longer need to use condition variable and extra flags to ensure that there is a proper sender/receiver pairing. Also note, we added a function `empty()` to return whether there is any data in the queue.

```cpp
T receive_blocking()
{
    std::unique_lock<std::mutex> the_lock(m_mutex);
    m_cv.wait(the_lock, [this]
    {
        return !empty();
    });

    T val = std::move(m_data.front());
    m_data.pop_front();
    return val;
};
void send(T&& val)
{
    std::unique_lock<std::mutex> the_lock(m_mutex);
    m_data.emplace_back(val);
    m_cv.notify_all();
};

bool empty() const {
    return m_data.empty();
}
```


Running this on our test program:

```
Channel created.
Main thread about to call receive on channel:
Async about to send ping
Async ping sent, sending pong next
Async pong sent
Got:ping
Main thread about to call receive on channel:
Got:pong
```

We got the desired behavior - the messages came in order (ping first, pong second), in addition, if you pay attention, you will notice that the 2nd message was sent right away without waiting for the first message to be withdraw. 

To ensure the channel is open at the point of send/receive, we need to add a boolean to track the channel open/closed state.

Currently, our buffered channel work do not have a capacity constraint.

```cpp
#pragma once
#include <mutex>
#include <condition_variable>
#include <deque>

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
            return !is_empty() || !is_open();
        });

        if (!is_open())
            throw std::runtime_error("Channel closed.");

        T val = std::move(m_data.front());
        m_data.pop_front();
        return val;
    };
    void send(T&& val)
    {
        std::unique_lock<std::mutex> the_lock(m_mutex);
        if (is_open())
        {
            m_data.emplace_back(val);
            m_cv.notify_all();
        }
    };

    void close() {
        std::unique_lock<std::mutex> the_lock(m_mutex);
        m_open = false;
    };

protected:
    bool is_open() const {
        return m_open;
    }

    bool is_empty() const {
        return m_data.empty();
    }
protected:
    std::deque<T> m_data;
    std::mutex m_mutex;
    std::condition_variable m_cv;
    bool m_open {true};
};
```
This version of the `Channel<T>` now allows us to `close()` the channel from either the sender or the receiver. If the channel is closed while another thread is waiting via `receive_blocking`, an exception will be thrown.

Lastly, we need to add a clean-up clause in the destructor.

```cpp
    virtual ~Channel() {
        if (is_open())
            close();
    };
```