# frozen_string_literal: true

require 'puppet/application'

class Puppet::Application::Filebucket < Puppet::Application

  option("--bucket BUCKET","-b")
  option("--debug","-d")
  option("--fromdate FROMDATE","-f")
  option("--todate TODATE","-t")
  option("--local","-l")
  option("--remote","-r")
  option("--verbose","-v")

  attr :args

  def summary
    _("Store and retrieve files in a filebucket")
  end

  def help
    <<-HELP

puppet-filebucket(8) -- #{summary}
========

SYNOPSIS
--------
A stand-alone Puppet filebucket client.


USAGE
-----
puppet filebucket <mode> [-h|--help] [-V|--version] [-d|--debug]
  [-v|--verbose] [-l|--local] [-r|--remote] [-s|--server <server>]
  [-f|--fromdate <date>] [-t|--todate <date>] [-b|--bucket <directory>]
  <file> <file> ...

Puppet filebucket can operate in three modes, with only one mode per call:

backup:
  Send one or more files to the specified file bucket. Each sent file is
  printed with its resulting md5 sum.

get:
  Return the text associated with an md5 sum. The text is printed to
  stdout, and only one file can be retrieved at a time.

restore:
  Given a file path and an md5 sum, store the content associated with
  the sum into the specified file path. You can specify an entirely new
  path to this argument; you are not restricted to restoring the content
  to its original location.

diff:
  Print a diff in unified format between two checksums in the filebucket
  or between a checksum and its matching file.

list:
  List all files in the current local filebucket. Listing remote
  filebuckets is not allowed.

DESCRIPTION
-----------
This is a stand-alone filebucket client for sending files to a local or
central filebucket.

Note that 'filebucket' defaults to using a network-based filebucket
available on the server named 'puppet'. To use this, you'll have to be
running as a user with valid Puppet certificates. Alternatively, you can
use your local file bucket by specifying '--local', or by specifying
'--bucket' with a local path.


OPTIONS
-------
Note that any setting that's valid in the configuration
file is also a valid long argument. For example, 'ssldir' is a valid
setting, so you can specify '--ssldir <directory>' as an
argument.

See the configuration file documentation at
https://puppet.com/docs/puppet/latest/configuration.html for the
full list of acceptable parameters. A commented list of all
configuration options can also be generated by running puppet with
'--genconfig'.

* --bucket:
  Specify a local filebucket path. This overrides the default path
  set in '$clientbucketdir'.

* --debug:
  Enable full debugging.

* --fromdate:
  (list only) Select bucket files from 'fromdate'.

* --help:
  Print this help message.

* --local:
  Use the local filebucket. This uses the default configuration
  information and the bucket located at the '$clientbucketdir'
  setting by default. If '--bucket' is set, puppet uses that
  path instead.

* --remote:
  Use a remote filebucket. This uses the default configuration
  information and the bucket located at the '$bucketdir' setting
  by default.

* --server_list:
  A list of comma seperated servers; only the first entry is used for file storage.
  This setting takes precidence over `server`.

* --server:
  The server to use for file storage. This setting is only used if `server_list`
  is not set.

* --todate:
  (list only) Select bucket files until 'todate'.

* --verbose:
  Print extra information.

* --version:
  Print version information.

EXAMPLES
--------
    ## Backup a file to the filebucket, then restore it to a temporary directory
    $ puppet filebucket backup /etc/passwd
    /etc/passwd: 429b225650b912a2ee067b0a4cf1e949
    $ puppet filebucket restore /tmp/passwd 429b225650b912a2ee067b0a4cf1e949

    ## Diff between two files in the filebucket
    $ puppet filebucket -l diff d43a6ecaa892a1962398ac9170ea9bf2 7ae322f5791217e031dc60188f4521ef
    1a2
    > again

    ## Diff between the file in the filebucket and a local file
    $ puppet filebucket -l diff d43a6ecaa892a1962398ac9170ea9bf2 /tmp/testFile
    1a2
    > again

    ## Backup a file to the filebucket and observe that it keeps each backup separate
    $ puppet filebucket -l list
    d43a6ecaa892a1962398ac9170ea9bf2 2015-05-11 09:27:56 /tmp/TestFile

    $ echo again >> /tmp/TestFile

    $ puppet filebucket -l backup /tmp/TestFile
    /tmp/TestFile: 7ae322f5791217e031dc60188f4521ef

    $ puppet filebucket -l list
    d43a6ecaa892a1962398ac9170ea9bf2 2015-05-11 09:27:56 /tmp/TestFile
    7ae322f5791217e031dc60188f4521ef 2015-05-11 09:52:15 /tmp/TestFile

    ## List files in a filebucket within date ranges
    $ puppet filebucket -l -f 2015-01-01 -t 2015-01-11 list
    <Empty Output>

    $ puppet filebucket -l -f 2015-05-10 list
    d43a6ecaa892a1962398ac9170ea9bf2 2015-05-11 09:27:56 /tmp/TestFile
    7ae322f5791217e031dc60188f4521ef 2015-05-11 09:52:15 /tmp/TestFile

    $ puppet filebucket -l -f "2015-05-11 09:30:00" list
    7ae322f5791217e031dc60188f4521ef 2015-05-11 09:52:15 /tmp/TestFile

    $ puppet filebucket -l -t "2015-05-11 09:30:00" list
    d43a6ecaa892a1962398ac9170ea9bf2 2015-05-11 09:27:56 /tmp/TestFile
    ## Manage files in a specific local filebucket
    $ puppet filebucket -b /tmp/TestBucket backup /tmp/TestFile2
    /tmp/TestFile2: d41d8cd98f00b204e9800998ecf8427e
    $ puppet filebucket -b /tmp/TestBucket list
    d41d8cd98f00b204e9800998ecf8427e 2015-05-11 09:33:22 /tmp/TestFile2

    ## From a Puppet master, list files in the master bucketdir
    $ puppet filebucket -b $(puppet config print bucketdir --section master) list
    d43a6ecaa892a1962398ac9170ea9bf2 2015-05-11 09:27:56 /tmp/TestFile
    7ae322f5791217e031dc60188f4521ef 2015-05-11 09:52:15 /tmp/TestFile

