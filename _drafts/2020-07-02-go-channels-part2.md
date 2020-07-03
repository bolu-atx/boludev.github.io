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
From [part 1]({% post_url 2020-06-28-go-channels-part1 %}), we know that if a sender/receiver is not paired together, the channel send/receive operations will never take place. As a result, if we run the following code, Go's deadlock detector will detect a panic and crash immediately.

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


 To make this code work, we need to make this a **buffered** channel. Buffered channel have asynchronous send, and therefore can be executed without having a listener on the other side. To make a buffered channel, we simply specify the channel capacity as the 2nd argument when constructing the channel.

```go
    queue := make(chan string, 2)
```

With this fix, we see the correct behavior
```
▶ go run deadlock_1thread.go
one
two
```

- In this example, we made a channel with a fixed size of 2
- We also called `close` on the channel, otherwise, the `for` loop in the main thread receiving the channel messages will loop over the existing results, and then block indefinitely waiting for the 3rd item (which will never come).


### C++ Implementation

Starting from the single element channel in our [part 1]({% post_url 2020-06-28-go-channels-part1 %}) of this series,  we can add more machinery to support multiple values by storing the messages in a queue via `std::deque<T>`:

we replace the `m_val` and `m_has_value` variables with a single data structure `m_data` of type `std::deque<T>`.

```cpp
protected:
    std::deque<T> m_data;
    std::mutex m_mutex;
    std::condition_variable m_cv;
```

Turned out, with this change, our send/receive logic also simplifies quite a bit - since we no longer need to use a condition variable to check to ensure there is a spot available in the channel to avoid overwriting a previously un-seen message. Also note, we added a function `empty()` to return whether there is any data in the queue.

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

We got the desired behavior - the messages came in order (ping first, pong second), in addition, if you pay attention, you will notice that the 2nd message was sent right away without waiting for the first message to be withdraw. Now, let's finish the rest of the logic for completeness:

```cpp
//
// Created by Bo Lu on 6/28/20.
//
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

Lastly, we need to add a clean-up clause in the destructor:

```cpp
    virtual ~Channel() {
        if (is_open())
            close();
    };
```
