require 'tempfile'

OUTPUT_DIR = 'references'
MANDIR = File.join(OUTPUT_DIR, 'man')
TYPES_DIR = File.join(OUTPUT_DIR, 'types')

CONFIGURATION_ERB = File.join(__dir__, 'references/configuration.erb')
CONFIGURATION_MD  = File.join(OUTPUT_DIR, 'configuration.md')
METAPARAMETER_ERB = File.join(__dir__, 'references/metaparameter.erb')
METAPARAMETER_MD  = File.join(OUTPUT_DIR, 'metaparameter.md')
REPORT_ERB        = File.join(__dir__, 'references/report.erb')
REPORT_MD         = File.join(OUTPUT_DIR, 'report.md')
FUNCTIONS_TEMPLATE_ERB = File.join(__dir__, 'references/functions_template.erb')
FUNCTION_ERB      = File.join(__dir__, 'references/function.erb')
FUNCTION_MD       = File.join(OUTPUT_DIR, 'function.md')
MAN_OVERVIEW_ERB  = File.join(__dir__, 'references/man/overview.erb')
MAN_OVERVIEW_MD   = File.join(MANDIR, "overview.md")
MAN_ERB           = File.join(__dir__, 'references/man.erb')
TYPES_OVERVIEW_ERB = File.join(__dir__, 'references/types/overview.erb')
TYPES_OVERVIEW_MD  = File.join(TYPES_DIR, 'overview.md')

def render_erb(erb_file, variables)
  # Create a binding so only the variables we specify will be visible
  template_binding = OpenStruct.new(variables).instance_eval {binding}
  ERB.new(File.read(erb_file), trim_mode: '-').result(template_binding)
end

