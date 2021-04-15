Puppet::Type.type(:file).provide(:posix2) do
  include Puppet::Util::Checksums

  mk_resource_methods

  CREATORS = [:content, :source, :target]

  def validate
    count = CREATORS.map { |param| resource[param] ? 1 : 0 }.sum
    self.fail _("You cannot specify more than one of %{creators}") % { creators: CREATORS.collect { |p| p.to_s}.join(", ") } if count > 1

    # REMIND more validation
  end

  def retrieve
    @current = retrieve_stat

    case @current[:ensure]
    when :file
      if resource[:content] || resource[:source]
        @current[:checksum] = resource[:checksum] || Puppet[:digest_algorithm]
        @current[:checksum_value] = send("#{@current[:checksum]}_file", resource[:path])
      end

      if resource[:content]
        # desired checksum isn't typically set when using content
        resource[:checksum] ||= @current[:checksum]
        resource[:checksum_value] ||= send(@current[:checksum], resource[:content])
      elsif resource[:source]
        raise "Managing by source is not supported yet"
      end
    end

    # set @property_hash so transaction can figure out which properties are out of sync
    set(@current)

    @current
  end

  def checksum_value=(value)
    @checksum_value = value
    @needs_write = true
  end

  # def exists?
  #   require 'byebug'; byebug
  #   @current[:ensure] != :absent
  # end

  def flush
    desired = resource.to_hash
    path = desired[:path]

    # REMIND link
    # REMIND force
    # REMIND backup
    # REMIND mode
    # REMIND source
    # REMIND present implies link

    # REMIND: Implicit ensure
    # if desired[:ensure].nil?
    #   if desired[:target]
    #     desired[:ensure] = :link
    #   elsif desired[:content]
    #     desired[:ensure] = :file
    #   end
    # end

    # current value is never present, but desired can be
    case @current[:ensure]
    when :directory
      case desired[:ensure]
      when :directory
        # REMIND: change mode
      when :file
        FileUtils.rmtree(path) # REMIND: only if force?
        write_file
      when :absent
        FileUtils.rmtree(path) # REMIND: only if force?
      else
        raise "Can't convert directory to #{desired[:ensure]}"
      end
    when :file
      case desired[:ensure]
      when :file
        write_file if @needs_write
      when :directory
        Puppet::FileSystem.unlink(path)
        mkdir
      when :absent
        FileUtils.rmtree(path)
      else
        fail "Can't convert file to #{desired[:ensure]}"
      end
    when :absent
      case desired[:ensure]
      when :directory
        mkdir
      when :file
        write_file
      else
        fail "Can't convert absent to #{desired[:ensure]}"
      end
    else
      fail "Can't convert from #{@current[:ensure]}"
    end
  end

  private

  def retrieve_stat
    stat = if resource[:links] == :manage
             Puppet::FileSystem.lstat(resource[:path])
           else
             Puppet::FileSystem.stat(resource[:path])
           end

    params = {
      path: resource[:path],
      owner: stat.uid.to_s, # REMIND: canonicalize owner
      group: stat.gid.to_s, # REMIND: canonicalize group
      mode: stat.mode.to_s(8), # REMIND: canonicalize mode
      mtime: stat.mtime,
      ctime: stat.ctime
    }

    case stat.ftype
    when 'directory'
      params[:ensure] = :directory
    when 'file'
      params[:ensure] = :file
    else
      # REMIND: fifo, socket, blockSpecial, characterSpecial, unknown
      fail "Unknown file type #{stat.ftype}"
    end

    params
  rescue Errno::ENOENT, Errno::ENOTDIR
    { ensure: :absent }
  rescue Errno::EACCES
    warning _("Could not stat; permission denied")
    { ensure: :absent }
  end

  def mkdir
    path = resource[:path]
    Dir.mkdir(path)
  rescue Errno::ENOTDIR
    parent = File.dirname(path)
    raise Puppet::Error, "Cannot create #{path}; parent directory #{parent} does not exist"
  end

  def write_file
    Puppet::FileSystem.open(resource[:path], resource[:mode], 'wb') do |f|
      f.write(resource[:content])
    end
  end
end

module Puppet
  class Type
    class File
      class ProviderPosix2
        class Source
          include Puppet::Util::Checksums

          attr_reader :checksum_type

          def initialize(resource)
            @checksum_type = resource[:checksum] || Puppet[:digest_algorithm]
          end
        end

        class ContentSource < Source
          attr_reader :checksum_value, :content

          def initialize(resource)
            super

            @checksum_value, @content = checksum_stream(resource[:path])
          end

          private

          def checksum_stream(path)
            # REMIND need to select digest based on checksum_type
            raise "Not implemented yet #{@checksum_type}" if @checksum_type != 'md5'

            # Existing Checksums module doesn't support returning both
            digest = Digest::MD5.new
            buf = StringIO.new
            Puppet::FileSystem.open(path, nil, 'rb') do |f|
              while chunk = f.read(8 * 1024)
                digest.update(chunk)
                buf.write(chunk)
              end
            end

            [digest.hexdigest, buf.string]
          end
        end
      end
    end
  end
end

