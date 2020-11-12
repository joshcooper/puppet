require 'erb'
require 'ostruct'
require 'fileutils'
require 'json'
require 'bundler'

class Benchmarker
  include FileUtils

  def initialize(target, size='medium')
    @target = target
    @size = 'large'
  end

  def check_submodule
    submodule = File.join('benchmarks', 'full_catalog', 'puppetlabs-puppetserver_perf_control')
    unless File.exist?(File.join(submodule, 'Puppetfile'))
      raise RuntimeError, 'The perf control repo is not readable. Make sure to initialize submodules by running: git submodule update --init --recursive'
    end
  end

  def setup
    require 'puppet'
    config = File.join(@target, 'puppet.conf')
    environment = File.join(@target, 'environments', 'perf_control')
    Puppet.initialize_settings(['--config', config])
    FileUtils.cd(@target) do
      Bundler::with_clean_env do
        system("bundle install")
        system("bundle exec r10k puppetfile install --puppetfile #{File.join(environment, 'Puppetfile')} --moduledir #{File.join(environment, 'modules')} --config r10k.yaml")
      end
    end

    # Loading the base system affects the first run a lot so burn one run here
    run
  end

  def run(args=nil)
    facts_path = File.join(File.dirname(__FILE__), 'facts.json')
    hash = JSON.parse(File.read(facts_path))
    hash["values"] = {
      'pe_concat_basedir'         => '/tmp/file',
      'platform_symlink_writable' => true,
      'pe_build'                  => '2016.4.4',
      'puppetversion' => '4.10.4',
      'aio_agent_version' => '1.10.4',
      'aio_agent_build'   => '1.10.4',
      'fake_domain' => 'pgtomcat.mycompany.org',
      'function' => 'app',
      'group' => 'pgtomcat',
      'stage' => 'prod',
      'whereami' => 'portland',
      'hostname' => 'pgtomcat',
      'fqdn' => 'pgtomcat.mycompany.org',
    }.merge!(hash["values"])

    Puppet::Node::Facts.indirection.terminus_class = :memory
    Puppet::Node::Facts.indirection.cache_class = nil

    facts = Puppet::Node::Facts.from_data_hash(hash)

    env = Puppet.lookup(:environments).get('perf_control')
    node = Puppet::Node.new(facts.name, :environment => env)

    Puppet.push_context({:current_environment => env}, 'current env for benchmark')
    require  'byebug'; byebug
    Puppet::Resource::Catalog.indirection.find(facts.name, :use_node => node, facts: facts, facts_format: 'application/json')
    Puppet.pop_context
    Puppet.lookup(:environments).clear('perf_control')
  end

  def generate
    check_submodule
    templates = File.join('benchmarks', 'full_catalog')
    source = File.join(templates, "puppetlabs-puppetserver_perf_control")
    environment = File.join(@target, 'environments', 'perf_control')
    mkdir_p(File.join(@target, 'environments'))
    FileUtils.cp_r(source, environment)

    render(File.join(templates, 'puppet.conf.erb'),
           File.join(@target, 'puppet.conf'),
           :codedir => File.join(@target, 'environments'),
           :target => @target)

    render(File.join(templates, 'site.pp.erb'),
           File.join(environment, 'manifests', 'site.pp'),
           :size => @size)

    render(File.join(templates, 'hiera.yaml.erb'),
           File.join(@target, 'hiera.yaml'),
           :datadir => File.join(environment, 'hieradata'))

    FileUtils.cp(File.join(templates, 'Gemfile'), @target)
    FileUtils.cp(File.join(templates, 'r10k.yaml'), @target)
  end

  def render(erb_file, output_file, bindings)
    site = ERB.new(File.read(erb_file))
    File.open(output_file, 'w') do |fh|
      fh.write(site.result(OpenStruct.new(bindings).instance_eval { binding }))
    end
  end
end
