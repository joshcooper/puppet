# The parent class of all AST objects that contain other AST objects.
# Everything but the really simple objects descend from this.  It is
# important to note that Branch objects contain other AST objects only --
# if you want to contain values, use a descendant of the AST::Leaf class.
#
# @api private
class Puppet::Parser::AST::Branch < Puppet::Parser::AST
  include Enumerable
  attr_accessor :pin
  attr_accessor :children

  def each(&block)
    @children.each(&block)
  end

  def initialize(children: [], **args)
    @children = children
    super(**args)
  end
end
