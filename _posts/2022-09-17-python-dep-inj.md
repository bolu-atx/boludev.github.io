---
layout: post
title:  "Dependency injection in Python"
date:   2022-09-17 9:06:06 -0700
tags: python programming
author: bolu-atx
categories: python programming
---

Since Python type hints are introduced, they have made complex Python code-bases much more readable and easier to maintain - especially combined with newer static analysis tools such as `mypy` or `pylint`. However, even with these tools, Python is still a dynamic language.  When using a dynamic language on a larger application (>5k LOC), the ability to do whatever we wanted any where and any time is more of a curse than a blessing.

In this post, I wanted to discuss several options of implementing loosely coupled code in large Python codebases that I have played around with and the final solution of **dependency injection** based pattern I ended up deciding on.

<!--more-->

### What is the problem?

Before we dive into the how, let's discuss the why and the context of what we are doing

[SOLID principle](https://medium.com/mindorks/solid-principles-explained-with-examples-79d1ce114ace) dictates that software components should be interchangable, and loosely coupled based on well defined interfaces that have minimal shared state and shared responsibilities. This post is not meant to argue the **why**, so let's assume that SOLID principle is a good sound idea that we should practice in our daily software development.

To "ground" the discussion into more concrete examples, suppose we are building a service that interfaces with many potential storage backends (filesystem, in-memory, database, s3). The exact setup of the service could vary from one deployment to the next and we wanted to make sure that we can pick any of the above and also set the code-base ready for extension into other backend services the future might bring us.


This naturaly leads to an interface + several concrete implementation pattern that fits the classical object-oriented programming paradigm.

The abstract interface and two example concrete implementations might look something like this

```python
class AbstractStorage(ABC):
  """Abstract interface for backend storage provider"""
  def __init__(self, **kwargs : dict):
    self.config = kwargs

  @abstractmethod
  def store(self, key, thing : Any) -> bool:
    ...

  @abstractmethod
  def destroy(self, key) -> bool:
    ...

  @abstractmethod
  def retrieve(self, key) -> Any:
    ...

class DatabaseStorage(AbstractStorage):
  def __init__(self, db_connection : Connection, table : str, **kwargs):
    self.db_conn = db_connection
    self.table = table
    super().__init__(**kwargs)

  # concrete implemetnations omitted here
  def store(self, key, thing : Any) -> bool:
    ...

  def destroy(self, key) -> bool:
    ...

  def retrieve(self, key) -> Any:
    ...

class S3Storage(AbstractStorage):
  def __init__(self, s3_credentials : S3Credential, s3_bucket : str, **kwargs):
    ...

  # detail impl omitted here
  ...
```

Hopefully, everything above makes sense, we are just doing vanilla object oriented design. Now, let's try to put this into practice. How do we decouple the user of this class from its implementation details? In other words, how do we instantiate the concerete implementation?

### The Factory Pattern 

The factory pattern is one of the simplest design patterns to employ to consolidate all the implementation specifics details of **instantiating a concrete implementation** into a centralized location. It is also my preferred choice of managing interface types for small projects.

In our specific example, we can do something like this:

```py
# storage_factory.py
def make_storage(configs : dict, db_connection : DatabaseConnection = None) -> AbstractStorage:
  if config['storage_type'] == 's3':
    return make_s3_storage(**configs['s3_storage_config'])
  if config['storage_type'] == 'database':
    return make_db_storage(db_connection = db_connection, **configs['db_storage_config'])
  if config['storage_type'] == '...':
    ...
```

The workflow would then be:

1. Parse configs either from commandline or load from file
2. Validate configs and instantiate required elements (such as `DatabaseConnection`)
3. Pass all validated configs and components into the `factory` methods for making various things
4. Factory returns the interface type and then the type can be used in various application logic


The draw-back of factory pattern is hopefully obvious to the astute reader:

- The factory methods will need to be updated whenver we need to handle a new specific concrete implementation
- If the new concrete implementation requires a new complex dependent type - we'll also need to modify the main application container to make that new complex type and then pass it into the factory (or instantiate that complex type inside the factory method directly if it doesn't need to be singleton and shared across other componnets)
- The various hard-coded magic "strings" become a fragile failure point of a otherwise loosely coupled interface - we can remediate this with Python enums that contain all the string keys to config fields and instance types but generally this technical debt is not paid off

### The Dynamic Import Pattern

To make the factory pattern more general, we can leverage Python's dynamic import capabilities to load modules on the fly based on a string description or a config key.


#### Example config

```py
config = {
  "storage_config" :
    {
      "type" : "base.storage_providers.database_storage_provider",
      "config_key1" : "config_val1",
      ...
    }
}
```

We can then make a generic `make_storage` method that utilizes dynamic import (i.e. importlib) to import a Python module based on a provided string from config file like so:

#### `factory.py`

```py
def make_storage(storage_config : dict) -> AbstractStorage:
  module_name = storage_config['type']
  mod = importlib.import_module(module_name)
  # dev should validate that the mod conforms to expected interface, skipped here

  return mod.make_storage(storage_config)
```

In this pattern, all the `modules` that can be specified in the `type` needs to conform to some interface by some implicit convention. In this example, that convention is that all of the modules should provide their own factory method `make_storage`. However, it is definitely a step-up from the classical factory based instantiatio in a sense that the dev no longer needs to update the `factory.py` when we add new components.
