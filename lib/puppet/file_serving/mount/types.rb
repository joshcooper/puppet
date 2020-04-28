require 'puppet/file_serving/mount'

# Find files in the modules' locales directories.
# This is a very strange mount because it merges
# many directories into one.
class Puppet::FileServing::Mount::Types < Puppet::FileServing::Mount
  # Return an instance of the appropriate class.
  def find(relative_path, request)
    mod = request.environment.modules.find { |m|  m.type(relative_path) }
    return nil unless mod

    path = mod.type(relative_path)

    path
  end

  def search(relative_path, request)
    # We currently only support one kind of search on types - return
    # them all.
    Puppet.debug("Warning: calling Types.search with empty module path.") if request.environment.modules.empty?
    paths = request.environment.modules.find_all { |mod| mod.types? }.collect { |mod| mod.type_directory }
    if paths.empty?
      # If the modulepath is valid then we still need to return a valid root
      # directory for the search, but make sure nothing inside it is
      # returned.
      request.options[:recurse] = false
      request.environment.modulepath.empty? ? nil : request.environment.modulepath
    else
      paths.each do |path|
        Puppet.notice("PATH #{path}")
      end

      paths
    end
  end

  def valid?
    true
  end
end
