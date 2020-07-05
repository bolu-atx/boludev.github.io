---
layout: post
title:  "Where did the heap memory that I just freed go?"
date:   2020-06-26 10:06:06 -0700
tags: cpp kernel linux
author: bolu-atx
categories: programming
---
Heap memory allocation via `new` and `delete` (or `malloc` or `free` for C) are unavoidable for more complex, large scale programs. However, it is a common misconception that `free/delete` will actually free the memory back to the operating system for other processes to use.

This is because there are actually two different types of memory allocation happening behind a `malloc/new` call. The first type, reserved usually for smaller allocations (less than 100 kb) uses `sbrk()`, which is a traditional way of allocating memory in UNIX -- it just expands the data area by a given amount. The second type uses `mmap()` to allocate memory for larger chunks of memory. `mmap()` allows you to allocate independent regions of memory without being restricted to a single contiguous chunk of virtual address space. A memory mapped region obtained through `mmap()` upon unmapping will immediately release the memory back to the OS, whereas `sbrk()` will keep the released memory within the process for future allocations.

<!--more-->

I won't get into the details of custom-built memory allocators such as jemalloc or tcmalloc; they are a fascinating topic on their own. Here the problem I wanted to investigate is how do I get the behavior I wanted using default glibc allocators. I wrote a little test program helped me to test the memory allocation behavior on CentOS7 linux with GCC 4.8.5 compiler:

```cpp
#include <iostream>
#include <vector>
#include <algorithm>
#include <random>
#include <chrono>

#include "stdlib.h"
#include "stdio.h"
#include "string.h"

// https://stackoverflow.com/questions/63166/how-to-determine-cpu-and-memory-consumption-from-inside-a-process
int parseLine(char* line){
    // This assumes that a digit will be found and the line ends in " Kb".
    int i = strlen(line);
    const char* p = line;
    while (*p <'0' || *p > '9') p++;
    line[i-3] = '\0';
    i = atoi(p);
    return i;
}

int getTotalVirtualMem(){ //Note: this value is in KB!
    FILE* file = fopen("/proc/self/status", "r");
    int result = -1;
    char line[128];

    while (fgets(line, 128, file) != NULL){
        if (strncmp(line, "VmSize:", 7) == 0){
            result = parseLine(line);
            break;
        }
    }
    fclose(file);
    return result;
}


int getTotalPhysicalMem(){ //Note: this value is in KB!
    FILE* file = fopen("/proc/self/status", "r");
    int result = -1;
    char line[128];

    while (fgets(line, 128, file) != NULL){
        if (strncmp(line, "VmRSS:", 6) == 0){
            result = parseLine(line);
            break;
        }
    }
    fclose(file);
    return result;
}

int main() {
    typedef ushort ElementType;
    typedef std::vector<ElementType> BufferType;
    BufferType* ptr;

    std::vector<size_t> num_elements_vec {1024, 1024*10, 1024*100, 1024*1024, 1024*1024*10, 1024*1024*100, 1024*1024*1024};

    // shuffle the order of the allocation elements
    unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
    auto rng = std::default_random_engine {seed};
    std::shuffle(std::begin(num_elements_vec), std::end(num_elements_vec), rng);

    for (const auto num_elements : num_elements_vec)
    {
        int virt_mem_before, virt_mem_during, virt_mem_after;
        int phys_mem_before, phys_mem_during, phys_mem_after;

        virt_mem_before = getTotalVirtualMem();
        phys_mem_before = getTotalPhysicalMem();
        std:: cout << "Number of elements: " << num_elements << " expected memory: "  << num_elements * sizeof(ElementType)  / 1024 << " kb \n";
        std::cout << "Before allocation: virt: " << virt_mem_before << " kb, physical: " << phys_mem_after <<" kb\n";
        const size_t alloc_size_bytes = num_elements * sizeof(ElementType);
        // memory actually does not get allocated here
        auto ptr = (ElementType*) malloc(alloc_size_bytes);        
        // memory allocation happens when you try to use it!
        memset(ptr, 0, alloc_size_bytes);
        virt_mem_during = getTotalVirtualMem();
        phys_mem_during = getTotalPhysicalMem();

        std::cout << "Before destruction: virt: " << virt_mem_during << " kb, physical: "<< phys_mem_during <<" kb \n";

        free(ptr);

        virt_mem_after = getTotalVirtualMem();
        phys_mem_after = getTotalPhysicalMem();

        std::cout << "After desctruction: virt: " << virt_mem_after << " kb, physical: "<< phys_mem_after <<" kb\n";
        std::cout << "Allocation virt: " << (virt_mem_during - virt_mem_before) << " kb, physical: "<< (phys_mem_during - phys_mem_before )<<" kb\n";
        std::cout << "Deallocation virt: " << (virt_mem_during - virt_mem_after) << " kb, physical: "<< (phys_mem_during - phys_mem_after )<<" kb\n\n\n";

    }
    std::cout << "Done.\n";
}
```
You should be able to compile this with any modern gcc compiler that supports C++11 or higher. Note that while the memory allocation part works on any OS, I used Linux specific parsing of `/proc/self` to check the current process memory usage, so this whole piece of code is not cross platform compatible.

