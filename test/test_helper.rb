ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

# Force ActionCable::Server::Base to load now, deterministically, instead of
# whenever something in the suite first happens to reference it. Its file
# fires ActiveSupport's :action_cable load hook as a top-level statement at
# load time (`ActiveSupport.run_load_hooks(:action_cable, Base.config)` in
# actioncable's server/base.rb) — and turbo-rails only mixes
# Turbo::Broadcastable::TestHelper (assert_turbo_stream_broadcasts, etc.)
# into ActiveSupport::TestCase from *inside* that hook. Without this,
# whichever test happens to touch Action Cable first (e.g. rendering a view
# with turbo_stream_from) decides whether a later, unrelated model test can
# use those assertions at all — under Minitest's randomized test order,
# that's a real, reproducible flake (verified: seed 12345 passes, the
# default random seed doesn't), not a hypothetical one.
ActionCable::Server::Base

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