def puppet_doc(reference)
  body = %x{bundle exec puppet doc -r #{reference}}
  # Remove the first H1 with the title, like "# Metaparameter Reference"
  body.sub!(/^# \w+ Reference *$/, '')
end

def generate_reference(reference, erb, body, output)
  sha = %x{git rev-parse HEAD}.chomp
  now = Time.now
  variables = {
    sha: sha,
    now: now,
    body: body
  }
  content = render_erb(erb, variables)
  File.write(output, content)
  puts "Generated #{output}"
end

def extract_resource_types(strings_data)
  strings_data['resource_types'].reduce(Hash.new) do |memo, type|
    memo[ type['name'] ] = {
      'description' => type['docstring']['text'],
      'features' => (type['features'] || []).reduce(Hash.new) {|memo, feature|
        memo[feature['name']] = feature['description']
        memo
      },
      'providers' => strings_data['providers'].select {|provider|
        provider['type_name'] == type['name']
      }.reduce(Hash.new) {|memo, provider|
        description = provider['docstring']['text']
        if provider['commands'] || provider['confines'] || provider['defaults']
          description = description + "\n"
        end
        if provider['commands']
          description = description + "\n* Required binaries: `#{provider['commands'].values.sort.join('`, `')}`"
        end
        if provider['confines']
          description = description + "\n* Confined to: `#{provider['confines'].map{|fact,val| "#{fact} == #{val}"}.join('`, `')}`"
        end
        if provider['defaults']
          description = description + "\n* Default for: `#{provider['defaults'].map{|fact,val| "#{fact} == #{val}"}.join('`, `')}`"
        end
        if provider['features']
          description = description + "\n* Supported features: `#{provider['features'].sort.join('`, `')}`"
        end
        memo[provider['name']] = {
          'features' => (provider['features'] || []),
          'description' => description
        }
        memo
      },
      'attributes' => (type['parameters'] || []).reduce(Hash.new) {|memo, attribute|
        description = attribute['description'] || ''
        if attribute['default']
          description = description + "\n\nDefault: `#{attribute['default']}`"
        end
        if attribute['values']
          description = description + "\n\nAllowed values:\n\n" + attribute['values'].map{|val| "* `#{val}`"}.join("\n")
        end
        memo[attribute['name']] = {
          'description' => description,
          'kind' => 'parameter',
          'namevar' => attribute['isnamevar'] ? true : false,
          'required_features' => attribute['required_features'],
        }
        memo
      }.merge( (type['properties'] || []).reduce(Hash.new) {|memo, attribute|
          description = attribute['description'] || ''
          if attribute['default']
            description = description + "\n\nDefault: `#{attribute['default']}`"
          end
          if attribute['values']
            description = description + "\n\nAllowed values:\n\n" + attribute['values'].map{|val| "* `#{val}`"}.join("\n")
          end
          memo[attribute['name']] = {
            'description' => description,
            'kind' => 'property',
            'namevar' => false,
            'required_features' => attribute['required_features'],
          }
          memo
        }).merge( (type['checks'] || []).reduce(Hash.new) {|memo, attribute|
            description = attribute['description'] || ''
            if attribute['default']
              description = description + "\n\nDefault: `#{attribute['default']}`"
            end
            if attribute['values']
              description = description + "\n\nAllowed values:\n\n" + attribute['values'].map{|val| "* `#{val}`"}.join("\n")
            end
            memo[attribute['name']] = {
              'description' => description,
              'kind' => 'check',
              'namevar' => false,
              'required_features' => attribute['required_features'],
            }
            memo
          })
    }
    memo
  end
end

namespace :ref do
  desc "Generate configuration reference"
  task :configuration do
    ENV['SOURCE_HOSTNAME'] = "(the system's fully qualified hostname)"
    ENV['SOURCE_DOMAIN'] = "(the system's own domain)"

    body = puppet_doc('configuration')
    generate_reference('configuration', CONFIGURATION_ERB, body, CONFIGURATION_MD)
  end

  desc "Generate metaparameter reference"
  task :metaparameter do
    body = puppet_doc('metaparameter')
    generate_reference('metaparameter', METAPARAMETER_ERB, body, METAPARAMETER_MD)
  end

  desc "Generate report reference"
  task :report do
    body = puppet_doc('report')
    generate_reference('report', REPORT_ERB, body, REPORT_MD)
  end

  desc "Generate function reference"
  task :function do
    # Locate puppet-strings
    begin
      require 'puppet-strings'
    rescue LoadError
      abort("Run `bundle config set with documentation` and `bundle update` to install the `puppet-strings` gem.")
    end

    strings_data = {}
    Tempfile.create do |tmpfile|
      # REMIND: This doesn't really do anything, because strings uses yard, which uses `.yardoc` to determine which files to search
      rubyfiles = Dir.glob(File.join(__dir__, "../lib/puppet/{functions,parser/functions}/**/*.rb"))
      puts "Running puppet strings on #{rubyfiles.count} functions"
      puts %x{bundle exec puppet strings generate --format json --out #{tmpfile.path} #{rubyfiles.join(' ')}}

      strings_data = JSON.load_file(tmpfile.path)
    end

    functions = strings_data['puppet_functions']

    # Deal with the duplicate 3.x and 4.x functions
    # 1. Figure out which functions are duplicated.
    names = functions.map { |func| func['name'] }
    duplicates = names.uniq.select { |name| names.count(name) > 1 }
    # 2. Reject the 3.x version of any dupes.
    functions = functions.reject do |func|
      duplicates.include?(func['name']) && func['type'] != 'ruby4x'
    end

    # renders the list of functions
    body = render_erb(FUNCTIONS_TEMPLATE_ERB, functions: functions)

    # This substitution could potentially make things a bit brittle, but it has to be done because the jump
    # From H2s to H4s is causing issues with the DITA-OT, which sees this as a rule violation. If it
    # Does become an issue, we should return to this and figure out a better way to generate the functions doc.
    body.gsub!(/#####\s(.*?:)/,'**\1**').gsub!(/####\s/,'### ')

    # renders the preamble and list of functions
    generate_reference('function', FUNCTION_ERB, body, FUNCTION_MD)
  end

  desc "Generate man as markdown references"
  task :man do
    FileUtils.mkdir_p(MANDIR)

    begin
      require 'pandoc-ruby'
    rescue LoadError
      abort("Run `bundle config set with documentation` and `bundle update` to install the `pandoc-ruby` gem.")
    end

    begin
      puts %x{pandoc --version}
    rescue Errno::ENOENT => e
      abort("Please install the `pandoc` package.")
    end

    sha = %x{git rev-parse HEAD}.chomp
    now = Time.now

    core_apps = %w(
      agent
      apply
      lookup
      module
      resource
    )
    occasional_apps = %w(
      config
      describe
      device
      doc
      epp
      generate
      help
      node
      parser
      plugin
      script
      ssl
    )
    weird_apps = %w(
      catalog
      facts
      filebucket
      report
    )

    variables = {
      sha: sha,
      now: now,
      title: 'Puppet Man Pages',
      core_apps: core_apps,
      occasional_apps: occasional_apps,
      weird_apps: weird_apps
    }

    content = render_erb(MAN_OVERVIEW_ERB, variables)
    File.write(MAN_OVERVIEW_MD, content)
    puts "Generated #{MAN_OVERVIEW_MD}"

    # Convert the roff formatted man pages to markdown.
    # This means if code changes are made to puppet, then we
    # first need to `rake gen_manpages`, followed by this task
    files = Pathname.glob(File.join(__dir__, '../man/man8/*.8'))
    files.each do |f|
      next if File.basename(f) == "puppet.8"

      app = File.basename(f).delete_prefix('puppet-').delete_suffix(".8")

      body =
        PandocRuby.convert([f], from: :man, to: :markdown)
        .gsub(/#(.*?)\n/, '##\1')
        .gsub(/:\s\s\s\n\n```\{=html\}\n<!--\s-->\n```/, '')
        .gsub(/\n:\s\s\s\s/, '')

      variables = {
        sha: sha,
        now: now,
        title: "Man Page: puppet #{app}",
        canonical: "/puppet/latest/man/#{app}.html",
        body: body
      }

      content = render_erb(MAN_ERB, variables)
      output = File.join(MANDIR, "#{app}.md")
      File.write(output, content)
      puts "Generated #{output}"
    end
  end

  task :type do
    FileUtils.mkdir_p(TYPES_DIR)

    # Locate puppet-strings
    begin
      require 'puppet-strings'
    rescue LoadError
      abort("Run `bundle config set with documentation` and `bundle update` to install the `puppet-strings` gem.")
    end

    sha = %x{git rev-parse HEAD}.chomp

    Tempfile.create do |tmpfile|
      # REMIND: This doesn't really do anything, because strings uses yard, which uses `.yardoc` to determine which files to search
      rubyfiles = Dir.glob(File.join(__dir__, "../lib/puppet/type/**/*.rb"))
      puts "Running puppet strings on #{rubyfiles.count} files"
      puts %x{bundle exec puppet strings generate --format json --out #{tmpfile.path} #{rubyfiles.join(' ')}}

      strings_data = JSON.load_file(tmpfile.path)
      type_data = extract_resource_types(strings_data)

      # REMIND: index.md exists in osp-docs, but it's nearly identical to overview.md

      # overview.md
      types = type_data.keys.reject do |type|
        type == 'component' || type == 'whit'
      end

      variables = {
        sha: sha,
        now: Time.now,
        title: 'Resource types overview',
        types: types
      }

      # Use the puppet-strings output that's been translated in
      # extract_resource_types to generate the overview
      content = render_erb(TYPES_OVERVIEW_ERB, variables)
      File.write(TYPES_OVERVIEW_MD, content)
      puts "Generated #{TYPES_OVERVIEW_MD}"
    end
  end
end
