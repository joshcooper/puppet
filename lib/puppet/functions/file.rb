Puppet::Functions.create_function(:file, Puppet::Functions::InternalFunction) do
  dispatch :file do
    scope_param
    param 'String', :path
  end

  def file(scope, unresolved_path)
    path = Puppet::Parser::Files.find_file(unresolved_path, scope.compiler.environment)
    unless path && Puppet::FileSystem.exist?(path)
      #TRANSLATORS the string "file()" should not be translated
      raise Puppet::ParseError, _("file(): The given file '%{unresolved_path}' does not exist") % { unresolved_path: unresolved_path }
    end
    content = Puppet::FileSystem.binread(path)
    content.force_encoding!(Encoding::UTF_8)
    content
  end
end
