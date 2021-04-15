source ENV['GEM_SOURCE'] || "https://rubygems.org"

gemspec

def location_for(place, fake_version = nil)
  if place =~ /^(git[:@][^#]*)#(.*)/
    [fake_version, { git: $1, branch: $2, require: false }].compact
  elsif place =~ /^file:\/\/(.*)/
    ['>= 0', { path: File.expand_path($1), require: false }]
  else
    [place, { require: false }]
  end
end

# override .gemspec deps - may issue warning depending on Bundler version
gem "facter", *location_for(ENV['FACTER_LOCATION']) if ENV.has_key?('FACTER_LOCATION')
gem "hiera", *location_for(ENV['HIERA_LOCATION']) if ENV.has_key?('HIERA_LOCATION')
gem "semantic_puppet", *location_for(ENV['SEMANTIC_PUPPET_LOCATION'] || ["~> 1.0"])
gem "puppet-resource_api", *location_for(ENV['RESOURCE_API_LOCATION'] || ["~> 1.5"])

group(:features) do
  gem 'diff-lcs', '~> 1.3', require: false
  gem 'hiera-eyaml', require: false
  gem 'hocon', '~> 1.0', require: false
  # requires native libshadow headers/libs
  # gem 'libshadow', '~> 1.0', require: false, platforms: [:ruby]
  gem 'minitar', '~> 0.6', require: false
  gem 'msgpack', '~> 1.2', require: false
  gem 'rdoc', '~> 6.0', require: false, platforms: [:ruby]
  # requires native augeas headers/libs
  # gem 'ruby-augeas', require: false, platforms: [:ruby]
  # requires native ldap headers/libs
  # gem 'ruby-ldap', '~> 0.9', require: false, platforms: [:ruby]
  gem 'puppetserver-ca', '~> 1.1', require: false
end

group(:test) do
  gem "json-schema", "~> 2.0", require: false
  gem "rake", *location_for(ENV['RAKE_LOCATION'] || '~> 12.2')
  gem "rspec", "~> 3.1", require: false
  gem "rspec-its", "~> 1.1", require: false
  gem "rspec-collection_matchers", "~> 1.1", require: false
  gem 'vcr', '~> 2.9', require: false
  gem 'webmock', '~> 1.24', require: false
  gem 'yard', require: false

  gem 'rubocop', '~> 0.49', require: false, platforms: [:ruby]
  gem 'rubocop-i18n', '~> 1.2.0', require: false, platforms: [:ruby]

  gem 'sorbet', :group => :development
  gem 'sorbet-runtime'
end

group(:development, optional: true) do
  gem 'memory_profiler', require: false, platforms: [:mri]
  gem 'pry', require: false, platforms: [:ruby]
  gem "racc", "1.4.9", require: false, platforms: [:ruby]
  if RUBY_PLATFORM != 'java'
    gem 'ruby-prof', '>= 0.16.0', require: false
  end
end

group(:packaging) do
  gem 'packaging', *location_for(ENV['PACKAGING_LOCATION'] || '~> 0.99')
end

group(:documentation) do
  gem 'gettext-setup', '~> 0.28', require: false, platforms: [:ruby]
  gem 'ronn', '~> 0.7.3', require: false, platforms: [:ruby]
end

if File.exists? "#{__FILE__}.local"
  eval(File.read("#{__FILE__}.local"), binding)
end

# vim:filetype=ruby
