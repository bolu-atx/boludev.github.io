---
layout: post
title:  "Type Erasure vs Polymorphism"
date:   2020-06-15 15:06:06 -0700
categories: cpp pattern
---

C++ templates are useful constructs to reduce code bloat (I think of them as fancy copy and paste) without any performance overhead at run-time.
However, to use them effectively might require some practice.
One issue I recently ran into while working with templates is the following:

Suppose I have a generic class `Foo<T>` that takes a template argument, I need to place `Foo<T>` in a container to be iterated upon or to be looked up later.  However, I might have multiple instantiations of `Foo<T>` of different types (i.e. `int, float, double, bool`), this makes it hard to use STL containers since these containers require the elements to be of a single type.

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

Note that these objects are not derived from a common base class, but they do need to have the same method signature. This looser-coupling is not really better/worse than inheritance. It's really up to the programmer. 

The type erasure magic happens here - in this `Object` container.

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

   boost::shared_ptr<ObjectConcept> object;

  public:
   template< typename T > Object( const T& obj ) :
      object( new ObjectModel<T>( obj ) ) {}

   std::string name() const
      { return object->name(); }

   bool has_attack_concept() const
      { return object->has_attack_concept(); }
};
```

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