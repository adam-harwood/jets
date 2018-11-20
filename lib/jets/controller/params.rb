require "action_controller/metal/strong_parameters"
require "rack"

class Jets::Controller
  module Params
    extend Memoist

    # Merge all the parameters together for convenience.  Users still have
    # access via events.
    #
    # Precedence:
    #   1. path parameters have highest precdence
    #   2. query string parameters
    #   3. body parameters
    def params(raw: false, path_parameters: true, body_parameters: true)
      path_params = event["pathParameters"] || {}

      params = {}
      params = params.deep_merge(body_params) if body_parameters
      params = params.deep_merge(query_parameters) # always
      params = params.deep_merge(path_params) if path_parameters

      if raw
        params
      else
        ActionController::Parameters.new(params)
      end
    end

    def query_parameters
      event["queryStringParameters"] || {}
    end

    def body_params
      # puts "body_params 1"
      body = event['isBase64Encoded'] ? decode(event["body"]) : event["body"]
      # puts "body_params 2"
      return {} if body.nil?

      # Try json parsing
      # puts "body_params 3"
      parsed_json = parse_json(body)
      return parsed_json if parsed_json

      # puts "body_params 4"
      # For content-type application/x-www-form-urlencoded CGI.parse the body
      headers = event["headers"] || {}
      headers = headers.transform_keys { |key| key.downcase }
      # API Gateway seems to use either: content-type or Content-Type
      content_type = headers["content-type"]
      if content_type.to_s.include?("application/x-www-form-urlencoded")
        puts "parse application/x-www-form-urlencoded".colorize(:yellow)
        return ::Rack::Utils.parse_nested_query(body)
      elsif content_type.to_s.include?("multipart/form-data")
        puts "parse_multipart".colorize(:yellow)
        return parse_multipart(body)
      end

      puts "body_params 7"
      {} # fallback to empty Hash
    end
    memoize :body_params

  private

    def parse_multipart(body)
      boundary = ::Rack::Multipart::Parser.parse_boundary(headers["content-type"])
      # puts "boundary: #{boundary.inspect}"
      # if event['isBase64Encoded']
      #   puts "event[body] #{event['body']}"
      # else
      #   puts "body: #{body.inspect}"
      # end
      options = multipart_options(body, boundary)
      # puts "options: #{options.inspect}"

      env = ::Rack::MockRequest.env_for("/", options)
      # puts "env:"
      # pp env

      puts "env['CONTENT_TYPE'] #{env['CONTENT_TYPE'].inspect}"
      puts "env['CONTENT_LENGTH'] #{env['CONTENT_LENGTH'].inspect}"
      puts "env['rack.input'] #{env['rack.input'].inspect}"
      body = env['rack.input'].read
      puts "body.size #{body.size}"
      env['rack.input'].rewind

      params = ::Rack::Multipart.parse_multipart(env)
      params
    end

    def multipart_options(data, boundary = "AaB03x")
      type = %(multipart/form-data; boundary=#{boundary})
      length = data.bytesize

      { "CONTENT_TYPE" => type,
        "CONTENT_LENGTH" => length.to_s,
        :input => StringIO.new(data) }
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def decode(body)
      return nil if body.nil?
      Base64.decode64(body)
    end
  end
end
