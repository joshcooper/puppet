# frozen_string_literal: true

require 'puppet/util/feature'

if Puppet::Util::Platform.windows?
  Puppet.features.add(:eventlog)
end
