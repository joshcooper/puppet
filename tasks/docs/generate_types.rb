require 'puppet'
require 'json'

# Strip indentation and trailing whitespace from embedded doc fragments.
#
# Multi-line doc fragments are sometimes indented in order to preserve the
# formatting of the code they're embedded in. Since indents are syntactic
# elements in Markdown, we need to make sure we remove any indent that was
# added solely to preserve surrounding code formatting, but LEAVE any indent
# that delineates a Markdown element (code blocks, multi-line bulleted list
# items). We can do this by removing the *least common indent* from each line.
#
# Least common indent is defined as follows:
#
# * Find the smallest amount of leading space on any line...
# * ...excluding the first line (which may have zero indent without affecting
#   the common indent)...
# * ...and excluding lines that consist solely of whitespace.
# * The least common indent may be a zero-length string, if the fragment is
#   not indented to match code.
# * If there are hard tabs for some dumb reason, we assume they're at least
#   consistent within this doc fragment.
#
# See tests in spec/unit/util/docs_spec.rb for examples.
def scrub(text)
  # One-liners are easy! (One-liners may be buffered with extra newlines.)
  return text.strip if text.strip !~ /\n/
  excluding_first_line = text.partition("\n").last
  indent = excluding_first_line.scan(/^[ \t]*(?=\S)/).min || '' # prevent nil
  # Clean hanging indent, if any
  if indent.length > 0
    text = text.gsub(/^#{indent}/, '')
  end
  # Clean trailing space
  text.lines.map{|line|line.rstrip}.join("\n").rstrip
end

typedocs = {}
Puppet.initialize_settings
Puppet::Type.loadall
Puppet::Type.eachtype { |type|
  # List of types to ignore:
  next if type.name == :puppet
  next if type.name == :component
  next if type.name == :whit

  # Initialize the documentation object for this type
  docobject = {
    :description => scrub(type.doc),
    :attributes  => {}
  }

  # Handle features:
  # inject will return empty hash if type.features is empty.
  docobject[:features] = type.features.inject( {} ) { |allfeatures, name|
    allfeatures[name] = scrub( type.provider_feature(name).docs )
    allfeatures
  }

  # Handle providers:
  # inject will return empty hash if type.providers is empty.
  docobject[:providers] = type.providers.inject( {} ) { |allproviders, name|
    allproviders[name] = {
      :description => scrub( type.provider(name).doc ),
      :features    => type.provider(name).features
    }
    allproviders
  }

  # Override several features missing due to bug #18426:
  if type.name == :user
    docobject[:providers][:useradd][:features] << :manages_passwords << :manages_password_age << :libuser
    if docobject[:providers][:openbsd]
      docobject[:providers][:openbsd][:features] << :manages_passwords << :manages_loginclass
    end
  end
  if type.name == :group
    docobject[:providers][:groupadd][:features] << :libuser
  end


  # Handle properties:
  docobject[:attributes].merge!(
    type.validproperties.inject( {} ) { |allproperties, name|
      property = type.propertybyname(name)
      raise "Could not retrieve property #{propertyname} on type #{type.name}" unless property
      description = property.doc
      $stderr.puts "No docs for property #{name} of #{type.name}" unless description and !description.empty?

      allproperties[name] = {
        :description => scrub(description),
        :kind        => :property,
        :namevar     => false # Properties can't be namevars.
      }
      allproperties
    }
  )

  # Handle parameters:
  docobject[:attributes].merge!(
    type.parameters.inject( {} ) { |allparameters, name|
      description = type.paramdoc(name)
      $stderr.puts "No docs for parameter #{name} of #{type.name}" unless description and !description.empty?

      # Strip off the too-huge provider list. The question of what to do about
      # providers is a decision for the formatter, not the fragment collector.
      description = description.split('Available providers are')[0] if name == :provider

      allparameters[name] = {
        :description => scrub(description),
        :kind        => :parameter,
        :namevar     => type.key_attributes.include?(name) # returns a boolean
      }
      allparameters
    }
  )

  # Finally:
  typedocs[type.name] = docobject
}

print JSON.dump(typedocs)