AUTHOR
------
Luke Kanies


COPYRIGHT
---------
Copyright (c) 2011 Puppet Inc., LLC Licensed under the Apache 2.0 License

    HELP
  end


  def run_command
    @args = command_line.args
    command = args.shift
    return send(command) if %w{get backup restore diff list}.include? command
    help
  end

  def get
    md5 = args.shift
    out = @client.getfile(md5)
    print out
  end

  def backup
    raise _("You must specify a file to back up") unless args.length > 0

    args.each do |file|
      unless Puppet::FileSystem.exist?(file)
        $stderr.puts _("%{file}: no such file") % { file: file }
        next
      end
      unless FileTest.readable?(file)
        $stderr.puts _("%{file}: cannot read file") % { file: file }
        next
      end
      md5 = @client.backup(file)
      puts "#{file}: #{md5}"
    end
  end

  def list
    fromdate = options[:fromdate]
    todate = options[:todate]
    out = @client.list(fromdate, todate)
    print out
  end

  def restore
    file = args.shift
    md5 = args.shift
    @client.restore(file, md5)
  end

  def diff
    raise Puppet::Error, _("Need exactly two arguments: filebucket diff <file_a> <file_b>") unless args.count == 2
    left = args.shift
    right = args.shift
    if Puppet::FileSystem.exist?(left)
      # It's a file
      file_a = left
      checksum_a = nil
    else
      file_a = nil
      checksum_a = left
    end
    if Puppet::FileSystem.exist?(right)
      # It's a file
      file_b = right
      checksum_b = nil
    else
      file_b = nil
      checksum_b = right
    end
    if (checksum_a || file_a) && (checksum_b || file_b)
      Puppet.info(_("Comparing %{checksum_a} %{checksum_b} %{file_a} %{file_b}") % { checksum_a: checksum_a, checksum_b: checksum_b, file_a: file_a, file_b: file_b })
      print @client.diff(checksum_a, checksum_b, file_a, file_b)
    else
      raise Puppet::Error, _("Need exactly two arguments: filebucket diff <file_a> <file_b>")
    end
  end

  def setup
    Puppet::Log.newdestination(:console)

    @client = nil
    @server = nil

    Signal.trap(:INT) do
      $stderr.puts _("Cancelling")
      exit(1)
    end

    if options[:debug]
      Puppet::Log.level = :debug
    elsif options[:verbose]
      Puppet::Log.level = :info
    end

      exit(Puppet.settings.print_configs ? 0 : 1) if Puppet.settings.print_configs?

    require 'puppet/file_bucket/dipper'
    begin
      if options[:local] or options[:bucket]
        path = options[:bucket] || Puppet[:clientbucketdir]
        @client = Puppet::FileBucket::Dipper.new(:Path => path)
      else
        if Puppet[:server_list] && !Puppet[:server_list].empty?
          server = Puppet[:server_list].first
          #TRANSLATORS 'server_list' is the name of a setting and should not be translated
          Puppet.debug _("Selected server from first entry of the `server_list` setting: %{server}:%{port}") % {server: server[0], port: server[1]}
          @client = Puppet::FileBucket::Dipper.new(
            :Server => server[0],
            :Port => server[1]
          )
        else
          #TRANSLATORS 'server' is the name of a setting and should not be translated
          Puppet.debug _("Selected server from the `server` setting: %{server}") % {server: Puppet[:server]}
          @client = Puppet::FileBucket::Dipper.new(:Server => Puppet[:server])
        end
      end
    rescue => detail
      Puppet.log_exception(detail)
      exit(1)
    end
  end
end
