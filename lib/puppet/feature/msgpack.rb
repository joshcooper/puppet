# frozen_string_literal: true

require 'puppet/util/feature'

Puppet.features.add(:msgpack, :libs => ["msgpack"])
