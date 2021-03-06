require 'rubocop'

module RuboCop
  module Lint
    class MissingKeysOnSharedArea < RuboCop::Cop::Cop
      MISSING_KEYS_MSG = "Found %<key>s in 'SharedValues' but not in 'output' method. Keys in the 'output' method: %<list>s".freeze
      MISSING_OUTPUT_METHOD_MSG = "There are declared keys on the shared area 'SharedValues', but 'output' method has not been found".freeze

      def_node_search :extract_const_assignment, <<-PATTERN
        (casgn nil? $_ ...)
      PATTERN

      def_node_matcher :find_output_method, <<-PATTERN
        (defs (self) :output ...)
      PATTERN

      attr_writer :shared_values_constants
      def shared_values_constants
        @shared_values_constants ||= []
      end

      def on_module(node)
        name, body = *node
        return unless name.source == 'SharedValues'
        return if body.nil?

        consts = extract_const_assignment(node)
        consts.each { |const| self.shared_values_constants << const.to_s }
      end

      def on_defs(node)
        return if self.shared_values_constants.empty?
        return unless find_output_method(node)

        _definee, _method_name, _args, body = *node
        return add_offense(node, :expression, format(MISSING_KEYS_MSG, key: self.shared_values_constants.join(', '), list: [])) if body.nil?
        return add_offense(node, :expression, format(MISSING_KEYS_MSG, key: self.shared_values_constants.join(', '), list: [])) unless body.array_type?

        children = body.children.select(&:array_type?)
        keys = children.map { |child| child.children.first.source.to_s.gsub(/\s|"|'/, '') }
        add_offense(node, :expression, format(MISSING_KEYS_MSG, key: self.shared_values_constants.join(', '), list: keys.join(', '))) unless self.shared_values_constants.to_set == keys.to_set
      end

      def on_class(node)
        _name, superclass, body = *node
        return unless superclass
        return unless superclass.loc.name.source == 'Action'

        add_offense(node, :expression, MISSING_OUTPUT_METHOD_MSG) if body.nil? && self.shared_values_constants.any?
        return if body.nil?

        has_output_method?(body)
      end

      def has_output_method?(node)
        return if node.nil?
        return if self.shared_values_constants.empty?

        if node.defs_type? # A single method
          add_offense(node, :expression, MISSING_OUTPUT_METHOD_MSG) unless output_method?(node)
        elsif node.begin_type? # Multiple methods
          outputs = node.each_child_node(:defs).select { |n| output_method?(n) }
          add_offense(node, :expression, MISSING_OUTPUT_METHOD_MSG) if outputs.empty?
        end
      end

      def output_method?(node)
        _definee, method_name, _args, _body = *node
        method_name.to_s == 'output'
      end
    end
  end
end
