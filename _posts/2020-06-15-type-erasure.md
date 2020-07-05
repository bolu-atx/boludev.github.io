---
layout: post
title:  "Type Erasure vs Polymorphism"
date:   2020-06-15 15:06:06 -0700
tags: cpp design-pattern template
author: bolu-atx
categories: programming
---

C++ templates are useful constructs to reduce code bloat (I think of them as fancy copy and paste) without any performance overhead at run-time.
However, to use them effectively might require some practice.
One issue I recently ran into while working with templates is the following:

Suppose I have a generic class `Foo<T>` that takes a template argument, I need to place `Foo<T>` in a container to be iterated upon or to be looked up later.  However, I might have multiple instantiations of `Foo<T>` of different types (i.e. `int, float, double, bool`), this makes it hard to use STL containers since these containers require the elements to be of a single type.

<!--more-->

After scouring the internet, I found that cplusplus.com article here (https://www.cplusplus.com/articles/oz18T05o/) was really insightful. I decided to update this article for my own interpretation.

## Classic Inheritence Approach

The straight-forward answer is to use classic polymorphism. We make the `Foo<T>` class a derived class of `IFoo`, and then instantiate a bunch of different `Foo<T>` but bind them `IFoo*`. The `IFoo*` can then be stored in a container such as `std::vector<IFoo*>`:

```cpp
class IFoo {
    public:
    virtual void bar() = 0;
}


template<typename T>
class Foo : public IFoo {
public:
    void bar() override {

    }

private:
    T m_foo;
}

int main() {
   std::vector<IFoo*> foos;
   for (size_t i = 0; i < 10; ++i>)
   {
      if (i % 2 == 0)
      {
         IFoo* ptr = new Foo<int>();
         foos.emplace_back(ptr);
      }
      else {
         IFoo* ptr = new Foo<float>();
         foos.emplace_back(ptr);
      }
   }

   // call bar
   for (auto ptr : foos)
   {
      ptr->bar();
   }

}
```

If raw pointers are scary to you, we can wrap `IFoo` with shared pointers or unique pointers to automatically clean-up the resources when they go out of scope.

```cpp
auto ptr = std::make_shared<IFoo>(new Foo<int>());
```

Why is this *bad*? According to this [post](https://www.cplusplus.com/articles/oz18T05o/), the claim is that the derived type is lost, therefore, we can no longer make a copy of the object if we wanted to. 

In addiiton, all the functions now need to be virtual, incurring slightly extra lookups costs for performance sensitive applications. This will also make `IFoo` cluttered.

## Type Erasure

In this [stack overflow post](https://stackoverflow.com/questions/4738405/how-can-i-store-objects-of-differing-types-in-a-c-container#4738459), `boost::any` was suggested. Since C++17, we can also use `std::any` to achieve the same functionality. 

These variant type containers are essentially performing type erasure. Type erasure is a pattern that hides the template parameter using composition and template functions (instead of template classes).

Here, we want to achieve similar functionality ourselves. This code snippet is origially from [here](https://www.cplusplus.com/articles/oz18T05o/).

Suppose you have a bunch of objects that belong together - why do they not derive from the same base class? I have no idea, but bear with me.
```cpp
struct Weapon {
   bool can_attack() const { return true; } // All weapons can do damage
};

struct Armor {
   bool can_attack() const { return false; } // Cannot attack with armor...
};

struct Helmet {
   bool can_attack() const { return false; } // Cannot attack with helmet...
};

struct Scroll {
   bool can_attack() const { return false; }
};

struct FireScroll {
   bool can_attack() const { return true; }
}

struct Potion {
   bool can_attack() const { return false; }  
};


struct PoisonPotion {
   bool can_attack() const { return true; }
};
```

Note that even though these classes are not derived from a common base, they do all implement the method `can_attack`. This looser-coupling can sometimes be bad - as you can imagine, when the code gets complicated, it might be difficult to figure out what needs to be implemented, or to tease out the hidden dependencies.

To make these things all fit into a standard container, we then need to do a bit of type erasure magic, aka a `Object` wrapper.

```cpp
class Object {

   struct ObjectConcept {   
       virtual ~ObjectConcept() {}
       virtual bool has_attack_concept() const = 0;
       virtual std::string name() const = 0;
   };

   template< typename T > struct ObjectModel : ObjectConcept {
       ObjectModel( const T& t ) : object( t ) {}
       virtual ~ObjectModel() {}
       virtual bool has_attack_concept() const
           { return object.can_attack(); }
       virtual std::string name() const
           { return typeid( object ).name; }
     private:
       T object;
   };

   std::shared_ptr<ObjectConcept> object;

  public:
   template< typename T > Object( const T& obj ) :
      object( new ObjectModel<T>( obj ) ) {}

   std::string name() const
      { return object->name(); }

   bool has_attack_concept() const
      { return object->has_attack_concept(); }
};
```

The `Object` wrapper holds a shared pointer to a `ObjectConcept`, which is just an abstract interface class that have templatized concrete derived classes for things that we want to model. `Object` class then implement a template constructor method to bind the shared pointer to a concrete instance of the `ObjectModel`

To use this wrapper, one simply calls the Object templatized constructor as follows:

```cpp
int main() {
   typedef std::vector< Object >    Backpack;
   Backpack backpack;

   backpack.push_back( Object( Weapon( SWORD ) ) );
   backpack.push_back( Object( Armor( CHAIN_MAIL ) ) );
   backpack.push_back( Object( Potion( HEALING ) ) );
   backpack.push_back( Object( Scroll( SLEEP ) ) );
   backpack.push_back( Object( FireScroll() ) );
   backpack.push_back( Object( PoisonPotion() ) );

   std::cout << "Items I can attack with:" << std::endl;
   for( auto item& : backpack)
       if( item->has_attack_concept() )
           std::cout << item->name();
}
```

What if you did not implement the method `can_attack` for certain items? Well.. nothing, as long as it is not called in the code. If it is, then you will get a compiler error.

## Thoughts

- Containers with unknown types has a lot of overhead (and rightly so), if we can avoid it, definitely do
- Custom type erasure implementation has a lot of overhead in both code complexity and performance. We should avoid them if possible.
- I prefer to use classic polymorphism solution if it's possible (i.e. if we do not need to make copy of the objects later, or need to know the derived type) -even then, we can use some [other tricks](https://stackoverflow.com/questions/39138770/get-objects-type-from-pointer-to-base-class-at-runtime) to figure this out.
- I would prefer `std::any` over any custom code for type erasure - there's just too many surfaces where things can go wrong
- for Library developers, one aspect of type erasure might be attractive -- it decouples the concrete implementation from the interface and allows greater freedom, which might be attractive when you do not have access to the complete codebase and its related libraries.