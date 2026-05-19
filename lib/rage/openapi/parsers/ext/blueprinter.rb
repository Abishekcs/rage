# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Ext::Blueprinter
  def initialize(namespace: Object, root: Rage::OpenAPI::Nodes::Root.new, **)
    @namespace = namespace
    @root = root
  end

  def known_definition?(str)
    _, str = Rage::OpenAPI.__try_parse_collection(str)
    defined?(Blueprinter::Base) && @namespace.const_get(str).ancestors.include?(Blueprinter::Base)
  rescue NameError
    false
  end

  def parse(klass_str)
    _, raw_klass_str = Rage::OpenAPI.__try_parse_collection(klass_str)
    visitor = __parse(raw_klass_str)

    visitor.build_schema
  end

  def __parse(klass_str)
    _is_collection, klass_str = Rage::OpenAPI.__try_parse_collection(klass_str)

    klass = @namespace.const_get(klass_str)
    source_path, _ = Object.const_source_location(klass.name)
    ast = Prism.parse_file(source_path)

    visitor = Visitor.new(self)
    ast.value.accept(visitor)

    visitor
  end

  class VisitorContext
    attr_accessor :symbols, :hashes, :keywords

    def initialize
      @symbols = []
      @hashes = []
      @keywords = {}
    end
  end

  class Visitor < Prism::Visitor
    attr_accessor :schema

    def initialize(parser)
      @parser = parser

      @context = nil
      @schema = {}
      @segment = @schema

      @identifier = nil
    end

    def visit_class_node(node)
      @self_name ||= node.name.to_s
      super
    end

    def build_schema
      result = { "type" => "object" }
      @schema = { @identifier => { "type" => "string" }, **@schema } if @identifier
      result["properties"] = @schema if @schema.any?
      result
    end

    def visit_call_node(node)
      case node.name
      when :identifier
        context = with_context { visit(node.arguments) }
        @identifier = context.symbols.first

      when :fields, :field
        context = with_context { visit(node.arguments) }

        if context.keywords.any?
          @segment[context.keywords["name"].delete_prefix(":")] = { "type" => "string" }
        elsif node.block
          @segment[context.symbols.first] = { "type" => "string" }
        else
          context.symbols.each { |symbol| @segment[symbol] = { "type" => "string" } }
        end
      end
    end

    def visit_assoc_node(node)
      @context.keywords[node.key.value] = node.value.slice
    end

    def visit_symbol_node(node)
      return unless @context
      @context.symbols << node.value
    end

    private

    def with_context
      @context = VisitorContext.new
      yield
      @context
    end
  end
end
