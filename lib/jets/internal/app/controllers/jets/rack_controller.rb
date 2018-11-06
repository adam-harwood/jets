class Jets::RackController < Jets::Controller::Base
  layout false
  internal true

  # Megamode
  def process
    # puts "PARAMS:".colorize(:yellow)
    # pp params
    # render json: {success: true}
    safe_event = event.dup
    safe_event['body'] = "POSSIBLE BINARY" # event['body'].force_encoding("UTF-8")

    puts "RackController SAFE EVENT:".colorize(:yellow)
    puts JSON.dump(safe_event)

    resp = mega_request
    render(resp)
  end

private
  # Override process! so it doesnt go through middleware adapter and hits
  # process logic directly. This handles the case for AWS Lambda.
  # For local server, we adjust the Middleware::Local logic.
  def process!
    status, headers, body = dispatch!
    # Use the adapter only to convert the Rack triplet to a API Gateway hash structure
    adapter = Jets::Controller::Rack::Adapter.new(event, context, meth)
    adapter.convert_to_api_gateway(status, headers, body)
  end

  def mega_request
    Jets::Mega::Request.new(event, self).proxy
  end
end