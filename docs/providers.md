# Resource Types & Providers

Puppet resource types describe the "shape" of a resource. For example, `file`
resources have an `owner`, `group` and `mode`.

Puppet resource providers are responsible for getting and setting the state of
the resource. A resource type should have at least one provider. Some resource
types have multiple providers, though that is less common.

Both types and providers are defined using puppet's DSL. This document describes
the type and provider DSL in more detail.

## Type Definition

A resource type is defined by calling the `Puppet::Type.newtype` DSL method
passing the name of the type. Here is a simple example. The name of the type is
`:abc` and it must be saved in the file `lib/puppet/type/abc.rb`. The name of
the type must be unique across all types.

```ruby
Puppet::Type.newtype(:abc) do
  # TODO: add type definition here
end
```

Puppet makes extensive use of metaprogramming, which just means new classes are
defined at runtime. For example, the above definition defines a new class
`Puppet::Type::Abc` that extends the `Puppet::Type` base class and registers the
type.

In order to retrieve a resource type, you can call:

```ruby
clazz = Puppet::Type.type(:abc)
```

## Provider Definition

Every resource type should have a corresponding provider that can manage the
desired state of the resource on the system.

The DSL methods for defining a provider are similar to that of a type. Here we
define a provider named `ruby` for the type `abc`. It must be saved in the file
`lib/puppet/provider/abc/ruby.rb`:

```
Puppet::Type.type(:abc).provide(:ruby) do
  # TODO: add provider definition here
end
```

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
puppet metaprograms a new class `Puppet::Type::Abc::ParameterName` that extends
puppet's base class `Puppet::Parameter`.

Instead of passing `namevar` as an option, you can call the block form of
`newparam` and call `isnamevar` inside of the block:

```ruby
Puppet::Type.newtype(:abc) do
  newparam(:name) do
    isnamevar
  end
end
```

## Ensurable

The first step to managing a resource is to ensure it exists or is absent. This
can be done as:

```ruby
Puppet::Type.newtype(:abc) do
  newparam(:name, namevar: true)
  ensurable
end
```

The `ensurable` DSL method metaprograms a new class `Puppet::Type::Abc::Ensure`
that extends puppet's `Puppet::Property::Ensure` base class. In order to
function, you'll need to implement `exists?`, `create` and `delete` in
your provider:

```ruby
Puppet::Type.type(:abc).provide(:ruby) do
  def exists?
    # TODO: return true if the resource exists
  end

  def create
    # TODO: create resource
  end

  def destroy
    # TODO: destroy resource
  end
end
```

## Properties

Suppose we need to manage the `description` for the resource. First we add `description` to the type
using the `newproperty` DSL method:

```ruby
Puppet::Type.newtype(:abc) do
  newparam(:name, namevar: true)
  ensurable
  newproperty(:description)
end
```

This metaprograms a new class `Puppet::Type::Abc::Description` that extends
puppet's `Puppet::Property` base class.

Next, we add getter and setters to the provider to get the current state and set
the desired state:

```ruby
Puppet::Type.type(:abc).provide(:ruby) do
  def description
    # TODO: return current state of @resource[:name]
  end

  def description=(value)
    # TODO: set current state of @resource[:name]
  end
end
```

Notice the `name` parameter was defined using `newparam`, whereas `description`
was defined `newproperty`. Although `property` and `parameter` sound synonymous,
they have different meanings.

A parameter contains information about how to manage a resource, whereas a
property contains the desired state of the resource. For example, the `owner`
property for a `file` defines its desired state, so it is a property. However,
the `source` parameter for a `package` defines where to download the package
from if the desired state doesn't match the current state, so it is a parameter.

## Provider Lifecycle

Providers are responsible for retrieving the current state of each resource. If
the current state doesn't match the desired state, then the provider is
responsible for setting the state.

### Instances

In cases where it makes sense to enumerate the instances of a resource, the
provider should implement an `instances` class method. The method should return
an Array of provider instances, where each instance corresponds to a different
resource. For example, the `user` provider returns one provider instance per
user on the system.

```ruby
Puppet::Type.type(:user).provide(...) do
  def self.instances
    users.map do |user|
      new(name: user[:name], ensure: :present)
    end
  end
end
```

The `instance` method is called when running `puppet resource <type>`

### Pre

Puppet creates one `Puppet::Type::<type>` object and its corresponding
`Puppet::Provider::<type>::<name>` object per managed resource. However
sometimes it is necessary to initialize provider state once, rather than once
per resource. For example, to create an SELinux context, open an HTTP
connection, etc. This can be done using the `pre_run_check` method:

```ruby
Puppet::Type.type(:abc).provide(:ruby) do
  def self.pre_run_check
    # TODO: create SELinux context, connect to HTTP server, etc
  end
end
```

### Post

Similarly, a provider can cleanup state by implementing the `post_resource_eval`
method:

```ruby
Puppet::Type.type(:abc).provide(:ruby) do
  def self.post_resource_eval
    # TODO: cleanup
  end
end
```

### Flush

If a resource has properties that are independent, for example the `owner`,
`group` and `mode` for posix files can be set independently. In that case, you
can define a getter and setter for each property, and in the setter call the
appropriate method to set the desired state for just that property. So in our
description case, we could do:

```ruby
Puppet::Type.type(:abc).provide(:ruby) do
  def description=(value)
    # TODO: update the resource with the new description
  end
end
```

However, in cases where properties cannot be set independently, you'll want to
define setters for each property and implement a `flush` method to set the
desired state of the resource. For example, suppose the resource's description
and label both needed to be set at the same time. So we can do that in the
`flush` method:

```ruby
Puppet::Type.type(:abc).provide(:ruby) do
  def description=(value)
    @property_hash[:description] = value
  end

  def label=(value)
    @property_hash[:label] = value
  end

  def flush
    # TODO: save the entire @property_hash
  end
end
```

Defining getters and setters in the provider is so common that the
`mk_resource_methods` will metaprogram them for you:

```ruby
Puppet::Type.type(:abc).provide(:ruby) do
  mk_resource_methods

  def flush
    # TODO: save the entire @property_hash
  end
end
```

### Munging
### Validation
## Suitability
## Features
## Sensitive
## Documentation

## Advanced

It's also possible to allow other values by passing a block to `ensurable`, like
the `package` type does:

```ruby
ensurable do
  newvalue(:held)
  newvalue(:latest)
  newvalue(:purged)
end
```
