# frozen_string_literal: true
module Puppet
  module Concurrent
    module ThreadLocalSingleton
      if ENV['PUPPET_MT']
        def singleton
          key = (name + ".singleton").intern
          thread = Thread.current
          value = thread.thread_variable_get(key)
          if value.nil?
            value = new
            thread.thread_variable_set(key, value)
          end
          value
        end
      else
        def singleton
          @singleton__instance__ ||= new
        end
      end
    end
  end
end
