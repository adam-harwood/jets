require 'net/http'
require 'rack'

module Jets::Mega
  class Request
    extend Memoist

    def initialize(event, controller)
      @event = event
      @controller = controller # Jets::Controller instance
    end

    def proxy
      http_method = @event['httpMethod'] # GET, POST, PUT, DELETE, etc
      params = @controller.params(raw: true, path_parameters: false)

      url = "http://localhost:9292#{@controller.request.path}"
      unless @controller.query_parameters.empty?
        # Thanks: https://stackoverflow.com/questions/798710/ruby-how-to-turn-a-hash-into-http-parameters
        query_string = Rack::Utils.build_nested_query(@controller.query_parameters)
        url += "?#{query_string}"
      end
      uri = URI(url) # local rack server

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 60
      http.read_timeout = 60

      # Rails sets _method=patch or _method=put as workaround
      # Falls back to GET when testing in lambda console
      http_class = params['_method'] || http_method || 'GET'
      http_class.capitalize!

      request_class = "Net::HTTP::#{http_class}".constantize # IE: Net::HTTP::Get
      request = request_class.new(uri.path)
      if %w[Post Patch Put].include?(http_class)
        params = HashConverter.encode(params)
        request.set_form_data(params)
      end

      request = set_headers!(request)

      # Setup body
      env = Jets::Controller::Rack::Env.new(@event, {}).convert # convert to Rack env
      source_request = Rack::Request.new(env)
      if source_request.body.respond_to?(:read)
        request.body = source_request.body.read
        request.content_length = source_request.content_length.to_i
        source_request.body.rewind
      end

      response = http.request(request)

      # # TODO: handle binary
      # content_type = @event["headers"]["content-type"]
      # if content_type&.include?("multipart/form-data")
      #   response = send_multipart_request(http, uri)
      # else
      #   response = send_normal_request(http, uri)
      # end

      {
        status: response.code.to_i,
        headers: response.each_header.to_h,
        body: response.body,
      }
    end

    def send_multipart_request(http, uri)
      # map = { "Patch" => "Put" } # not all classes are available with Multipart library
      # multi_class = map[http_class] || http_class
      # # IE: Net::HTTP::Post::Multipart
      # klass = "Net::HTTP::#{multi_class}::Multipart".constantize

      # path = File.expand_path("#{Jets.root}rack/jets-mega.png")
      # png = File.read(path, 'rb')
      request = Net::HTTP::Patch.new(uri,
        {}
        # "user[avatar]" => UploadIO.new(png, "image/png", "jets-mega.png")
      )
      request = set_headers!(request)

      request.body = @event['body'] # weird works locally but not with AWS Lambda
      puts "rack#request @event['body'].class #{@event['body'].class}"
      puts "request.body.class #{request.body.class}"

      # request['Content-Length'] = 123
      # request['content-length'] = 123
      # pp request

      # response = http.request(request)
      # response
      Net::HTTP.start(uri.host, uri.port) do |h|
        h.request(request)
      end
    end

    def send_normal_request(http, uri)
      # IE: Net::HTTP::Get, Net::HTTP::Post, etc
      klass = "Net::HTTP::#{http_class}".constantize
      request = klass.new(uri)
      request = set_normal_data!(request)
      request = set_headers!(request)
      http.request(request)
    end

    def set_normal_data!(request)
      return request unless %w[Post Patch Put].include?(http_class)
      return request unless content_type = @event["headers"]["content-type"]

      # content_type: multipart/form-data; boundary=----WebKitFormBoundarydhxvxyxg19TFYTcE
      puts "content_type: #{content_type}"
      if content_type.include?("application/x-www-form-urlencoded")
        form_data = HashConverter.encode(params)
        puts "form_data:".colorize(:yellow)
        pp form_data
        request.set_form_data(form_data)
      elsif content_type.include?("multipart")
        request.body = @event['body']
      end
      request
    end

    # Rails sets _method=patch or _method=put as workaround
    # Falls back to GET when testing in lambda console
    # @event['httpMethod'] is GET, POST, PUT, DELETE, etc
    def http_class
      http_class = params['_method'] || @event['httpMethod'] || 'GET'
      http_class.capitalize!
      http_class
    end

    def params
      @controller.params(raw: true, path_parameters: false, body_parameters: true)
    end
    memoize :params

    # Set request headers. Forwards original request info from remote API gateway.
    # By this time, the server/api_gateway.rb middleware.
    def set_headers!(request)
      headers = @event['headers'] # from api gateway
      if headers # remote API Gateway
        # Forward headers from API Gateway over to the sub http request.
        # It's important to forward the headers. Here are some examples:
        #
        #   "Turbolinks-Referrer"=>"http://localhost:8888/posts/122",
        #   "Referer"=>"http://localhost:8888/posts/122",
        #   "Accept-Encoding"=>"gzip, deflate",
        #   "Accept-Language"=>"en-US,en;q=0.9,pt;q=0.8",
        #   "Cookie"=>"_demo_session=...",
        #   "If-None-Match"=>"W/\"9fa479205fc6d24ca826d46f1f6cf461\"",
        headers.each do |k,v|
          request[k] = v
        end

        # Note by the time headers get to rack later in the they get changed to:
        #
        #   request['X-Forwarded-Host'] vs env['HTTP_X_FORWARDED_HOST']
        #
        request['X-Forwarded-For'] = headers['X-Forwarded-For'] # "1.1.1.1, 2.2.2.2" # can be comma separated list
        request['X-Forwarded-Host'] = headers['Host'] # uhghn8z6t1.execute-api.us-east-1.amazonaws.com
        request['X-Forwarded-Port'] = headers['X-Forwarded-Port'] # 443
        request['X-Forwarded-Proto'] = headers['X-Forwarded-Proto'] # https # scheme
      end

      request
    end
  end
end