### Output Analysis

For small buffers less than 200kb, the behavior is that the deallocation calls actually do not return the memory to the OS, as seen below (where the deallocation virt/physical are both 0 kb):

```
Number of elements: 1024 expected memory: 2 kb 
Before allocation: virt: 13232 kb, physical: 0 kb
Before destruction: virt: 13236 kb, physical: 1476 kb 
After destruction: virt: 13236 kb, physical: 1476 kb
Allocation virt: 4 kb, physical: 40 kb
Deallocation virt: 0 kb, physical: 0 kb

Number of elements: 10240 expected memory: 20 kb 
Before allocation: virt: 13236 kb, physical: 1476 kb
Before destruction: virt: 13236 kb, physical: 1492 kb 
After destruction: virt: 13236 kb, physical: 1492 kb
Allocation virt: 0 kb, physical: 16 kb
Deallocation virt: 0 kb, physical: 0 kb

Number of elements: 102400 expected memory: 200 kb 
Before allocation: virt: 13236 kb, physical: 1492 kb
Before destruction: virt: 13436 kb, physical: 1672 kb 
After destruction: virt: 13436 kb, physical: 1672 kb
Allocation virt: 200 kb, physical: 180 kb
Deallocation virt: 0 kb, physical: 0 kb
```

But for larger buffers (>200kb), the memory does get returned as soon as you call `free/delete`. The real cut-off is between 200 kb vs 2 Mb on the default CentOS7 glibc implementation. We can use a more granular test allocation size to identify the exact cut-off point, but 200kb seems like a good enough cutoff.

```
Number of elements: 1073741824 expected memory: 2097152 kb 
Before allocation: virt: 13236 kb, physical: 1476 kb
Before destruction: virt: 2110392 kb, physical: 2098632 kb 
After destruction: virt: 13236 kb, physical: 1476 kb
Allocation virt: 2097156 kb, physical: 2097156 kb
Deallocation virt: 2097156 kb, physical: 2097156 kb


Number of elements: 10485760 expected memory: 20480 kb 
Before allocation: virt: 13236 kb, physical: 1492 kb
Before destruction: virt: 33720 kb, physical: 21976 kb 
After destruction: virt: 13236 kb, physical: 1492 kb
Allocation virt: 20484 kb, physical: 20484 kb
Deallocation virt: 20484 kb, physical: 20484 kb

Number of elements: 104857600 expected memory: 204800 kb 
Before allocation: virt: 13236 kb, physical: 1492 kb
Before destruction: virt: 218040 kb, physical: 206296 kb 
After destruction: virt: 13236 kb, physical: 1492 kb
Allocation virt: 204804 kb, physical: 204804 kb
Deallocation virt: 204804 kb, physical: 204804 kb


Number of elements: 1048576 expected memory: 2048 kb 
Before allocation: virt: 13236 kb, physical: 1492 kb
Before destruction: virt: 15288 kb, physical: 3544 kb 
After destruction: virt: 13236 kb, physical: 1492 kb
Allocation virt: 2052 kb, physical: 2052 kb
Deallocation virt: 2052 kb, physical: 2052 kb
```

## Attempts at Changing The Default Behavior


### Attempt 1. GLIBC Tunables

