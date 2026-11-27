ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module ActionDispatch
  class IntegrationTest
    # start every request test with an empty cache so login rate limit counts
    # from one test can't block logins in the next
    setup { Rails.cache.clear }
  end
end


# Work around Chrome rejecting Capybara's wildcard storage reset.
# Close the browser so the next test starts with a fresh session.
require "capybara/selenium/driver_specializations/chrome_driver"

module ChromeStorageResetWorkaround
  def reset!
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError => error
    raise unless error.message.include?("* is not a valid URL")

    quit
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeStorageResetWorkaround)
