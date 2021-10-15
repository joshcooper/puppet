
class Puppet::Pops::Parser::CodeMerger

  # Concatenates the logic in the array of parse results into one parse result.
  # @return Puppet::Parser::AST::BlockExpression
  #
  def concatenate(parse_results, block_expr = nil)
    # this is a bit brute force as the result is already 3x ast with wrapped 4x content
    # this could be combined in a more elegant way, but it is only used to process a handful of files
    # at the beginning of a puppet run. TODO: Revisit for Puppet 4x when there is no 3x ast at the top.
    # PUP-5299, some sites have thousands of entries, and run out of stack when evaluating - the logic
    # below maps the logic as flatly as possible.
    #
    children = block_expr ? block_expr.children : []
    parse_results.each do |x|
      next if x.nil? || x.code.nil?

      case x.code
      when Puppet::Parser::AST::BlockExpression
        # the BlockExpression wraps a single 4x instruction that is most likely wrapped in a Factory
        children.concat(x.code.children)
#        parsed_class.code.children.map {|c| c.is_a?(Puppet::Pops::Model::Factory) ? c.model : c }
      when Puppet::Pops::Model::Factory
        # If it is a 4x instruction wrapped in a Factory
        children << x.code.model
      else
        # It is the instruction directly
        children << x.code
      end
    end
    if block_expr
      block_expr
    else
      Puppet::Parser::AST::BlockExpression.new(:children => children)
    end
  end
end
