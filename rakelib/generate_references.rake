require 'tempfile'

OUTPUT_DIR = 'references'

def render_erb(erb, variables)
  template_binding = OpenStruct.new(variables).instance_eval {binding}
  ERB.new(File.read(erb), trim_mode: '-').result(template_binding)
end

def puppet_doc(reference)
  body = %x{bundle exec puppet doc -r #{reference}}
  # Remove the first H1 with the title, like "# Metaparameter Reference"
  body.sub!(/^# \w+ Reference *$/, '')
end

def generate_reference(reference, erb, body, output)
  sha = %x{git rev-parse HEAD}.chomp
  now = Time.now

  puts "Generating #{reference} reference from #{sha}"
  variables = {
    sha: sha,
    now: now,
    body: body
  }
  content = render_erb(erb, variables)
  File.write(output, content)
  puts "Generated #{output}"
end

def render_resource_type(name, this_type)
  sorted_attribute_list = this_type['attributes'].keys.sort {|a,b|
    # Float namevar to top and ensure to second-top
    if this_type['attributes'][a]['namevar']
      -1
    elsif this_type['attributes'][b]['namevar']
      1
    elsif a == 'ensure'
      -1
    elsif b == 'ensure'
      1
    else
      a <=> b
    end
  }

  variables = {
    name: name,
    this_type: this_type,
    sorted_attribute_list: sorted_attribute_list,
    sorted_feature_list: this_type['features'].keys.sort,
    longest_attribute_name: sorted_attribute_list.collect{|attr| attr.length}.max
  }
  erb = File.join(__dir__, 'references/types/type.erb')
  render_erb(erb, variables)
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
  task :config do
    ENV['SOURCE_HOSTNAME'] = "(the system's fully qualified hostname)"
    ENV['SOURCE_DOMAIN'] = "(the system's own domain)"

    erb = File.join(__dir__, 'references/configuration.erb')
    body = puppet_doc('configuration')
    output = File.join(OUTPUT_DIR, 'configuration.md')

    generate_reference('configuration', erb, body, output)
  end

  desc "Generate metaparameter reference"
  task :metaparameter do
    erb = File.join(__dir__, 'references/metaparameter.erb')
    body = puppet_doc('metaparameter')
    output = File.join(OUTPUT_DIR, 'metaparameter.md')

    generate_reference('metaparameter', erb, body, output)
  end

  desc "Generate report reference"
  task :report do
    erb = File.join(__dir__, 'references/report.erb')
    body = puppet_doc('report')
    output = File.join(OUTPUT_DIR, 'report.md')

    generate_reference('report', erb, body, output)
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
      # This doesn't really do anything, because strings uses yard, which uses `.yardoc` to determine which files to search
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

    erb = File.join(__dir__, 'references/functions_template.erb')
    body = render_erb(erb, functions: functions)

    # This substitution could potentially make things a bit brittle, but it has to be done because the jump
    # From H2s to H4s is causing issues with the DITA-OT, which sees this as a rule violation. If it
    # Does become an issue, we should return to this and figure out a better way to generate the functions doc.
    body.gsub!(/#####\s(.*?:)/,'**\1**').gsub!(/####\s/,'###\s')

    erb = File.join(__dir__, 'references/function.erb')
    output = File.join(OUTPUT_DIR, 'function.md')
    generate_reference('function', erb, body, output)
  end

  desc "Generate man as markdown references"
  task :man do
    mandir = File.join(OUTPUT_DIR, 'man')
    FileUtils.mkdir_p(mandir)

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

    files = Pathname.glob(File.join(__dir__, '../man/man8/*.8'))
    files.each do |f|
      app = File.basename(f).delete_prefix('puppet-').delete_suffix(".8")

      # REMIND: top-level puppet.8
      puts "Generating #{app} markdown from #{sha}"
      body =
        PandocRuby.convert([f], from: :man, to: :markdown)
        .gsub(/#(.*?)\n/, '##\1')
        .gsub(/:\s\s\s\n\n```\{=html\}\n<!--\s-->\n```/, '')
        .gsub(/\n:\s\s\s\s/, '')

      variables = {
        sha: sha,
        now: Time.now,
        title: "Man Page: puppet #{app}",
        canonical: "/puppet/latest/man/#{app}.html",
        body: body
      }

      erb = File.join(__dir__, 'references/man.erb')
      content = render_erb(erb, variables)
      output = File.join(mandir, "#{app}.md")
      File.write(output, content)
      puts "Generated #{output}"
    end
  end

  task :type do
    typesdir = File.join(OUTPUT_DIR, 'types')
    FileUtils.mkdir_p(typesdir)

    # Locate puppet-strings
    begin
      require 'puppet-strings'
    rescue LoadError
      abort("Run `bundle config set with documentation` and `bundle update` to install the `puppet-strings` gem.")
    end

    sha = %x{git rev-parse HEAD}.chomp
    now = Time.now

    Tempfile.create do |tmpfile|
      # This doesn't really do anything, because strings uses yard, which uses `.yardoc` to determine which files to search
      rubyfiles = Dir.glob(File.join(__dir__, "../lib/puppet/type/**/*.rb"))
      puts "Running puppet strings on #{rubyfiles.count} files"
      puts %x{bundle exec puppet strings generate --format json --out #{tmpfile.path} #{rubyfiles.join(' ')}}

      strings_data = JSON.load_file(tmpfile.path)
      type_data = extract_resource_types(strings_data)

      # overview.md
      types = type_data.keys.reject do |type|
        type == 'component' || type == 'whit'
      end

      variables = {
        title: 'Resource types overview',
        sha: sha,
        now: now,
        types: types
      }

      erb = File.join(__dir__, 'references/types/overview.erb')
      content = render_erb(erb, variables)
      output = File.join(typesdir, 'overview.md')
      File.write(output, content)

      # single page
      types_content = types.sort.map do |name|
        render_resource_type(name, type_data[name])
      end

      variables = {
        title: 'Resource Type Reference (Single-Page)',
        sha: sha,
        now: now,
        types: types_content
      }

      erb = File.join(__dir__, 'references/unified_type.erb')
      content = render_erb(erb, variables)
      output = File.join(OUTPUT_DIR, 'type.md')
      File.write(output, content)
    end
  end
end
