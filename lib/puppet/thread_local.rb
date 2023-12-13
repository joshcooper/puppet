# frozen_string_literal: true

if ENV['PUPPET_MT']
  require 'concurrent'
  class Puppet::ThreadLocal < Concurrent::ThreadLocalVar; end
else
  # this is mostly copied from concurrent-ruby's ThreadLocalVar except for the
  # thread local part
  class Puppet::ThreadLocal
    def initialize(default = nil, &default_block)
      if default && block_given?
        raise ArgumentError, "Cannot use both value and block as default value"
      end

      if block_given?
        @default_block = default_block
        @default = nil
      else
        @default_block = nil
        @default = default
      end
    end

    def value
      unless defined?(@value)
        if @default_block
          @value = @default_block.call
        else
          @value = @default
        end
      end
      @value
    end

    def value=(value)
      @value = value
    end

    def bind(value)
      if block_given?
        old_value = self.value
        self.value = value
        begin
          yield
        ensure
          self.value = old_value
        end
      end
    end
  end
end