The official [documentation](https://www.gnu.org/software/libc/manual/html_node/Memory-Allocation-Tunables.html#Memory-Allocation-Tunables) for glibc has a section on "tunables" which are environment variables you can set to change the behavior of glibc.
Specifically, there's `glibc.malloc.mmap_threshold` which should be an integer in bytes that tells the glibc memory allocator when to switch to `mmap` instead of `sbrk`. There's also something similar `glibc.malloc.trim_threshold` which sets upper threshold on which `malloc_trim` will be called on `sbrk` allocated heap memory to tell the OS that those memories are no longer needed and ready for re-claim.

However, after trying them on my test program, I did not see any difference at all. I also tried to use the `mallopt` method provided in `malloc.h` header of the libc directly, and actually got a `0` status returned on my CentOS7 machine.
It appears these tunables are optional features that the distro maintainers can pick/choose; for CentOS7, this feature appears to be disabled. I did not want to explore how to link against a custom version of glibc, it appears to be non-trivial to have two different versions of glibc on the same system. In addition, if this is required, it defeats the purpose of using the default memory allocator. We might as well go with a custom allocator like jemalloc instead.


### Attempt 2. Write a simple dumb memory allocator to get desired behavior

We can wrap a custom allocator class using `mmap` and `unmmap` to get guaranteed memory freeing upon release

```cpp
void* malloc_mmap(const size_t sz)
{
    void* ptr = mmap(NULL, sz, PROT_READ|PROT_WRITE, 
                  MMAP_PRIVATE|MMAP_ANONYMOUS,
                  -1, (off_t)0);

    if (ptr == MMAP_FAILED)
        ptr = nullptr;

    return ptr; 
}

bool free_mmap(void* ptr, const size_t sz)
{
  return (munmap((void*)ptr, sz));
}
```

This is pretty simple since we need the size of the buffer to de-allocate, but we can make this more complex by storing the pointer and size into some map to be looked-up later.

Another optimization that might be good to do is to overload the default `new` and `free` methods in C++, an example/tutorial is [available here](https://www.geeksforgeeks.org/overloading-new-delete-operator-c/).

Using this allocator and re-testing the small size allocations, we get the following behavior:

```
Number of elements: 10240 expected memory: 20 kb 
Before allocation: virt: 13240 kb, physical: 1476 kb
Before destruction: virt: 13260 kb, physical: 1496 kb 
After destruction: virt: 13240 kb, physical: 1476 kb
Allocation virt: 20 kb, physical: 20 kb
Deallocation virt: 20 kb, physical: 20 kb


Number of elements: 102400 expected memory: 200 kb 
Before allocation: virt: 13240 kb, physical: 1476 kb
Before destruction: virt: 13440 kb, physical: 1676 kb 
After destruction: virt: 13240 kb, physical: 1476 kb
Allocation virt: 200 kb, physical: 200 kb
Deallocation virt: 200 kb, physical: 200 kb
```

### Attempt 3. Linking against a custom allocator

I decided to try jemalloc and see if their custom tuning options can help in tuning sbrk/mmap. Their tuning instructions is [here](https://github.com/jemalloc/jemalloc/blob/dev/TUNING.md).

On CentOS7, the jemalloc is part of the EPEL repo, and can be installed very easily:

```bash
sudo yum install jemalloc-devel
```

Once installed, you can modify the behavior by using `LD_PRELOAD` environmental variable:
```bash
export LD_PRELOAD=$LD_PRELOAD:/usr/lib64/libjemalloc.so.1
```

After using jemalloc, we can see the memory allocation behavior definitely changed. For starters, the initial virt page size is much larger (25 mb instead of 12 mb). The threshold for reclaiming physical memory seems to be smaller than default malloc (200 kb allocation gets reclaimed after free). However, the virtual memory does not get freed, even at fairly large allocations like 46 mb. I don't know what the implication of this behavior is.

```
Number of elements: 1024 expected memory: 2 kb 
Before allocation: virt: 25648 kb, physical: 0 kb
Before destruction: virt: 25652 kb, physical: 1712 kb 
After destruction: virt: 25652 kb, physical: 1712 kb
Allocation virt: 4 kb, physical: 40 kb
Deallocation virt: 0 kb, physical: 0 kb


Number of elements: 102400 expected memory: 200 kb 
Before allocation: virt: 25652 kb, physical: 1712 kb
Before destruction: virt: 25652 kb, physical: 1912 kb 
After destruction: virt: 25652 kb, physical: 1716 kb
Allocation virt: 0 kb, physical: 200 kb
Deallocation virt: 0 kb, physical: 196 kb


Number of elements: 10240 expected memory: 20 kb 
Before allocation: virt: 25652 kb, physical: 1716 kb
Before destruction: virt: 25652 kb, physical: 1736 kb 
After destruction: virt: 25652 kb, physical: 1740 kb
Allocation virt: 0 kb, physical: 20 kb
Deallocation virt: 0 kb, physical: -4 kb


Number of elements: 1048576 expected memory: 2048 kb 
Before allocation: virt: 25652 kb, physical: 1740 kb
Before destruction: virt: 25652 kb, physical: 3792 kb 
After destruction: virt: 25652 kb, physical: 1752 kb
Allocation virt: 0 kb, physical: 2052 kb
Deallocation virt: 0 kb, physical: 2040 kb


Number of elements: 10485760 expected memory: 20480 kb 
Before allocation: virt: 25652 kb, physical: 1752 kb
Before destruction: virt: 46132 kb, physical: 22236 kb 
After destruction: virt: 46132 kb, physical: 1756 kb
Allocation virt: 20480 kb, physical: 20484 kb
Deallocation virt: 0 kb, physical: 20480 kb
```

To tune the behavior of jemalloc, we can set the `MALLOC_CONF` environmental variable, the full list of options are [here](http://jemalloc.net/jemalloc.3.html#size_classes).

```bash
# set the oversize threshold to 10 mb
export MALLOC_CONF="oversize_threshold:10485760"
```

However, I got an error in the code
```
<jemalloc>: Invalid conf pair: oversize_threshold:10485760
```
It appears that the default CentOS7 jemalloc package did not enable this as a run-time configurable option. To access more granular jemalloc customization, we must build jemalloc from source with various compile-time flags enabled/disabled, which might be an interesting topic for another write-up in the future.

## Conclusion

- small memory allocations generally do not get released to the OS upon `free`
- large memory allocations do get released to the OS usually upon free
- If you do a lot of small memory allocations, `malloc_trim` will advise the OS to reclaim memory if you do a lot of small allocations on the heap
- for large buffers (>200 kb), the allocation is done via `mmap` and you do not have to worry about the memory being stuck in the process.
- custom memory allocators have different behavior fine-tuned to the application of choice - make sure you read their manual and see if the designed behavior matches your intended application