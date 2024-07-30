require 'tempfile'

OUTPUT_DIR = 'references'
CONFIGURATION_ERB = File.join(__dir__, 'references/configuration.erb')
CONFIGURATION_MD  = File.join(OUTPUT_DIR, 'configuration.md')

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

namespace :ref do
  desc "Generate configuration reference"
  task :configuration do
    ENV['SOURCE_HOSTNAME'] = "(the system's fully qualified hostname)"
    ENV['SOURCE_DOMAIN'] = "(the system's own domain)"

    body = puppet_doc('configuration')
    generate_reference('configuration', CONFIGURATION_ERB, body, CONFIGURATION_MD)
  end
end
