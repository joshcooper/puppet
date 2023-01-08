module Puppet::Pops
module Types

# @api private
class RubyGenerator < TypeFormatter

  RUBY_RESERVED_WORDS = {
    'alias' => '_alias',
    'begin' => '_begin',
    'break' => '_break',
    'def' => '_def',
    'do' => '_do',
    'end' => '_end',
    'ensure' => '_ensure',
    'for' => '_for',
    'module' => '_module',
    'next' => '_next',
    'nil' => '_nil',
    'not' => '_not',
    'redo' => '_redo',
    'rescue' => '_rescue',
    'retry' => '_retry',
    'return' => '_return',
    'self' => '_self',
    'super' => '_super',
    'then' => '_then',
    'until' => '_until',
    'when' => '_when',
    'while' => '_while',
    'yield' => '_yield',
  }

  RUBY_RESERVED_WORDS_REVERSED = Hash[RUBY_RESERVED_WORDS.map { |k, v| [v, k] }]

  def self.protect_reserved_name(name)
    RUBY_RESERVED_WORDS[name] || name
  end

  def self.unprotect_reserved_name(name)
    RUBY_RESERVED_WORDS_REVERSED[name] || name
  end

  def remove_common_namespace(namespace_segments, name)
    segments = name.split(TypeFormatter::NAME_SEGMENT_SEPARATOR)
    namespace_segments.size.times do |idx|
      break if segments.empty? || namespace_segments[idx] != segments[0]
      segments.shift
    end
    segments
  end

  def namespace_relative(namespace_segments, name)
    remove_common_namespace(namespace_segments, name).join(TypeFormatter::NAME_SEGMENT_SEPARATOR)
  end

  def create_class(obj)
    @dynamic_classes ||= Hash.new do |hash, key|
      cls = key.implementation_class(false)
      if cls.nil?
        rp = key.resolved_parent
        parent_class = rp.is_a?(PObjectType) ? rp.implementation_class : Object
        class_def = ''
        class_body(key, EMPTY_ARRAY, class_def)
        cls = Class.new(parent_class)
        cls.class_eval(class_def)
        cls.define_singleton_method(:_pcore_type) { return key }
        key.implementation_class = cls
      end
      hash[key] = cls
    end
    raise ArgumentError, "Expected a Puppet Type, got '#{obj.class.name}'" unless obj.is_a?(PAnyType)
    @dynamic_classes[obj]
  end

  def module_definition_from_typeset(typeset, *impl_subst)
    module_definition(
      typeset.types.values,
      "# Generated by #{self.class.name} from TypeSet #{typeset.name} on #{Date.new}\n",
      *impl_subst)
  end

  def module_definition(types, comment, *impl_subst)
    object_types, aliased_types = types.partition { |type| type.is_a?(PObjectType) }
    if impl_subst.empty?
      impl_names = implementation_names(object_types)
    else
      impl_names = object_types.map { |type| type.name.gsub(*impl_subst) }
    end

    # extract common implementation module prefix
    names_by_prefix = Hash.new { |hash, key| hash[key] = [] }
    index = 0
    min_prefix_length = impl_names.reduce(Float::INFINITY) do |len, impl_name|
      segments = impl_name.split(TypeFormatter::NAME_SEGMENT_SEPARATOR)
      leaf_name = segments.pop
      names_by_prefix[segments.freeze] << [index, leaf_name, impl_name]
      index += 1
      len > segments.size ? segments.size : len
    end
    min_prefix_length = 0 if min_prefix_length == Float::INFINITY

    common_prefix = []
    segments_array = names_by_prefix.keys
    min_prefix_length.times do |idx|
      segment = segments_array[0][idx]
      break unless segments_array.all? { |sn| sn[idx] == segment }
      common_prefix << segment
    end

    # Create class definition of all contained types
    bld = ''
    start_module(common_prefix, comment, bld)
    class_names = []
    names_by_prefix.each_pair do |seg_array, index_and_name_array|
      added_to_common_prefix = seg_array[common_prefix.length..-1]
      added_to_common_prefix.each { |name| bld << 'module ' << name << "\n" }
      index_and_name_array.each do |idx, name, full_name|
        scoped_class_definition(object_types[idx], name, bld, full_name, *impl_subst)
        class_names << (added_to_common_prefix + [name]).join(TypeFormatter::NAME_SEGMENT_SEPARATOR)
        bld << "\n"
      end
      added_to_common_prefix.size.times { bld << "end\n" }
    end

    aliases = Hash[aliased_types.map { |type| [type.name, type.resolved_type] }]
    end_module(common_prefix, aliases, class_names, bld)
    bld
  end

  def start_module(common_prefix, comment, bld)
    bld << '# ' << comment << "\n"
    common_prefix.each { |cp| bld << 'module ' << cp << "\n" }
  end

  def end_module(common_prefix, aliases, class_names, bld)
    # Emit registration of contained type aliases
    unless aliases.empty?
      bld << "Puppet::Pops::Pcore.register_aliases({\n"
      aliases.each { |name, type| bld << "  '" << name << "' => " << TypeFormatter.string(type.to_s) << "\n" }
      bld.chomp!(",\n")
      bld << "})\n\n"
    end

    # Emit registration of contained types
    unless class_names.empty?
      bld << "Puppet::Pops::Pcore.register_implementations([\n"
      class_names.each { |class_name| bld << '  ' << class_name << ",\n" }
      bld.chomp!(",\n")
      bld << "])\n\n"
    end
    bld.chomp!("\n")

    common_prefix.size.times { bld << "end\n" }
  end

  def implementation_names(object_types)
    object_types.map do |type|
      ir = Loaders.implementation_registry
      impl_name = ir.module_name_for_type(type)
      raise Puppet::Error, "Unable to create an instance of #{type.name}. No mapping exists to runtime object" if impl_name.nil?
      impl_name
    end
  end

  def class_definition(obj, namespace_segments, bld, class_name, *impl_subst)
    module_segments = remove_common_namespace(namespace_segments, class_name)
    leaf_name = module_segments.pop
    module_segments.each { |segment| bld << 'module ' << segment << "\n" }
    scoped_class_definition(obj,leaf_name, bld, class_name, *impl_subst)
    module_segments.size.times { bld << "end\n" }
    module_segments << leaf_name
    module_segments.join(TypeFormatter::NAME_SEGMENT_SEPARATOR)
  end

  def scoped_class_definition(obj, leaf_name, bld, class_name, *impl_subst)
    bld << 'class ' << leaf_name
    segments = class_name.split(TypeFormatter::NAME_SEGMENT_SEPARATOR)

    unless obj.parent.nil?
      if impl_subst.empty?
        ir = Loaders.implementation_registry
        parent_name = ir.module_name_for_type(obj.parent)
        raise Puppet::Error, "Unable to create an instance of #{obj.parent.name}. No mapping exists to runtime object" if parent_name.nil?
      else
        parent_name = obj.parent.name.gsub(*impl_subst)
      end
      bld << ' < ' << namespace_relative(segments, parent_name)
    end

    bld << "\n"
    bld << "  def self._pcore_type\n"
    bld << '    @_pcore_type ||= ' << namespace_relative(segments, obj.class.name) << ".new('" << obj.name << "', "
    bld << TypeFormatter.singleton.ruby('ref').indented(2).string(obj._pcore_init_hash(false)) << ")\n"
    bld << "  end\n"

    class_body(obj, segments, bld)

    bld << "end\n"
  end

  def class_body(obj, segments, bld)
    unless obj.parent.is_a?(PObjectType)
      bld << "\n  include " << namespace_relative(segments, Puppet::Pops::Types::PuppetObject.name) << "\n\n" # marker interface
      bld << "  def self.ref(type_string)\n"
      bld << '    ' << namespace_relative(segments, Puppet::Pops::Types::PTypeReferenceType.name) << ".new(type_string)\n"
      bld << "  end\n"
    end

    # Output constants
    constants, others = obj.attributes(true).values.partition { |a| a.kind == PObjectType::ATTRIBUTE_KIND_CONSTANT }
    constants = constants.select { |ca| ca.container.equal?(obj) }
    unless constants.empty?
      constants.each { |ca|
        bld << "\n  def self." << rname(ca.name) << "\n    _pcore_type['" << ca.name << "'].value\n  end\n"
        bld << "\n  def " << rname(ca.name) << "\n    self.class." << ca.name << "\n  end\n"
      }
    end

    init_params = others.reject { |a| a.kind == PObjectType::ATTRIBUTE_KIND_DERIVED }
    opt, non_opt = init_params.partition { |ip| ip.value? }
    derived_attrs, obj_attrs = others.select { |a| a.container.equal?(obj) }.partition { |ip| ip.kind == PObjectType::ATTRIBUTE_KIND_DERIVED }

    include_type = obj.equality_include_type? && !(obj.parent.is_a?(PObjectType) && obj.parent.equality_include_type?)
    if obj.equality.nil?
      eq_names = obj_attrs.reject { |a| a.kind == PObjectType::ATTRIBUTE_KIND_CONSTANT }.map(&:name)
    else
      eq_names = obj.equality
    end

    # Output type safe hash constructor
    bld << "\n  def self.from_hash(init_hash)\n"
    bld << '    from_asserted_hash(' << namespace_relative(segments, TypeAsserter.name) << '.assert_instance_of('
    bld << "'" << obj.label << " initializer', _pcore_type.init_hash_type, init_hash))\n  end\n\n  def self.from_asserted_hash(init_hash)\n    new"
    unless non_opt.empty? && opt.empty?
      bld << "(\n"
      non_opt.each { |ip| bld << "      init_hash['" << ip.name << "'],\n" }
      opt.each do |ip|
        if ip.value.nil?
          bld << "      init_hash['" << ip.name << "'],\n"
        else
          bld << "      init_hash.fetch('" << ip.name << "', "
          default_string(bld, ip)
          bld << "),\n"
        end
      end
      bld.chomp!(",\n")
      bld << ')'
    end
    bld << "\n  end\n"

    # Output type safe constructor
    bld << "\n  def self.create"
    if init_params.empty?
      bld << "\n    new"
    else
      bld << '('
      non_opt.each { |ip| bld << rname(ip.name) << ', ' }
      opt.each do |ip|
        bld << rname(ip.name) << ' = '
        default_string(bld, ip)
        bld << ', '
      end
      bld.chomp!(', ')
      bld << ")\n"
      bld << '    ta = ' << namespace_relative(segments, TypeAsserter.name) << "\n"
      bld << "    attrs = _pcore_type.attributes(true)\n"
      init_params.each do |a|
        bld << "    ta.assert_instance_of('" << a.container.name << '[' << a.name << ']'
        bld << "', attrs['" << a.name << "'].type, " << rname(a.name) << ")\n"
      end
      bld << '    new('
      non_opt.each { |a| bld << rname(a.name) << ', ' }
      opt.each { |a| bld << rname(a.name) << ', ' }
      bld.chomp!(', ')
      bld << ')'
    end
    bld << "\n  end\n"

    unless obj.parent.is_a?(PObjectType) && obj_attrs.empty?
      # Output attr_readers
      unless obj_attrs.empty?
        bld << "\n"
        obj_attrs.each { |a| bld << '  attr_reader :' << rname(a.name) << "\n" }
      end

      bld << "  attr_reader :hash\n" if obj.parent.nil?

      derived_attrs.each do |a|
        bld << "\n  def " << rname(a.name) << "\n"
        code_annotation = RubyMethod.annotate(a)
        ruby_body = code_annotation.nil? ? nil: code_annotation.body
        if ruby_body.nil?
          bld << "    raise Puppet::Error, \"no method is implemented for derived #{a.label}\"\n"
        else
          bld << '    ' << ruby_body << "\n"
        end
        bld << "  end\n"
      end

      if init_params.empty?
        bld << "\n  def initialize\n    @hash = " << obj.hash.to_s << "\n  end" if obj.parent.nil?
      else
        # Output initializer
        bld << "\n  def initialize"
        bld << '('
        non_opt.each { |ip| bld << rname(ip.name) << ', ' }
        opt.each do |ip|
          bld << rname(ip.name) << ' = '
          default_string(bld, ip)
          bld << ', '
        end
        bld.chomp!(', ')
        bld << ')'

        hash_participants = init_params.select { |ip| eq_names.include?(ip.name) }
        if obj.parent.nil?
          bld << "\n    @hash = "
          bld << obj.hash.to_s << "\n" if hash_participants.empty?
        else
          bld << "\n    super("
          super_args = (non_opt + opt).select { |ip| !ip.container.equal?(obj) }
          unless super_args.empty?
            super_args.each { |ip| bld << rname(ip.name) << ', ' }
            bld.chomp!(', ')
          end
          bld << ")\n"
          bld << '    @hash = @hash ^ ' unless hash_participants.empty?
        end
        unless hash_participants.empty?
          hash_participants.each { |a| bld << rname(a.name) << '.hash ^ ' if a.container.equal?(obj) }
          bld.chomp!(' ^ ')
          bld << "\n"
        end
        init_params.each { |a| bld << '    @' << rname(a.name) << ' = ' << rname(a.name) << "\n" if a.container.equal?(obj) }
        bld << "  end\n"
      end
    end

    unless obj_attrs.empty? && obj.parent.nil?
      bld << "\n  def _pcore_init_hash\n"
      bld << '    result = '
      bld << (obj.parent.nil? ? '{}' : 'super')
      bld << "\n"
      obj_attrs.each do |a|
        bld << "    result['" << a.name << "'] = @" << rname(a.name)
        if a.value?
          bld << ' unless '
          equals_default_string(bld, a)
        end
        bld << "\n"
      end
      bld << "    result\n  end\n"
    end

    content_participants = init_params.select { |a| content_participant?(a) }
    if content_participants.empty?
      unless obj.parent.is_a?(PObjectType)
        bld << "\n  def _pcore_contents\n  end\n"
        bld << "\n  def _pcore_all_contents(path)\n  end\n"
      end
    else
      bld << "\n  def _pcore_contents\n"
      content_participants.each do |cp|
        if array_type?(cp.type)
          bld << '    @' << rname(cp.name) << ".each { |value| yield(value) }\n"
        else
          bld << '    yield(@' << rname(cp.name) << ') unless @' << rname(cp.name)  << ".nil?\n"
        end
      end
      bld << "  end\n\n  def _pcore_all_contents(path, &block)\n    path << self\n"
      content_participants.each do |cp|
        if array_type?(cp.type)
          bld << '    @' << rname(cp.name) << ".each do |value|\n"
          bld << "      block.call(value, path)\n"
          bld << "      value._pcore_all_contents(path, &block)\n"
        else
          bld << '    unless @' << rname(cp.name) << ".nil?\n"
          bld << '      block.call(@' << rname(cp.name) << ", path)\n"
          bld << '      @' << rname(cp.name) << "._pcore_all_contents(path, &block)\n"
        end
        bld << "    end\n"
      end
      bld << "    path.pop\n  end\n"
    end

    # Output function placeholders
    obj.functions(false).each_value do |func|
      code_annotation = RubyMethod.annotate(func)
      if code_annotation
        body = code_annotation.body
        params = code_annotation.parameters
        bld << "\n  def " << rname(func.name)
        unless params.nil? || params.empty?
          bld << '(' << params << ')'
        end
        bld << "\n    " << body << "\n"
      else
        bld << "\n  def " << rname(func.name) << "(*args)\n"
        bld << "    # Placeholder for #{func.type}\n"
        bld << "    raise Puppet::Error, \"no method is implemented for #{func.label}\"\n"
      end
      bld << "  end\n"
    end

    unless eq_names.empty? && !include_type
      bld << "\n  def eql?(o)\n"
      bld << "    super &&\n" unless obj.parent.nil?
      bld << "    o.instance_of?(self.class) &&\n" if include_type
      eq_names.each { |eqn| bld << '    @' << rname(eqn) << '.eql?(o.' <<  rname(eqn) << ") &&\n" }
      bld.chomp!(" &&\n")
      bld << "\n  end\n  alias == eql?\n"
    end
  end

  def content_participant?(a)
    a.kind != PObjectType::ATTRIBUTE_KIND_REFERENCE && obj_type?(a.type)
  end

  def obj_type?(t)
    case t
    when PObjectType
      true
    when POptionalType
      obj_type?(t.optional_type)
    when PNotUndefType
      obj_type?(t.type)
    when PArrayType
      obj_type?(t.element_type)
    when PVariantType
      t.types.all? { |v| obj_type?(v) }
    else
      false
    end
  end

  def array_type?(t)
    case t
    when PArrayType
      true
    when POptionalType
      array_type?(t.optional_type)
    when PNotUndefType
      array_type?(t.type)
    when PVariantType
      t.types.all? { |v| array_type?(v) }
    else
      false
    end
  end

  def default_string(bld, a)
    case a.value
    when nil, true, false, Numeric, String
      bld << a.value.inspect
    else
      bld << "_pcore_type['" << a.name << "'].value"
    end
  end

  def equals_default_string(bld, a)
    case a.value
    when nil, true, false, Numeric, String
      bld << '@' << a.name << ' == ' << a.value.inspect
    else
      bld << "_pcore_type['" << a.name << "'].default_value?(@" << a.name << ')'
    end
  end

  def rname(name)
    RUBY_RESERVED_WORDS[name] || name
  end
end
end
end
