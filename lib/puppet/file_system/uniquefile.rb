# frozen_string_literal: true

require 'English'
require_relative '../../puppet/file_system'
require 'delegate'
require 'tmpdir'

# A class that provides `Tempfile`-like capabilities, but does not attempt to
# manage the deletion of the file for you.  API is identical to the
# normal `Tempfile` class.
#
# @api public
class Puppet::FileSystem::Uniquefile < DelegateClass(File)
  # Convenience method which ensures that the file is closed and
  # unlinked before returning
  #
  # @param identifier [String] additional part of generated pathname
  # @yieldparam file [File] the temporary file object
  # @return result of the passed block
  # @api private
  def self.open_tmp(identifier)
    f = new(identifier)
    yield f
  ensure
    if f
      f.close!
    end
  end

  def initialize(basename, tmpdir = nil, mode: 0)
    @mode = mode | File::RDWR | File::CREAT | File::EXCL

    Dir::Tmpname.create(basename, tmpdir) do |tmpname, _n, opts|
      opts[:perm] = 0o600
      self.class.locking(tmpname) do
        @tmpfile = File.open(tmpname, @mode, **opts)
        @tmpname = tmpname
      end
      @opts = opts.freeze
    end

    super(@tmpfile)
  end

  # Opens or reopens the file with mode "r+".
  def open
    _close
    mode = @mode & ~(File::CREAT | File::EXCL)
    @tmpfile = File.open(@tmpname, mode, **@opts)
  end

  def _close
    @tmpfile.close if @tmpfile
  ensure
    @tmpfile = nil
  end
  protected :_close

  def close(unlink_now = false)
    if unlink_now
      close!
    else
      _close
    end
  end

  def close!
    _close
    unlink
  end

  def unlink
    return unless @tmpname

    begin
      File.unlink(@tmpname)
    rescue Errno::ENOENT
    rescue Errno::EACCES
      # may not be able to unlink on Windows; just ignore
      return
    end
    @tmpname = nil
  end
  alias delete unlink

  # Returns the full path name of the temporary file.
  # This will be nil if #unlink has been called.
  def path
    @tmpname
  end

  @@systmpdir ||= defined?(Etc.systmpdir) ? Etc.systmpdir : '/tmp'

  class << self
    # yields with locking for +tmpname+ and returns the result of the
    # block.
    def locking(tmpname)
      lock = tmpname + '.lock'
      mkdir(lock)
      yield
    rescue Errno::ENOENT => e
      ex = Errno::ENOENT.new("A directory component in #{lock} does not exist or is a dangling symbolic link")
      ex.set_backtrace(e.backtrace)
      raise ex
    ensure
      rmdir(lock) if Puppet::FileSystem.exist?(lock)
    end

    def mkdir(*args)
      Dir.mkdir(*args)
    end

    def rmdir(*args)
      Dir.rmdir(*args)
    end
  end
end
