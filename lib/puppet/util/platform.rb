module Puppet
  module Util
    module Platform

      FIPS_STATUS_FILE = "/proc/sys/crypto/fips_enabled".freeze

      def windows?
        # Ruby only sets File::ALT_SEPARATOR on Windows and the Ruby standard
        # library uses that to test what platform it's on. In some places we
        # would use Puppet.features.microsoft_windows?, but this method can be
        # used to determine the behavior of the underlying system without
        # requiring features to be initialized and without side effect.
        !!File::ALT_SEPARATOR
      end
      module_function :windows?

      def default_paths
        return [] if windows?

        %w{/usr/sbin /sbin}
      end
      module_function :default_paths

      @fips_enabled = !windows? &&
                       File.exist?(FIPS_STATUS_FILE) &&
                       File.read(FIPS_STATUS_FILE, 1) == '1'

      def fips_enabled?
        @fips_enabled
      end
      module_function :fips_enabled?

      def self.jruby?
        RUBY_PLATFORM == 'java'
      end

      def jruby_fips?
        @@jruby_fips ||= if RUBY_PLATFORM == 'java'
                           require 'java'

                           begin
                             require 'openssl'
                             false
                           rescue LoadError, NameError
                             true
                           end
                         else
                           false
                         end
      end
      module_function :jruby_fips?
    end
  end
end
