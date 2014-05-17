module AsyncHelper
  def eventually(options = {})
    timeout = options[:timeout]   || 1
    interval = options[:interval] || 0.0001
    time_limit = Time.now + timeout
    loop do
      begin
        yield
      rescue => error
      end
      return if error.nil?
      if Time.now >= time_limit
        raise error
      end
      sleep interval
    end
  end
end
