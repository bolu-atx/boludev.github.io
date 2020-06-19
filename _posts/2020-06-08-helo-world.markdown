---
layout: post
title:  "Hello World"
date:   2020-06-08 15:06:06 -0700
categories: general
---

This is the obligatory "Hello World" post.

After various attempts to use Wordpress, Vue, React, I've decided to just switch to Github pages (Jekyll). The setup was fairly painless:

- The official [Github pages](https://pages.github.com/) guide was very helpful
- To re-direct my custom domain (bolu.dev) to the Github pages, I followed Hossain Khan's guide here: https://medium.com/@hossainkhan/using-custom-domain-for-github-pages-86b303d3918a

The main advantage of Github pages is the ease of setup and migration should I need to do so in the future. There's no database, almost no-setup, and I can make use of standard git workflows. Looking forward to see if this motivates me to write more and document more.


### Notes on setting up Jekyll on WSL2

It was pretty painful to setup Jekyll on WSL2 - mainly due to WSL2 by default adds all the Windows paths into the WSL2 PATH and the fact that all directories on `/mnt/C` are too permissive `0777`.

What I did was then to execute this first:

```bash
export PATH=`echo $PATH | tr ':' '\n' | awk '($0!~/mnt\/c/) {print} ' | tr '\n' ':'`
```

and then to follow the Jekyll's ubuntu [guide](https://jekyllrb.com/docs/installation/ubuntu/). Also note, if you use different gcc compiler versions other than the default ubuntu one (I think gcc7 is the default on Ubuntu 18.04), then you need to make sure to use `sudo update-alternatives --config gcc`  and `sudo update-alternatives --config g++` to switch back to the default versions. Otherwise, you will get a silent failure when installing `bundle/jekyll` via ruby gems.

I also ran into conflicts of different versions of Ruby packages due to a prior install of `jekyll` through apt, so make sure you start with a clean-slate!