require 'puppet/property'

# This property is automatically added to any {Puppet::Type} that responds
# to the methods 'exists?', 'create', and 'destroy'.
#
# Ensure defaults to having the wanted _(should)_ value `:present`.
#
# @api public
#
class Puppet::Property::Ensure < Puppet::Property
  @name = :ensure

  def self.defaultvalues
    newvalue(:present) do
      if @resource.provider && @resource.provider.respond_to?(:create)
        @resource.provider.create
      else
        @resource.create
      end
      nil # return nil so the event is autogenerated
    end

    newvalue(:absent) do
      if @resource.provider && @resource.provider.respond_to?(:destroy)
        @resource.provider.destroy
      else
        @resource.destroy
      end
      nil # return nil so the event is autogenerated
    end

    defaultto do
      if @resource.managed?
        :present
      else
        nil
      end
    end

    # This doc will probably get overridden
    @doc ||= "The basic property that the resource should be in."
  end

  def self.inherited(sub)
    # Add in the two properties that everyone will have.
    sub.class_eval do
    end
  end

  def change_to_s(currentvalue, newvalue)
    begin
      if currentvalue == :absent || currentvalue.nil?
        return _("created")
      elsif newvalue == :absent
        return _("removed")
      else
        return _('%{name} changed %{is} to %{should}') % { name: name, is: is_to_s(currentvalue), should: should_to_s(newvalue) }
      end
    rescue Puppet::Error, Puppet::DevError
      raise
    rescue => detail
      raise Puppet::DevError, _("Could not convert change %{name} to string: %{detail}") % { name: self.name, detail: detail }, detail.backtrace
    end
  end

  # Retrieves the _is_ value for the ensure property.
  # The existence of the resource is checked by first consulting the provider (if it responds to
  # `:exists`), and secondly the resource. A a value of `:present` or `:absent` is returned
  # depending on if the managed entity exists or not.
  #
  # @return [Symbol] a value of `:present` or `:absent` depending on if it exists or not
  # @raise [Puppet::DevError] if neither the provider nor the resource responds to `:exists`
  #
  def retrieve
    # XXX This is a problem -- whether the object exists or not often
    # depends on the results of other properties, yet we're the first property
    # to get checked, which means that those other properties do not have
    # @is values set.  This seems to be the source of quite a few bugs,
    # although they're mostly logging bugs, not functional ones.
    if (prov = @resource.provider) && prov.respond_to?(:exists?)
      result = prov.exists?
    elsif @resource.respond_to?(:exists?)
      result = @resource.exists?
    else
      raise Puppet::DevError, _("No ability to determine if %{name} exists") % { name: @resource.class.name }
    end
    if result
      return :present
    else
      return :absent
    end
  end

  # If they're talking about the thing at all, they generally want to
  # say it should exist.
  #defaultto :present
  defaultto do
    if @resource.managed?
      :present
    else
      nil
    end
  end
end

