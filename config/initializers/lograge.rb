Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    {
      request_id: event.payload[:request_id],
      params: event.payload[:params].except('controller', 'action', 'format', 'id')
    }
  end
end
