module AsyncHelper

  # Instead of waiting an specific an amount of time and then
  # asserting for a certain behaviour, this test helper polls for an assertion
  # success every X number of seconds (configurable as interval).
  # The test will fail if the assertion doesn't pass after Y number of
  # seconds (configurable as timeout).
  def eventually(options = {})
    timeout    = options[:timeout] || 1 # seconds
    interval   = options[:interval] || 0.0001 # seconds
    time_limit = Time.now + timeout

    loop do
      begin
        yield
      rescue RSpec::Expectations::ExpectationNotMetError => error

      end

      return if error.nil?

      if Time.now >= time_limit
        raise error
      end
      sleep interval
    end
  end

  # Same behaviour as eventually, but decided to change the method name to make
  # it more clear that this is focused on 'synchronizing' the test with the application
  def wait_until(options = {}, &block)
    eventually(options, &block)
  end

  # Small wrapper around sleep
  def on_timeout(options = {})
    timeout = options[:timeout]   || 0.5

    sleep timeout

    yield
  end
end
