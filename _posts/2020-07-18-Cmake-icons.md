---
layout: post
title:  "Embedding icon into GUI executables for MacOS / Windows via cmake"
date:   2020-07-18 15:06:06 -0700
tags: cmake build
author: bolu-atx
categories: programming
---

CMake while being arcane and quirky in its own way, is currently the standard cross-platform compilation platform for C++/C build systems. I think the power of CMake comes from all the community contributions and the knowledge base built up over the years.

I recently worked on a project to migrate it from an archaic Perl build system into the land of CMake. Following modern CMake practices really made dependency management a breeze (i.e. target based compilation flag specification, target based linking, transient header propagation via INTERFACE/PUBLIC/PRIVATE, generator expressions to optionally specify different compiler warning / optimization levels)

One of the things that took a little while for me to figure out is how to embed a GUI based application an application icon that is in a cross-platform friendly method. I googled around and really didn't come across a simple enough solution, so I decided to roll my own.

<!--more-->

I wrote a `.cmake` module that defines a CMake function `AddIconToBinary()` that allows you to embed the application icon in a cross-platform way. The usage example is as follows:

```cmake
# USAGE:
set(SOURCE_FILES source/main.cpp
        source/helpers/utils.cpp)
set(HEADERS source/helpers/utils.h)

# Add icons
include(${CMAKE_SOURCE_DIR}/cmake/AddIconToBinary.cmake)
AddIconToBinary(SOURCE_FILES ICONS ${CMAKE_SOURCE_DIR}/infra/kin.ico ${CMAKE_SOURCE_DIR}/infra/kin.icns)
if (MSVC)
    add_executable(${APP_TARGET} WIN32 ${SOURCE_FILES} ${HEADERS})
elseif(APPLE)
    add_executable(${APP_TARGET} MACOSX_BUNDLE ${SOURCE_FILES} ${HEADERS})
else()
    message(FATAL_ERROR "Unsupported platform, currently we are only supporting MacOS / Windows")
endif()
```
`icns` file is the MacOS icon file archive format that contains a wide variety of different sizes. `ico` is the Windows icon format. You can find online tools that take your SVG/PNG icons into these formats.

#### AddIconToBinary.cmake

```cmake
include(CMakeParseArguments)

function(AddIconToBinary appsources)
    set(options)
    set(oneValueArgs OUTFILE_BASENAME)
    set(multiValueArgs ICONS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT ARG_ICONS)
        message(FATAL_ERROR "No ICONS argument given to AddIconToBinary")
    endif()
    if (ARG_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unexpected arguments to ecm_add_app_icon: ${ARG_UNPARSED_ARGUMENTS}")
    endif()

    foreach (icon ${ARG_ICONS})
        get_filename_component(icon_full ${icon} ABSOLUTE)
        get_filename_component(icon_type ${icon_full} EXT)
        get_filename_component(icon_name ${icon_full} NAME_WE) 

        if (APPLE)
            if (${icon_type} STREQUAL ".icns")
                set(icon_full_output ${CMAKE_CURRENT_BINARY_DIR}/${icon_name}.icns)
                configure_file(${icon_full} ${icon_full_output} COPYONLY)
                set(MACOSX_BUNDLE_ICON_FILE ${icon_name}.icns PARENT_SCOPE)
                set(${appsources} "${${appsources}};${icon_full_output}" PARENT_SCOPE)
                set_source_files_properties(${icon_full_output} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
                return()
            endif()            
        endif()
        if (MSVC)        
            if (${icon_type} STREQUAL ".ico")
                set(icon_full_output ${CMAKE_CURRENT_BINARY_DIR}/${icon_name}.ico)
                configure_file(${icon_full} ${icon_full_output} COPYONLY)
                file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${icon_name}.rc.in" "IDI_ICON1        ICON        DISCARDABLE    \"${icon_name}.ico\"\n")
                add_custom_command(
                        OUTPUT "${icon_name}.rc"
                        COMMAND ${CMAKE_COMMAND}
                        ARGS -E copy "${icon_name}.rc.in" "${icon_name}.rc"
                        DEPENDS "${icon_name}.ico"
                        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
                set(${appsources} "${${appsources}};${icon_name}.rc" PARENT_SCOPE)
                return()
            endif()
        endif()

    endforeach()
    
    return()
endfunction()
```

