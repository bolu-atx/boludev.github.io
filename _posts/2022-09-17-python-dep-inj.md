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

### Solution 1. The Factory Pattern 

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

### Solution 2. The Dynamic Import + Factory pattern

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

All the `modules` that can be specified in the `type` needs to conform to some interface by some implicit convention. In this example, that convention is the `make_storage` method - Let's review the pros and cons:

- Dynamic import sometimes can be finnicky especially during development when the import path is not set properly
- Dynamic import could potentially expose security issues if the config file can be modified by outside parties
- The interface expected by the factory varies depending on the instantiated type and this interface needs to be implicitly provided in the `**kwargs` or some other config parameters that requires careful validation and documentation.

### Solution 3. The Dependency Injection Pattern

The dependency injection pattern is another option to solve this instantiation problem with abstract interface types. It trades off more complexity and initial setup time but offers the developer much higher flexibility and scalability. It is very commonly used on large applications in Java, C#.

There are several terminology that will help in understanding the DI pattern:

- *Container*: container provides instantiated objects or instantiation methods that allow a specific object to be created when requested
- *Interface*: OOP-interface, allows us to query to see if a container contains said types that conform to certain interface
- *Injector*:  a holder type that should have access to the container and help resolve dependencies to construct types when requested for.
- *Injection Scope*, a scope of injection, this is typically not required for simple applications but is essentially as the application gets large - in addition, the user can specify whether the injected type is a `singleton` type or there can be multiple instances to get the `singleton` pattern for free for common services such as logging, performance monitoring etc.

A typicaly dependency injection workflow involves:
- The binding step - the dev needs to declare what type or what type provider can provide certain types to the `container`
- The request step - the dev needs to request a interface type to trigger dependency injection
- The resolution step - this step is usually abstracted away from the user of the DI library. But in this step, the injector/container will attempt to satisfy the DI request and return a type that fufills the interface requirements

There are two highly rated dependency injection libraries available for Python. After surveiling the internetz, it appears `injector` is simpler and more straight forward, while `dependency-injector` is more fully featured and supports more complicated DI patterns.

- [dependency-injector](https://python-dependency-injector.ets-labs.org/)
- [injector](https://pypi.org/project/injector)

I decided to use `injector` in the end for its simplicity. 

The simplest DI example would be something like below:

```py
from injector import Binder, Injector, Module, provider, singleton

### in some other file
Configuration = Dict[
    str,
    Union[
        str,
        int,
        float,
        bool,
        List[str],
        List[int],
        List[float],
        List[bool],
        np.ndarray,
        List[np.ndarray],
        Dict[str, Any],
        List[Dict[str, Any]],
    ],
]

def test_bind_singleton(config: Configuration) -> None:
    """Test that we can bind a class to a provider and get it back"""

    def config_provider(binder : Binder):
        binder.multibind(Configuration, to=config, scope=singleton)

    inj = Injector([config_provider])

    # since this is bound in singleton scope, the same instance is returned
    di_conf = inj.get(Configuration)
    di_conf_2 = inj.get(Configuration)
    di_conf_3 = inj.get(Configuration)

    # test for singleton
    assert id(di_conf) == id(di_conf_2)
    assert id(di_conf_3) == id(di_conf)
```

In this example: 

- we defined a method called `config_provider` in which we associate the type `Configuration` to an existing instance `config` in singleton scope.

- After that, we instantiated injector with this container and then requested the injector to resolve `Configuration`.

- We then verified that the configuration returned is indeed a singleton by checking its ID to ensure it matches other IDs.

For a more complex application, this doesn't change either - we first need to register all the providers - and then instantiate an Injector and ask injector to resolve the dependency for us. Using the similar `AbstractStorage` example above, that would look something like this

```py

# in module i.e. S3Storage.py
from injector import Binder, Injector, Module, provider, singleton

class S3Storage(AbstractStorage):
  ...

def get_provider():
  class _provider(Module):
    @provider
    @singleton
    def provide_storage(s3_conn : S3Connection, config : Configuration) -> AbstractStorage:
      return S3Storage(s3_conn, config)

def create_storage(config : Configpassuration) -> AbstractStorage:
  def config_provider(binder : Binder):
      binder.multibind(Configuration, to=config, scope=singleton)

  container = [config_provider]

  # this returns a list of modules, out of scope for this write-up
  dynamic_loaded_modules = dynamic_load_modules(config['components'])
  for module in dynamic_loaded_modules:
    container.append(module.get_provider())

  inj = Injector(container)
  storage = inj.get(AbstractStorage)
  return storage
```

And voila! Once we call `create_storage`, we should have a `S3Storage` instance that conforms to `AbstractStorage`. If there are more than 1 storage provider injected (i.e. in the dynamic load modules step), the injector will throw an error and complaining that singleton scope rule is being violated.

However, This is not a typical use case for dependency injection - I had to take some shortcuts to make the code self-containing and does not dependent on any other methods or modules.


In a **realistic scenario**, we do not use dependency injection in a stand-alone way to just resolve one specific instance, but leverage dependency injection to resolve a complex chain of dependencies to get complex objects. For example:

```py
class Application

  @inject
  def __init__(self, logger : Logger, db : DatabaseProvider, storage : StorageProvider, server : HTTPServer, api_x : XAPI):
  ...

  def version(self) -> str:
    ...

  def config(self) -> str:
    ...

  def context(self) -> str:
    ...

  def run(self) -> bool:
    ...
    

# provider declaration skipped here
inj = Injector(container_providers)
app = inj.get(Application)
logger = inj.get(Logger)
logger.info(app.version())
logger.info(app.config())
logger.info(app.context())

exit_code = 0 if app.run() else 1
sys.exit(exit_code)
```

In this example, the `Appliation` constructor is decorated with `@inject`, which is just syntatic sugar for declaring a provider. The injector looks at the method and realizes that it needs `Logger`, a `StorageProvider`, a `DatabaseProvider` and a `API` type and attempts to map them to the types it knows how to construct based on the container provider. As long as these dependencies are satisfied by the declaration provided to the DI module, we sholud be able to fully construct `app`.

What seems **magical** to me is that the `injector` library is able to make use of the type hints to resolve the types of each variable instead of relying on convention or magic python variables such as `__class__` or `__name__`. This magic makes using the DI pattern a pleasure just like in C# or Java-land.


### Cons of DI framework to keep in mind

Lastly, This post is not meant to advocate DI regardless of project scale and complexity - in fact, there are [obvious draw-backs](https://en.wikipedia.org/wiki/Dependency_injection#Disadvantages) of the DI pattern that the user should be aware of:

- Creates clients that demand configuration details, which can be onerous when obvious defaults are available.
- Prone to abuse and makes the dependency chain difficult to trace
- Typically requires more upfront development effort and encourages dependence on a framework.
