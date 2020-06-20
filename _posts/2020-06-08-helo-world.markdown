---
layout: post
title:  "Hello World"
date:   2020-06-08 15:06:06 -0700
categories: general
author: bolu-atx
---

This is the obligatory "Hello World" post.

After various attempts to use Wordpress, Vue, React, I've decided to just switch to Github pages (Jekyll). The setup was fairly painless:

- The official [Github pages](https://pages.github.com/) guide was very helpful
- To re-direct my custom domain (bolu.dev) to the Github pages, I followed Hossain Khan's guide here: https://medium.com/@hossainkhan/using-custom-domain-for-github-pages-86b303d3918a

The main advantage of moving to Github pages is the ease of setup and migration should I need to do so in the future. There's no database, almost no-setup, and I can make use of standard git workflows. The posts are in markdown so I can work on it piece-meal whenever I want. Looking forward to see if this motivates me to write more.

### On setting up WSL2

It was pretty painful to setup Jekyll on WSL2 (Ubuntu 18.04 LTS) - mainly due to WSL2 by default adds all the Windows paths into the WSL2 PATH and the fact that all directories on `/mnt/C` are too permissive `0777`.

Instead of manually setting up a new path, this one liner below will help trim all /mnt/c paths from the PATH temporarily for the current bash session

```bash
export PATH=`echo $PATH | tr ':' '\n' | awk '($0!~/mnt\/c/) {print} ' | tr '\n' ':'`
```

Afterwards, the setup is identical to normal Linux, I just followed Jekyll's ubuntu [guide](https://jekyllrb.com/docs/installation/ubuntu/). Also note, if you use different gcc compiler versions other than the default ubuntu one (I think gcc7 is the default on Ubuntu 18.04), then you need to make sure to use `sudo update-alternatives --config gcc`  and `sudo update-alternatives --config g++` to switch back to the default versions. Otherwise, you will get a silent failure when installing `bundle/jekyll` via ruby gems.

I also ran into conflicts of different versions of Ruby packages due to a prior install of `jekyll` through apt, so make sure you start with a clean-slate!


### On writing equations in LaTeX

Getting MathJax to work with Jekyll was suprisingly easy, all I needed to do was to insert this snippet into my `head.html`

```html
<script type="text/javascript" src="https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"></script>
```
After that, I can use LaTeX syntax as such: `$$ y = \int{a}{b}{x^2+3x+b} $$` gets rendered into:

$$ y = \int{a}{b}{x^2+3x+b} $$


### On other useful Jekyll goodies
- [Automatic tag management](http://longqian.me/2017/02/09/github-jekyll-tag/) and archiving from Long Qian
- [Automatic tag generator](https://www.untangled.dev/2020/06/02/tag-management-jekyll/) via Jekyll hooks
- [Google analytics](https://michaelsoolee.com/google-analytics-jekyll/) to get visitor and stats on the site 
