# frozen_string_literal: true

# Adds additional resources to the catalog and relationship graph that are
# generated by existing resources. There are two ways that a resource can
# generate additional resources, either through the #generate method or the
# #eval_generate method.
#
# @api private
class Puppet::Transaction::AdditionalResourceGenerator
  attr_writer :relationship_graph
  # [boolean] true if any resource has attempted and failed to generate resources
  attr_reader :resources_failed_to_generate

  def initialize(catalog, relationship_graph, prioritizer)
    @catalog = catalog
    @relationship_graph = relationship_graph
    @prioritizer = prioritizer
    @resources_failed_to_generate = false
  end

  def generate_additional_resources(resource)
    return unless resource.respond_to?(:generate)
    begin
      generated = resource.generate
    rescue => detail
      @resources_failed_to_generate = true
      resource.log_exception(detail, _("Failed to generate additional resources using 'generate': %{detail}") % { detail: detail })
    end
    return unless generated
    generated = [generated] unless generated.is_a?(Array)
    generated.collect! do |res|
      @catalog.resource(res.ref) || res
    end
    unless resource.depthfirst?
      # This is reversed because PUP-1963 changed how generated
      # resources were added to the catalog. It exists for backwards
      # compatibility only, and can probably be removed in Puppet 5
      #
      # Previously, resources were given sequential priorities in the
      # relationship graph. Post-1963, resources are added to the
      # catalog one by one adjacent to the parent resource. This
      # causes an implicit reversal of their application order from
      # the old code. The reverse makes it all work like it did.
      generated.reverse!
    end
    generated.each do |res|
      add_resource(res, resource)

      add_generated_directed_dependency(resource, res)
      generate_additional_resources(res)
    end
  end

  def eval_generate(resource)
    return false unless resource.respond_to?(:eval_generate)
    raise Puppet::DevError, _("Depthfirst resources are not supported by eval_generate") if resource.depthfirst?
    begin
      generated = replace_duplicates_with_catalog_resources(resource.eval_generate)
      return false if generated.empty?
    rescue => detail
      @resources_failed_to_generate = true
      #TRANSLATORS eval_generate is a method name and should be left untranslated
      resource.log_exception(detail, _("Failed to generate additional resources using 'eval_generate': %{detail}") % { detail: detail })
      return false
    end
    add_resources(generated, resource)

    made = Hash[generated.map(&:name).zip(generated)]
    contain_generated_resources_in(resource, made)
    connect_resources_to_ancestors(resource, made)

    true
  end

  private

  def replace_duplicates_with_catalog_resources(generated)
    generated.collect do |generated_resource|
      @catalog.resource(generated_resource.ref) || generated_resource
    end
  end

  def contain_generated_resources_in(resource, made)
    sentinel = Puppet::Type.type(:whit).new(:name => "completed_#{resource.title}", :catalog => resource.catalog)
    # Tag the completed whit with all of the tags of the generating resource
    # except the type name to allow event propogation to succeed beyond the whit
    # "boundary" when filtering resources with tags. We include auto-generated
    # tags such as the type name to support implicit filtering as well as
    # explicit. Note that resource#tags returns a duplicate of the resource's
    # tags.
    sentinel.merge_tags_from(resource)
    priority = @prioritizer.generate_priority_contained_in(resource, sentinel)
    @relationship_graph.add_vertex(sentinel, priority)

    redirect_edges_to_sentinel(resource, sentinel, made)

    made.values.each do |res|
      # This resource isn't 'completed' until each child has run
      add_conditional_directed_dependency(res, sentinel, Puppet::Graph::RelationshipGraph::Default_label)
    end

    # This edge allows the resource's events to propagate, though it isn't
    # strictly necessary for ordering purposes
    add_conditional_directed_dependency(resource, sentinel, Puppet::Graph::RelationshipGraph::Default_label)
  end

  def redirect_edges_to_sentinel(resource, sentinel, made)
    @relationship_graph.adjacent(resource, :direction => :out, :type => :edges).each do |e|
      next if made[e.target.name]

      @relationship_graph.add_relationship(sentinel, e.target, e.label)
      @relationship_graph.remove_edge! e
    end
  end

  def connect_resources_to_ancestors(resource, made)
    made.values.each do |res|
      # Depend on the nearest ancestor we generated, falling back to the
      # resource if we have none
      parent_name = res.ancestors.find { |a| made[a] and made[a] != res }
      parent = made[parent_name] || resource

      add_conditional_directed_dependency(parent, res)
    end
  end

  def add_resources(generated, resource)
    generated.each do |res|
      priority = @prioritizer.generate_priority_contained_in(resource, res)
      add_resource(res, resource, priority)
    end
  end

  def add_resource(res, parent_resource, priority=nil)
    if @catalog.resource(res.ref).nil?
      res.merge_tags_from(parent_resource)
      if parent_resource.depthfirst?
        @catalog.add_resource_before(parent_resource, res)
      else
        @catalog.add_resource_after(parent_resource, res)
      end
      @catalog.add_edge(@catalog.container_of(parent_resource), res)
      if @relationship_graph && priority
        # If we have a relationship_graph we should add the resource
        # to it (this is an eval_generate). If we don't, then the
        # relationship_graph has not yet been created and we can skip
        # adding it.
        @relationship_graph.add_vertex(res, priority)
      end
      res.finish
    end
  end

  # add correct edge for depth- or breadth- first traversal of
  # generated resource. Skip generating the edge if there is already
  # some sort of edge between the two resources.
  def add_generated_directed_dependency(parent, child, label=nil)
    if parent.depthfirst?
      source = child
      target = parent
    else
      source = parent
      target = child
    end

    # For each potential relationship metaparam, check if parent or
    # child references the other. If there are none, we should add our
    # edge.
    edge_exists = Puppet::Type.relationship_params.any? { |param|
      param_sym = param.name.to_sym

      if parent[param_sym]
        parent_contains = parent[param_sym].any? { |res|
          res.ref == child.ref
        }
      else
        parent_contains = false
      end

      if child[param_sym]
        child_contains = child[param_sym].any? { |res|
          res.ref == parent.ref
        }
      else
        child_contains = false
      end

      parent_contains || child_contains
    }

    if not edge_exists
      # We *cannot* use target.to_resource here!
      #
      # For reasons that are beyond my (and, perhaps, human)
      # comprehension, to_resource will call retrieve. This is
      # problematic if a generated resource needs the system to be
      # changed by a previous resource (think a file on a path
      # controlled by a mount resource).
      #
      # Instead of using to_resource, we just construct a resource as
      # if the arguments to the Type instance had been passed to a
      # Resource instead.
      resource = ::Puppet::Resource.new(target.class, target.title,
                                        :parameters => target.original_parameters)

      source[:before] ||= []
      source[:before] << resource
    end
  end

  # Copy an important relationships from the parent to the newly-generated
  # child resource.
  def add_conditional_directed_dependency(parent, child, label=nil)
    @relationship_graph.add_vertex(child)
    edge = parent.depthfirst? ? [child, parent] : [parent, child]
    if @relationship_graph.edge?(*edge.reverse)
      parent.debug "Skipping automatic relationship to #{child}"
    else
      @relationship_graph.add_relationship(edge[0],edge[1],label)
    end
  end
end
