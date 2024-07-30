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
end
