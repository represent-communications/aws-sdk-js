require 'nokogiri'

module Documentor
  def documentation(rules)
    docs = rules['documentation'] || ''
    docs = docs.gsub(/<!--.*?-->/m, '')
    docs = docs.gsub(/<examples?>.+?<\/examples?>/m, '')
    docs = docs.gsub(/<\/?note>/m, '')
    docs = docs.gsub(/\{(\S+)\}/, '`{\1}`')
    docs = docs.gsub(/\s+/, ' ').strip
    docs == '' ? nil : docs
  end
end

class ModelDocumentor
  include Documentor

  attr_reader :lines

  def initialize(klass, api)
    @lines = []
    @lines << ''
    @lines << <<-DOCS.strip
Constructs a service interface object. Each API operation is exposed as a
function on service.

### Sending a Request Using #{klass}

```javascript
var #{klass.downcase} = new AWS.#{klass}();
#{klass.downcase}.#{find_example_operation(api)}(params, function (err, data) {
  if (err) console.log(err, err.stack); // an error occurred
  else     console.log(data);           // successful response
});
```

### Locking the API Version

In order to ensure that the #{klass} object uses this specific API, you can
construct the object by passing the `apiVersion` option to the constructor:

```javascript
var #{klass.downcase} = new AWS.#{klass}({apiVersion: '#{api['apiVersion']}'});
```

You can also set the API version globally in `AWS.config.apiVersions` using
the **#{klass.downcase}** service identifier:

```javascript
AWS.config.apiVersions = {
  #{klass.downcase}: '#{api['apiVersion']}',
  // other service API versions
};

var #{klass.downcase} = new AWS.#{klass}();
```

@!method constructor(options = {})
  Constructs a service object. This object has one method for each
  API operation.

  @example Constructing a #{klass} object
    var #{klass.downcase} = new AWS.#{klass}({apiVersion: '#{api['apiVersion']}'});

  @option options [String] endpoint The endpoint URI to send requests
    to.  The default endpoint is built from the configured `region`.
    The endpoint should be a string like `'https://s3.amazonaws.com'`.
  @option (see AWS.Config.constructor)

@!attribute endpoint
  @return [AWS.Endpoint] an Endpoint object representing the endpoint URL
    for service requests.
DOCS
  end

  def find_example_operation(api)
    list = api['operations'].keys.grep(/describe|list|get/)
    list = api['operations'].keys if list.size == 0
    list.first
  end
end

class MethodDocumentor

  include Documentor

  attr_reader :lines

  def initialize(operation, api, klass)
    desc = documentation(operation)
    desc ||= "Calls the #{method_name(operation, false)} API operation."
    desc = desc.gsub(/^\s+/, '').strip

    @lines = [desc, '']

    ## @param tags

    @lines << "@param params [Object]"
    @lines += shapes(operation['input']).map {|line| "  " + line }

    ## @example tag

    @lines << "@example Calling the #{method_name(operation)} operation"
    @lines << generate_example(klass, method_name(operation),
                operation['input']).split("\n").map {|line| "  " + line }
    @lines << ""

    ## @callback tag

    @lines << "@callback callback function(err, data)"
    @lines << "  Called when a response from the service is returned. If a"
    @lines << "  callback is not supplied, you must call {AWS.Request.send}"
    @lines << "  on the returned request object to initiate the request."
    @lines << "  @param err [Error] the error object returned from the request."
    @lines << "    Set to `null` if the request is successful."
    @lines << "  @param data [Object] the de-serialized data returned from"
    @lines << "    the request. Set to `null` if a request error occurs."

    output = shapes(operation['output'])
    output = output.map {|line| "    " + line }
    if output.size > 0
      @lines << "    The `data` object has the following properties:"
      @lines << ""
      @lines += output
    end

    ## @return tag

    @lines << "@return [AWS.Request] a handle to the operation request for"
    @lines << "  subsequent event callback registration."

    if operation['documentation_url']
      @lines << "@see #{operation['documentation_url']}"
      @lines << "  #{api['serviceAbbreviation']} Documentation for #{operation['name']}"
    end
  end

  def method_name(operation, downcased = true)
    name = operation['name']
    name = name.sub(/\d{4}_\d{2}_\d{2}$/, '')
    downcased ? name[0].downcase + name[1..-1] : name
  end

  def shapes(rules)
    if rules and rules['members']
      rules['members'].map do |name, member_rules|
        ShapeDocumentor.new(member_rules, :name => name).lines
      end.flatten
    else
      []
    end
  end

  def generate_example(klass, name, input)
    ExampleShapeVisitor.new.example(klass, name, input)
  end

end

