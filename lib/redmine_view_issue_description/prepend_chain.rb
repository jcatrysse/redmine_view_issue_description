# frozen_string_literal: true

module RedmineViewIssueDescription
  # Patches a core method with prepend instead of an alias_method chain (Jan's
  # general decision of 2026-10-07: mixing both on one method recurses).
  #
  # The plugin's logic keeps its names: `with` holds it and calls `without`
  # for the original. Here a named module, prepended to klass, routes `name`
  # to `with` and answers `without` with the next method in the chain after
  # this module (core's, or that of a plugin prepended before this one), so a
  # plugin that later prepends or aliases the same method stacks on top of it.
  module PrependChain
    def self.wrap(klass, const_name, name, with:, without:)
      return if const_defined?(const_name, false) && klass.ancestors.include?(const_get(const_name, false))

      mod = Module.new
      mod.define_method(name) { |*args, &block| send(with, *args, &block) }
      mod.define_method(without) do |*args, &block|
        mod.instance_method(name).bind(self).super_method.call(*args, &block)
      end
      if klass.private_method_defined?(name)
        mod.send(:private, name, without)
      elsif klass.protected_method_defined?(name)
        mod.send(:protected, name, without)
      end
      const_set(const_name, mod)
      klass.prepend(mod)
    end
  end
end
