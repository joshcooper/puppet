require 'pathname'
require 'puppet/util/rubygems'
require 'puppet/util/warnings'
require 'puppet/pops/adaptable'

# An adapter that ties the module_directories cache to the environment where the modules are parsed. This
# adapter ensures that the life-cycle of this cache doesn't exceed  the life-cycle of the environment.
#
# @api private
class Puppet::Util::ModuleDirectoriesAdapter < Puppet::Pops::Adaptable::Adapter
  attr_accessor :directories
end

# Autoload paths, either based on names or all at once.
class Puppet::Util::Autoload
  @loaded = {}

  class << self
    attr_accessor :loaded

    # @api private
    def gem_source
      @gem_source ||= Puppet::Util::RubyGems::Source.new
    end

    # @api private
    def loaded?(path)
      path = cleanpath(path).chomp('.rb')
      loaded.include?(path)
    end

    # Save the fact that a given path has been loaded.  This is so
    # we can load downloaded plugins if they've already been loaded
    # into memory.
    # @api private
    def mark_loaded(name, file)
      name = cleanpath(name).chomp('.rb')
      file = File.expand_path(file)
      $LOADED_FEATURES << file unless $LOADED_FEATURES.include?(file)
      loaded[name] = [file, File.mtime(file)]
    end

    # Return false if we've already loaded *name*, it still resolves
    # to the same absolute path, and the mtime of the file is unchanged
    # since it was loaded. Return true otherwise, such as if the file
    # was modified or deleted, or it resolves to a different file
    # because the search path changed, e.g. due to a newly pluginsynced
    # file.
    # @api private
    def changed?(name, env)
      name = cleanpath(name).chomp('.rb')
      return true unless loaded.include?(name)
      file, old_mtime = loaded[name]
      return true unless file == get_file(name, env)
      begin
        old_mtime.to_i != File.mtime(file).to_i
      rescue Errno::ENOENT
        true
      end
    end

    # Load a single plugin by name.  We use 'load' here so we can reload a
    # given plugin.
    #
    # @api private
    def load_file(name, env)
      file = get_file(name.to_s, env)
      return false unless file
      load_path(name, file)
    end

    # @api private
    def load_path(name, file)
      begin
        mark_loaded(name, file)
        Kernel.load file
        return true
      rescue SystemExit,NoMemoryError
        raise
      rescue Exception => detail
        message = _("Could not autoload %{name}: %{detail}") % { name: name, detail: detail }
        Puppet.log_exception(detail, message)
        raise Puppet::Error, message, detail.backtrace
      end
    end

    # @api private
    def loadall(path, env)
      # Load every instance of everything we can find.
      paths_to_load(path, env).each do |file|
        name = file.chomp(".rb")
        load_path(name, file) unless loaded?(name)
      end
    end

    # Reload all of the files that we've previously loaded.
    #
    # @param env [Puppet::Node::Environment] The environment whose modulepath to search
    # @api public
    def reload_changed(env)
      loaded.keys.each do |file|
        if changed?(file, env)
          load_file(file, env)
        end
      end
    end

    # Get the correct file to load for a given path
    # returns nil if no file is found
    # @api private
    def get_file(name, env)
      name = name + '.rb' unless name =~ /\.rb$/
      path = search_directories(env).find { |dir| Puppet::FileSystem.exist?(File.join(dir, name)) }
      path and File.join(path, name)
    end

    # @api private
    def paths_to_load(path, env)
      search_directories(env).map do |dir|
        files_in_dir(dir, path)
      end.flatten.uniq
    end

    # @api private
    def files_to_load(path, env)
      search_directories(env).map do |dir|
        dir = Pathname.new(dir)
        files_in_dir(dir, path).collect do |file|
          Pathname.new(file).relative_path_from(dir).to_s
        end
      end.flatten.uniq
    end

    # @api private
    def files_in_dir(dir, path)
      dir = File.expand_path(dir)
      Dir.glob(File.join(dir, path, "*.rb"))
    end

    # @api private
    def module_directories(env)
      raise ArgumentError, "Autoloader requires an environment" unless env

      # This is a little bit of a hack.  Basically, the autoloader is being
      # called indirectly during application bootstrapping when we do things
      # such as check "features".  However, during bootstrapping, we haven't
      # yet parsed all of the command line parameters nor the config files,
      # and thus we don't yet know with certainty what the module path is.
      # This should be irrelevant during bootstrapping, because anything that
      # we are attempting to load during bootstrapping should be something
      # that we ship with puppet, and thus the module path is irrelevant.
      #
      # In the long term, I think the way that we want to handle this is to
      # have the autoloader ignore the module path in all cases where it is
      # not specifically requested (e.g., by a constructor param or
      # something)... because there are very few cases where we should
      # actually be loading code from the module path.  However, until that
      # happens, we at least need a way to prevent the autoloader from
      # attempting to access the module path before it is initialized.  For
      # now we are accomplishing that by calling the
      # "app_defaults_initialized?" method on the main puppet Settings object.
      # --cprice 2012-03-16
      if Puppet.settings.app_defaults_initialized?
        # if the app defaults have been initialized then it should be safe to access the module path setting.
        Puppet::Util::ModuleDirectoriesAdapter.adapt(env) do |a|
          a.directories ||= env.modulepath.collect do |dir|
            Dir.entries(dir).reject { |f| f =~ /^\./ }.collect { |f| File.join(dir, f, "lib") }
          end.flatten.find_all do |d|
            FileTest.directory?(d)
          end
        end.directories
      else
        # if we get here, the app defaults have not been initialized, so we basically use an empty module path.
        []
      end
    end

    # @api private
    def libdirs
      # See the comments in #module_directories above.  Basically, we need to be careful not to try to access the
      # libdir before we know for sure that all of the settings have been initialized (e.g., during bootstrapping).
      if (Puppet.settings.app_defaults_initialized?)
        [Puppet[:libdir]]
      else
        []
      end
    end

    # @api private
    def vendored_modules
      dir = Puppet[:vendormoduledir]
      if dir && File.directory?(dir)
        Dir.entries(dir)
          .reject { |f| f =~ /^\./ }
          .collect { |f| File.join(dir, f, "lib") }
          .find_all { |d| FileTest.directory?(d) }
      else
        []
      end
    end

    # @api private
    def gem_directories
      gem_source.directories
    end

    # @api private
    def search_directories(env)
      [gem_directories, module_directories(env), libdirs, $LOAD_PATH, vendored_modules].flatten
    end

    # Normalize a path. This converts ALT_SEPARATOR to SEPARATOR on Windows
    # and eliminates unnecessary parts of a path.
    #
    # @api public
    def cleanpath(path)
      Pathname.new(path).cleanpath.to_s
    end
  end

  attr_accessor :object, :path

  def initialize(obj, path)
    @path = path.to_s
    raise ArgumentError, _("Autoload paths cannot be fully qualified") if Puppet::Util.absolute_path?(@path)
    @object = obj
  end

  # Require a file based on the Autoload#path namespace.
  #
  # @api public
  def require(name)
    Kernel.require expand(name)
  end

  # Load a file based on the Autoload#path namespace.
  # @api public
  def load(name, env)
    self.class.load_file(expand(name), env)
  end

  # Load all instances of a plugin in this autoloader's namespace. For example,
  # if we have created a Puppet::Util::Autoload for Puppet::Type::User with a
  # path of 'puppet/provider/user', the search_directories path will be searched
  # for all ruby files matching puppet/provider/user/*.rb and they will then be
  # loaded from the first directory in the search path providing them. So
  # earlier entries in the search path may shadow later entries. This uses load,
  # rather than require, so that already loaded files can be reloaded if they've
  # changed.
  #
  # @api public
  def loadall(env)
    self.class.loadall(@path, env)
  end

  # Returns true if *name* has been loaded by *any* autoloader, though
  # so long as each autoloader has a unique namespace, then it returns
  # true if it was loaded by *this* autoloader.
  #
  # @api public
  def loaded?(name)
    self.class.loaded?(expand(name))
  end

  def changed?(name, env)
    self.class.changed?(expand(name), env)
  end

  # Returns an array of relative paths that this autoload could load based on
  # its *path* namespace and the specified environment. For example, if *path*
  # is "puppet/application", then this returns an array of the form
  # "puppet/application/agent", etc. The array does not contain duplicates. The
  # autoloader will return the first entry it finds.
  #
  # @param env [Puppet::Node::Environment] The environment whose modulepath to search
  # @return Array[String] An array of relative paths.
  # @api public
  def files_to_load(env)
    self.class.files_to_load(@path, env)
  end

  # @api private
  def expand(name)
    ::File.join(@path, name.to_s)
  end
end
