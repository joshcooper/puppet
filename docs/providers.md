# Types & Providers

Puppet resource types describe the "shape" of a resource. For example, `file`
resources have an `owner`, `group` and `mode`. Puppet resource providers are
responsible for getting the current state and setting the desired state, if the
two don't match.

## Definition

A resource type is defined using puppet's DSL. Here is a simple example that
starts with the most basic example, and builds up from there:

```ruby
Puppet::Type.newtype(:abc)
```

This defines a new class `Puppet::Type::Abc` that extends puppet's
`Puppet::Type` base class and registers the type.

In order to retrieve a resource type, you can call:

```ruby
Puppet::Type.type(:abc)
```

If the type has not been loaded, then puppet will search its load path to try to
load the type.

## Identity

Every resource that puppet manages must have a unique identity. For example,
`file` resources are uniquely identified by their `path`. In puppet source code,
this is referred to as the namevar. Some resources may require multiple
attributes to be uniquely identified, which is referred to as *composite
namevars*. So continuing our example, we can define a namevar as:

```ruby
Puppet::Type.newtype(:abc) do
  newparam(:name, namevar: true)
end
```

Here we've defined a resource type with a `name` parameter. Behind the scenes,
puppet metaprograms a new class `Puppet::Type::Abc::ParameterName` that extends puppet's
base class `Puppet::Parameter`.

## Ensurable

The first step when managing a resource is to ensure it exists, or is absent.
This can be done as:

```ruby
Puppet::Type.newtype(:abc) do
  newparam(:name, namevar: true)
  ensurable
end
```

The `ensurable` statement metaprograms a new class `Puppet::Type::Abc::Ensure`
that extends puppet's `Puppet::Property::Ensure` base class. By default, the type
accepts two values `present` and `absent`. So for example in manifest you can
write:

```puppet
abc { 'example':
  ensure => present
}
```

It's also possible to allow other values by passing a block to `ensurable`, like
the `package` type does:

```ruby
ensurable do
  newvalue(:held)
  newvalue(:latest)
  newvalue(:purged)
end
```
## Properties

Next suppose we need to manage the `description` for the resource. We can do
that using the `newproperty` DSL method:

```ruby
Puppet::Type.newtype(:abc) do
  newparam(:name, namevar: true)
  ensurable
  newproperty(:description)
end
```

This metaprograms a new class `Puppet::Type::Abc::Description` that extends
puppet's `Puppet::Property` base class.

## Parameters

Notice that `name` was defined using `newparam` while `description` was defined
using `newproperty`. Properties are resource attributes that puppet can manage,
like a file's `mode`. However, the name of a resource is a parameter. Parameters
are also used in cases where you need to specify additional information about
**how** puppet should manage a resource, such as the `source` of a package, the
`cwd` for an `exec`, whether to append a group to the `user` resource, etc.
## Lifecycle
### Instances
### Pre
### Post
### Flush
### Munging
### Validation
## Suitability
## Features
## Sensitive
## Documentation
