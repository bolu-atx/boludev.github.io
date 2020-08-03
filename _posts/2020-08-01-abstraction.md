---
layout: post
title:  "Abstraction All the Way Down"
date:   2020-08-01 15:06:06 -0700
tags: blog
author: bolu-atx
categories: programming
---

Programming or any problem solving skill is really all about distilling complex problems into simpler abstractions.  The art of creating elegant abstractions is a skill that developers must acquire on their journey to master software craftsmanship. Terse abstractions that fully describes a problem helps reduce cognitive burden, allowing the developer to focus on what really matters in the code. 

<!--more-->

Abstractions exist in hardware, software, design patterns or even business logic.
When I'm writing about abstractions, I'm largely referring to software and design pattern abstractions - since those are what I am most familiar with. However, it does not mean that similar concepts cannot be applied to other problem domains or areas. 

<img
src="https://images.squarespace-cdn.com/content/v1/550c787fe4b05aacac39d2d5/1557949823164-P38BEW1003AJ1USPU740/ke17ZwdGBToddI8pDm48kD33KhhWEodMJvcytjXFyvFZw-zPPgdn4jUwVcJE1ZvWQUxwkmyExglNqGp0IvTJZamWLI2zvYWH8K3-s_4yszcp2ryTI0HqTOaaUohrI8PIFbyG1bnTu2n2cGYUv9pFL8WtEMIRp8edI1V1pz5mx5E/CCAbOP.gif?format=1000w" />

Just like models, "all abstractions are wrong, but some are useful". The usefulness of abstractions we created is strongly dependent on the problem at hand. Knowing how to draw system boundaries, defining input, output, and system states empowers the developer to pick the right abstraction - this skill is probably more of an art rather than a science. Although rules of thumb apply, every scenario is different. Unless you are working with just basic CRUD type of application. Even then, in those scenarios, scale is important, and considerable complexity arises from the scale of the problem - which simply shifts the focus to "scaling" rather than the CRUD operations themselves.

Conversely, the level of abstraction selected to model the problem also defines the solution space for the problem itself. Just as abstractions help simplify a complex problem into things that can be reasoned more modularly. This simplification often masks the complexity of reality. For example, if we are discussing variable scope, lifetimes and assignment operations, we are opearting at the abstraction level of programming languages and semantics - at this level, the details of how hardware components interact with the kernel to create memory pages, to load data from DRAM into CPU caches, and many other details are all abstracted away. This might be fine for a toy program or some business logic where speed is not critical. However, in infrastructure critical code or compute intensive applications, we might want to have access to lower level assembly code to have finer control over our program. As a result, one might need to plan ahead for the potential possibility of having to write hand-tuned assembly code if speed/business needs dictates it. On the other extreme, we might not care about variable lifetimes at all and want to reason about the high level business logic at a module-level, in which case, object oriented programming paradigms 

In any case, there's really no subsitute for practice when it comes to getting better at coming up with appropriate abstractions for the given problems. Developing the intuition for when to abstract and what to abstract takes experience, training and intuition. It is also important to re-evaluate the assumptions in your abstraction - some of these might seem constant at the time, but are in reality variables that just happens to change very slowly.

