---
layout: post
title:  "Advanced memory allocation techniques in C++"
date:   2024-06-01 15:06:06 -0700
tags: cpp memory
author: bolu-atx
categories: programming
---

Efficient choice of stack / heap / static memory allocation can make a big difference in the performance of your C++ program. In this post, I wanted to talk about some advanced memory allocation techniques in C++ that can help you write faster and more efficient code.
When dealing with multi-threaded applications running on Symmetric Multiprocessing (SMP) systems, it's important to consider how memory is allocated and shared among threads. Here are some techniques to optimize memory management in multi-threaded environments:

1. Thread-local storage: Use thread-local storage (TLS) to allocate memory that is private to each thread. This can reduce contention and improve performance by avoiding synchronization overhead.
2. Lock-free data structures: Implement lock-free data structures such as lock-free queues, stacks, and maps to avoid contention and improve scalability in multi-threaded applications.
3. Memory pools: Use memory pools to pre-allocate and manage memory for frequently used data structures. This can reduce memory fragmentation and improve cache locality.
4. NUMA-aware allocation: Consider Non-Uniform Memory Access (NUMA) architecture when allocating memory in multi-threaded applications. Allocate memory from the local NUMA node to reduce memory access latency.

<!--more-->


### Thread Local Storage

Thread-local memory allocation on Linux can be achieved using several techniques and tools. Here are some key methods and considerations:

1. Thread-Local Storage (TLS)
Thread-local storage (TLS) allows each thread to have its own instance of a variable. This is useful for thread-local memory allocation because it ensures that each thread can manage its own memory without interference from other threads.

    - GCC Extension: Use the `__thread` keyword in C or thread_local in C++11 to declare thread-local variables. These variables are allocated such that there is one instance per thread
    - POSIX API: Use `pthread_getspecific()` and `pthread_setspecific()` to store and retrieve thread-specific data

2. Arena Allocators
Arena allocators manage a large block of memory and allocate smaller chunks from this block. This can be done in a thread-local manner to avoid contention.
Thread-Local Arena: Each thread can have its own arena allocator. This reduces lock contention because each thread manages its own memory block
Implementation: Use a bitset or freelist to manage allocations within the arena. Freeing memory can be more complex and may involve checking ownership and using lockless data structures like linked lists or ring buffers

3. Specialized Allocators
Several specialized allocators are designed to handle thread-local memory allocation efficiently.

    - Jemalloc: A general-purpose allocator that supports thread-specific allocation using shared arenas. It can be tuned for specific use cases and is known for balancing overhead against contention
    - Nedmalloc: A high-performance thread caching allocator that can be built statically or as a DLL. It is designed to reduce contention and improve performance in multi-threaded applications
    - Hoard Allocator: Incorporates techniques to reduce contention and improve scalability in multi-threaded environments

4. System Calls and Kernel Support
On Linux, thread-local storage setup involves system calls and kernel support.

    GDT Entries: The kernel sets up a new Global Descriptor Table (GDT) entry for each thread, which refers to the memory block allocated for TLS. This is done using system calls like set_thread_area() and arch_prctl()

    Memory Segments: Segment registers (FS and GS) are used to point to the TLS area, allowing thread-specific memory access

Example code:

```c
#include <pthread.h>
#include <stdio.h>

__thread int thread_local_var = 0;

void* thread_function(void* arg) {
    thread_local_var = (int)(size_t)arg;
    printf("Thread %d: thread_local_var = %d\n", (int)(size_t)arg, thread_local_var);
    return NULL;
}

int main() {
    pthread_t threads[2];
    pthread_create(&threads[0], NULL, thread_function, (void*)1);
    pthread_create(&threads[1], NULL, thread_function, (void*)2);

    pthread_join(threads[0], NULL);
    pthread_join(threads[1], NULL);

    return 0;
}

```

### Dealing with NUMA

To implement NUMA-aware arena allocators that avoid going through the main bus, you need to ensure that memory allocations are local to the NUMA node where the thread is running. This can significantly reduce memory access latency and improve performance in multi-threaded applications. Here are the steps and considerations based on the provided sources:

1. Understanding NUMA and Arena Allocators
    NUMA (Non-Uniform Memory Access) architecture involves multiple memory nodes, each with its own local memory. Accessing local memory is faster than accessing memory from another node. Arena allocators manage large blocks of memory and allocate smaller chunks from these blocks, which can be optimized for NUMA by ensuring that each thread allocates memory from its local node.

2. Using NUMA-Aware Allocation Functions
    - libnuma: Use the numa_alloc_onnode() function from the libnuma library to allocate memory on a specific NUMA node. This function uses mmap() to allocate memory and mbind() to set the NUMA policy
    - Thread Pinning: Pin threads to specific CPUs using pthread_setaffinity_np() to ensure that memory allocations are local to the thread's NUMA node

3. Implementing Thread-Local Arenas

Each thread can have its own arena allocator that allocates memory from its local NUMA node. This reduces contention and ensures that memory accesses are local.
    - Initialization: At the start of each thread, allocate a large block of memory using numa_alloc_onnode() and manage this block using an arena allocator.
    - Allocation: When a thread needs memory, it allocates from its local arena. This avoids the overhead of frequent system calls and ensures memory locality
4. Example Implementation
    Here is a simplified example in C using libnuma:


```c
#include <numa.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

#define ARENA_SIZE (1024 * 1024) // 1 MB

typedef struct {
    void* start;
    size_t offset;
    size_t size;
} Arena;

__thread Arena thread_arena;

void* arena_alloc(size_t size) {
    if (thread_arena.offset + size > thread_arena.size) {
        return NULL; // Out of memory
    }
    void* ptr = (char*)thread_arena.start + thread_arena.offset;
    thread_arena.offset += size;
    return ptr;
}

void init_thread_arena(int node) {
    thread_arena.start = numa_alloc_onnode(ARENA_SIZE, node);
    thread_arena.offset = 0;
    thread_arena.size = ARENA_SIZE;
}

void* thread_function(void* arg) {
    int node = *(int*)arg;
    init_thread_arena(node);
    void* mem = arena_alloc(256); // Allocate 256 bytes
    printf("Thread on node %d allocated memory at %p\n", node, mem);
    return NULL;
}

int main() {
    pthread_t threads[2];
    int nodes[2] = {0, 1}; // Assuming a 2-node NUMA system

    for (int i = 0; i < 2; i++) {
        pthread_create(&threads[i], NULL, thread_function, &nodes[i]);
    }

    for (int i = 0; i < 2; i++) {
        pthread_join(threads[i], NULL);
    }

    return 0;
}

```