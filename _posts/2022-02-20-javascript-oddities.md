---
layout: post
title:  "Javascript oddities"
date:   2022-02-25 9:06:06 -0700
tags: javascript programming
author: bolu-atx
categories: javascript typescript programming
---


A collection of weird things in Javascript:

### 1. `var` scoping rules

```js
for (var i = 0; i < 3; ++i)
{
	const log = () => {
  	console.log(`a ${i}`);
  }
  setTimeout(log, 100);
}

for (let i = 0; i < 3; ++i)
{
	const log = () => {
  	console.log(`b ${i}`);
  }
  setTimeout(log, 100);
}
```

The output here is:
```
"a 3"
"a 3"
"a 3"
"b 0"
"b 1"
"b 2"
```

Why does `var` cause it to print 3?

### 2. `const` in Javascript does not mean the same as C/C++.  Example:

```javascript
const value = 3;
value = 4; // error, cannot override a constant
value += 3; // error

const obj = {a : 3};
obj.a += 3; //allowed
obj.a = 5; //allowed
```

Turns out `const` in Javascript is more of a "const" reference like `const &` in C++. It does not mean the value itself is constant - just the reference to the array cannot be changed.


### 3. Converting time formats can be tricky

Suppose you have a time in `yyyy-mm-DD` format and you want it in `mm/DD/yyyy` format.

```javascript
new Date('2016-06-05').
  toLocaleString('en-us', {year: 'numeric', month: '2-digit', day: '2-digit'})

// Output:
>>> '06/04/2016'
```

Wait, what happened?, I asked for 2016-06-05 in `mm/dd/YYYY` but it gave me `06/04/2016` instead! This because all dates by default assumes it's GMT time, when you convert it to a local timezone, you might get a different date.

The `moment` library fortunately makes this a lot easier.

```javascript
var date = new Date('10/01/2021');
var formattedDate = moment(date).format('YYYY-MM-DD');
```

If we don't want some extra dependency, it's probably easier to just not convert the date into a Javascript `Date` obj and directly do string operations on it to get it to the format you want. Example:

```javascript
function reformatDateString(dateString) {
    //reformat date string to from YYYY-MM-DD to MM/DD/YYYY
    if (dateString && dateString.indexOf('-') > -1) {
        const dateParts = dateString.split('-');
        return `${dateParts[1]}/${dateParts[2]}/${dateParts[0]}`;
    }
    return dateString;
}
```

