# frozen_string_literal: true

Puppet::Type.type(:file).provide :posix do
  desc "Uses POSIX functionality to manage file ownership and permissions."

  confine :feature => :posix
  has_features :manages_symlinks

  include Puppet::Util::POSIX
  include Puppet::Util::Warnings

  require 'etc'
  require_relative '../../../puppet/util/selinux'

  class << self
    def selinux_mounts
      @selinux_mounts ||= {}
    end

    def selinux_handle
      return nil unless Puppet::Util::SELinux.selinux_support?

      # selabel_open takes 3 args: backend, options, and nopt. The backend param
      # is a constant, SELABEL_CTX_FILE, which happens to be 0. Since options is
      # nil, nopt can be 0 since nopt represents the # of options specified.
      @selinux_handle ||= Selinux.selabel_open(Selinux::SELABEL_CTX_FILE, nil, 0)
    end

    def post_resource_eval
      @selinux_mounts = nil

      if @selinux_handle
        Selinux.selabel_close(@selinux_handle)
        @selinux_handle = nil
      end
    end
  end

  def uid2name(id)
    return id.to_s if id.is_a?(Symbol) or id.is_a?(String)
    return nil if id > Puppet[:maximum_uid].to_i

    begin
      user = Etc.getpwuid(id)
    rescue TypeError, ArgumentError
      return nil
    end

    if user.uid == ""
      nil
    else
      user.name
    end
  end

  # Determine if the user is valid, and if so, return the UID
  def name2uid(value)
    Integer(value)
  rescue
    uid(value) || false
  end

  def gid2name(id)
    return id.to_s if id.is_a?(Symbol) or id.is_a?(String)
    return nil if id > Puppet[:maximum_uid].to_i

    begin
      group = Etc.getgrgid(id)
    rescue TypeError, ArgumentError
      return nil
    end

    if group.gid == ""
      nil
    else
      group.name
    end
  end

  def name2gid(value)
    Integer(value)
  rescue
    gid(value) || false
  end

  def owner
    stat = resource.stat
    unless stat
      return :absent
    end

    currentvalue = stat.uid

    # On OS X, files that are owned by -2 get returned as really
    # large UIDs instead of negative ones.  This isn't a Ruby bug,
    # it's an OS X bug, since it shows up in perl, too.
    if currentvalue > Puppet[:maximum_uid].to_i
      warning _("Apparently using negative UID (%{currentvalue}) on a platform that does not consistently handle them") % { currentvalue: currentvalue }
      currentvalue = :silly
    end

    currentvalue
  end

  def owner=(should)
    # Set our method appropriately, depending on links.
    if resource[:links] == :manage
      method = :lchown
    else
      method = :chown
    end

    begin
      File.send(method, should, nil, resource[:path])
    rescue => detail
      raise Puppet::Error, _("Failed to set owner to '%{should}': %{detail}") % { should: should, detail: detail }, detail.backtrace
    end
  end

  def group
    stat = resource.stat
    return :absent unless stat

    currentvalue = stat.gid

    # On OS X, files that are owned by -2 get returned as really
    # large GIDs instead of negative ones.  This isn't a Ruby bug,
    # it's an OS X bug, since it shows up in perl, too.
    if currentvalue > Puppet[:maximum_uid].to_i
      warning _("Apparently using negative GID (%{currentvalue}) on a platform that does not consistently handle them") % { currentvalue: currentvalue }
      currentvalue = :silly
    end

    currentvalue
  end

  def group=(should)
    # Set our method appropriately, depending on links.
    if resource[:links] == :manage
      method = :lchown
    else
      method = :chown
    end

    begin
      File.send(method, nil, should, resource[:path])
    rescue => detail
      raise Puppet::Error, _("Failed to set group to '%{should}': %{detail}") % { should: should, detail: detail }, detail.backtrace
    end
  end

  def mode
    stat = resource.stat
    if stat
      (stat.mode & 0o07777).to_s(8).rjust(4, '0')
    else
      :absent
    end
  end

  def mode=(value)
    File.chmod(value.to_i(8), resource[:path])
  rescue => detail
    error = Puppet::Error.new(_("failed to set mode %{mode} on %{path}: %{message}") % { mode: mode, path: resource[:path], message: detail.message })
    error.set_backtrace detail.backtrace
    raise error
  end
end
