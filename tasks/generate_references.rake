class Reference
  attr_reader :commit, :latest

  def initialize(commit)
    @commit = commit
  end

  def make_header(header_data)
    default_header_data = {layout: 'default', built_from_commit: @commit}

    data = default_header_data.merge(header_data)
    # clean out any symbols:
    clean_data = data.reduce( {} ) do |result, (key,val)|
      result[key.to_s]=val
      result
    end
    generated_at = "> **NOTE:** This page was generated from the Puppet source code on #{Time.now.to_s}"
    YAML.dump(clean_data) + "---\n\n" + "# #{clean_data['title']}" + "\n\n" + generated_at + "\n\n"
  end
end

class TypeReference < Reference
  TYPEDOCS_SCRIPT = Pathname.new(File.expand_path(__FILE__)).dirname + 'docs/generate_types.rb'
  TEMPLATE_FILE = Pathname.new(File.expand_path(__FILE__)).dirname + 'docs/type_template.erb'
  TEMPLATE = ERB.new(TEMPLATE_FILE.read, nil, '-')
  PREAMBLE_FILE = Pathname.new(File.expand_path(__FILE__)).dirname + 'docs/type_preamble.md'
  PREAMBLE = PREAMBLE_FILE.read

  def initialize(commit, output_dir_unified, output_dir_individual)
    super(commit)
    @latest = '/puppet/latest'
    @output_dir_unified = output_dir_unified
    @output_dir_individual = output_dir_individual
    @base_filename = 'type'
  end

  def build_all
    puts 'Type ref: Building all...'
    type_json = get_type_json
    type_data = JSON.load(type_json)

    write_json_file(type_json)
    build_index(type_data.keys.sort)
    build_unified_page(type_data)
    type_data.each do |name, data|
      build_page(name, data)
    end
    puts 'Type ref: Done!'
  end

  def build_index(names)
    header_data = {title: 'Resource Types: Index',
                   canonical: "#{@latest}/types/index.md"}
    links = names.map {|name|
      "* [#{name}](./#{name}.md)" unless name == 'component' || name == 'whit'
    }
    content = make_header(header_data) + "## List of Resource Types\n\n" + links.join("\n") + "\n\n" + PREAMBLE
    filename = @output_dir_individual + 'index.md'
    filename.open('w') {|f| f.write(content)}
  end

  def get_type_json
    puts 'Type ref: Getting JSON data'
    %x{ruby #{TYPEDOCS_SCRIPT}}
  end

  def build_unified_page(typedocs)
    puts 'Type ref: Building unified page'
    header_data = {title: 'Resource Type Reference (Single-Page)',
                   canonical: "#{@latest}/type.html",
                   toc_levels: 2,
                   toc: 'columns'}

    sorted_type_list = typedocs.keys.sort
    all_type_docs = sorted_type_list.collect{|name|
      text_for_type(name, typedocs[name])
    }.join("\n\n---------\n\n")

    content = make_header(header_data) + "\n\n" + PREAMBLE + all_type_docs + "\n\n"
    filename = @output_dir_unified + "#{@base_filename}.md"
    filename.open('w') {|f| f.write(content)}
  end

  def write_json_file(json)
    puts 'Type ref: Writing JSON as file'
    filename = @output_dir_unified + "#{@base_filename}.json"
    filename.open('w') {|f| f.write(json)}
  end

  def build_page(name, data)
    puts "Type ref: Building #{name}"
    header_data = {title: "Resource Type: #{name}",
                   canonical: "#{@latest}/types/#{name}.html"}
    content = make_header(header_data) + "\n\n" + text_for_type(name, data) + "\n\n"
    filename = @output_dir_individual + "#{name}.md"
    filename.open('w') {|f| f.write(content)}
  end

  def text_for_type(name, this_type)
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

    # template uses: name, this_type, sorted_attribute_list, sorted_feature_list, longest_attribute_name
    template_scope = OpenStruct.new(
      {
        name: name,
        this_type: this_type,
        sorted_attribute_list: sorted_attribute_list,
        sorted_feature_list: this_type['features'].keys.sort,
        longest_attribute_name: sorted_attribute_list.collect{|attr| attr.length}.max
      }
    )
    TEMPLATE.result( template_scope.instance_eval {binding} )
  end
end

classes = [
  #  PuppetReferences::Puppet::Man,
  #  PuppetReferences::Puppet::PuppetDoc,
  TypeReference,
  #  PuppetReferences::Puppet::TypeStrings,
  #  PuppetReferences::Puppet::Functions
]

task :generate_references do
  commit = `git rev-parse HEAD`
  output_dir_unified = Pathname.new '/tmp/references_output/puppet'
  output_dir_unified.mkpath

  output_dir_individual = Pathname.new '/tmp/references_output/puppet/types'
  output_dir_individual.mkpath

  references = classes.map do |klass|
    klass.new(commit, output_dir_unified, output_dir_individual)
  end

  references.each do |ref|
    ref.build_all
  end

  locations = references.map do |ref|
    "#{ref.class.to_s} -> #{ref.latest}"
  end.join("\n")
  puts 'NOTE: Generated files are in the references_output directory.'
  puts "NOTE: You'll have to move the generated files into place yourself. The 'latest' location for each is:"
  puts locations
end
