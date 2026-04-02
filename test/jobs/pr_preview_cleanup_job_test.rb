require "test_helper"

class PrPreviewCleanupJobTest < ActiveJob::TestCase
  setup do
    @parent_app = app_records(:one)
    @server = @parent_app.server
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      PrPreviewCleanupJob.perform_later(
        parent_app_id: @parent_app.id,
        pr_number: 42
      )
    end
  end

  test "destroys preview app when it exists" do
    preview_name = "#{@parent_app.name}-pr-777"
    preview_app = AppRecord.create!(
      name: preview_name,
      server: @server,
      team: @parent_app.team,
      creator: @parent_app.creator,
      status: :running
    )

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
    end

    Dokku::Apps.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:destroy) { |_name| true }
    end

    assert_difference "AppRecord.count", -1 do
      PrPreviewCleanupJob.perform_now(
        parent_app_id: @parent_app.id,
        pr_number: 777
      )
    end

    assert_nil AppRecord.find_by(id: preview_app.id)
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
    Dokku::Apps.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :destroy
    end
  end

  test "returns early when preview app does not exist" do
    assert_nothing_raised do
      PrPreviewCleanupJob.perform_now(
        parent_app_id: @parent_app.id,
        pr_number: 99999
      )
    end
  end
end
