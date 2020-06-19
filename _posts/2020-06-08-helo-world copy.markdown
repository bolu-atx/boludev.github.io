---
layout: post
title:  "Type Erasure vs Polymorphism"
date:   2020-06-15 15:06:06 -0700
categories: cpp pattern
---

## The Problem
C++ templates are useful constructs to reduce code bloat (I think of them as fancy copy and paste) without any performance overhead at run-time.
However, to use them effectively might require some practice.
One issue I recently ran into while working with templates is the following:

Suppose I have a generic class `Foo<T>` that takes a template argument, I need to place `Foo<T>` in a container to extend its lifetime. 

However, there are multiple instantiations of `Foo<T>` of different template argument types (i.e. `int, float, double, bool`). This is a non-trivial problem without resorting to external libraries.

After scouring the internet, I found that cplusplus.com article here (https://www.cplusplus.com/articles/oz18T05o/) was really insightful. I decided to update this article for my own interpretation.

## Classic Inheritence Approach

We can make the `Foo<T>` class a derived class of `IFoo`, a non-templated, abstract class, and then make all the methods of `Foo` virtual.

```
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
```

Now, we can store a collection of `Foo<T>` in a container

## Type Erasure

Type erasure is a pattern that hides the template parameter using composition and template functions (instead of template classes).

```
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

int main() {
   typedef std::vector< Object >    Backpack;
   typedef Backpack::const_iterator BackpackIter;

   Backpack backpack;

   backpack.push_back( Object( Weapon( SWORD ) ) );
   backpack.push_back( Object( Armor( CHAIN_MAIL ) ) );
   backpack.push_back( Object( Potion( HEALING ) ) );
   backpack.push_back( Object( Scroll( SLEEP ) ) );
   backpack.push_back( Object( FireScroll() ) );
   backpack.push_back( Object( PoisonPotion() ) );

   std::cout << "Items I can attack with:" << std::endl;
   for( BackpackIter item = backpack.begin(); item != backpack.end(); ++item )
       if( item->has_attack_concept() )
           std::cout << item->name();
}
```