class ExampleShapeVisitor
  def initialize(required_only = false)
    @required_only = required_only
  end

  def example(klass, name, input)
    lines = []
    params = traverse(input)
    params_var = ""
    if params.strip.length > 0
      lines << "var params = " + params + ";"
      params_var = "params, "
    end
    lines << "#{klass.downcase}.#{name}(#{params_var}function(err, data) {"
    lines << "  if (err) console.log(err, err.stack); // an error occurred"
    lines << "  else     console.log(data);           // successful response"
    lines << "}"
    lines.join("\n")
  end

  def traverse(node)
    if (meth = "visit_" + (node['type'] || 'string')) && respond_to?(meth)
      return send(meth, node)
    end
    ""
  end

  def visit_structure(node)
    lines = ["{" + (node['required'] ? " // required" : "")]
    node['members'].sort_by {|n, v| [v['required'] ? -1 : 1, n] }.each do |key, value|
      next if @required_only && !value['required']
      lines << "  #{key}: " + indent(traverse(value), false) + "," +
        (value['required'] && !%w(list map structure).include?(value['type']) ?
          " // required" : "")
    end
    lines << "}"
    lines.join("\n")
  end

  def visit_list(node)
    lines = ["[" + (node['required'] ? " // required" : "")]
    lines << indent(traverse(node['members'])) + ","
    lines << "  // ... more items ..."
    lines << "]"
    lines.join("\n")
  end

  def visit_map(node)
    lines = ["{" + (node['required'] ? " // required" : "")]
    lines << indent("someKey: " + traverse(node['members'])) + ","
    lines << "  // anotherKey: ..."
    lines << "}"
    lines.join("\n")
  end

  def visit_string(node)
    value = node['enum'] ? node['enum'].join(' | ') : 'STRING_VALUE'
    "'#{value}'"
  end

  def visit_integer(node)
    "0"
  end
  alias visit_long visit_integer

  def visit_float(node)
    "0.0"
  end
  alias visit_double visit_float
  alias visit_bigdecimal visit_float

  def visit_boolean(node)
    "true || false"
  end

  def visit_base64(node)
    "'BASE64_ENCODED_STRING'"
  end

  def visit_binary(node)
    "new Buffer('...') || streamObject || 'STRING_VALUE'"
  end

  def visit_timestamp(node)
    "new Date || 'Wed Dec 31 1969 16:00:00 GMT-0800 (PST)' || 123456789"
  end

  def indent(text, first_line = true, n = 2)
    text = text.split(/\r?\n/).map {|l| "#{' ' * n}#{l}" }.join("\n")
    text = text.sub(/\A\s+/, '') if !first_line
    text
  end
end

class ShapeDocumentor
  include Documentor

  attr_reader :name
  attr_reader :rules
  attr_reader :lines
  attr_reader :nested_lines
  attr_reader :prefix
  attr_reader :type

  def initialize(rules, options = {})

    @rules = rules
    @name = options[:name]
    @prefix = options[:prefix] || ''

    @type =
      case rules['type']
      when 'structure' then 'map'
      when 'list' then 'Array'
      when 'map' then 'map'
      when 'string', nil then 'String'
      when 'integer' then 'Integer'
      when 'long' then 'Integer'
      when 'float' then 'Float'
      when 'double' then 'Float'
      when 'bigdecimal' then 'Float'
      when 'boolean' then 'Boolean'
      when 'base64' then 'Base64 Encoded String'
      when 'binary' then 'Buffer'
      when 'timestamp' then 'Date'
      else raise "unhandled type: #{rules['type']}"
      end

    # TODO : update this format description once we add streaming uploads
    @type = 'String' if streaming?

    @lines = []
    @nested_lines = []

    if structure?
      rules['members'].each_pair do |name, member_rules|
        @nested_lines += child_shape(member_rules, :name => name).lines
      end
    end

    if list?
      child = child_shape(rules['members'] || {}, :prefix => prefix)
      @type << "<#{child.type}>"
      @nested_lines += child.nested_lines
    end

    if map?

      # sanity check, I don't think this should ever raise, but if it
      # does we will have to document the key shape
      key_child = child_shape(rules['keys'] || {}, :prefix => prefix)
      raise "unhandled map key type" if key_child.type != 'String'

      child = child_shape(rules['members'] || {}, :prefix => prefix)
      @type << "<#{child.type}>"
      @nested_lines += child.nested_lines

    end

    @lines = ["#{prefix}* `#{name}` #{description}"]
    @lines += @nested_lines

    if rules['enum']
      @lines << "#{prefix}   Possible values include:"
      @lines += rules['enum'].map{|v| "#{prefix}   * `#{v.inspect}`" }
    end

  end

  def streaming?
    rules['payload'] and rules['type'] == 'blob'
  end

  def structure?
    rules['type'] == 'structure'
  end

  def list?
    rules['type'] == 'list'
  end

  def map?
    rules['type'] == 'map'
  end

  def description
    text = []
    if rules['required']
      text << "&mdash; **required** &mdash; (`#{@type}`)"
    else
      text << "&mdash; (`#{@type}`)"
    end
    if docs = documentation(rules)
      text << " #{docs}"
    end
    text.join(' ')
  end

  private

  def child_shape(rules, options = {})
    ShapeDocumentor.new(rules, { :prefix => prefix + '    ' }.merge(options))
  end
end
