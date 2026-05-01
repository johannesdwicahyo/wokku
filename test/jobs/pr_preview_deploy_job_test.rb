require "test_helper"

class PrPreviewDeployJobTest < ActiveJob::TestCase
  setup do
    @parent_app = app_records(:one)
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      PrPreviewDeployJob.perform_later(
        parent_app_id: @parent_app.id,
        pr_number: 42,
        branch: "feature/my-pr",
        commit_sha: "abc123",
        pr_title: "My PR",
        repo_full_name: "owner/repo"
      )
    end
  end

  test "creates preview AppRecord before attempting deploy" do
    # The job saves the AppRecord (find_or_initialize_by + save!) before creating the
    # Deploy record, so even if a subsequent error occurs the app row is persisted.
    Dokku::Apps.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:create) { |_name| true }
    end

    Dokku::Config.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:list) { |_name| {} }
      define_method(:set) { |_name, _env| true }
    end

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run) { |_cmd| "" }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    # Job may raise due to SSH-dependent Dokku calls deeper in the stack.
    # We only care that the AppRecord was created before any failure.
    begin
      PrPreviewDeployJob.perform_now(
        parent_app_id: @parent_app.id,
        pr_number: 88,
        branch: "pr-branch",
        commit_sha: "abc123",
        pr_title: "Test PR",
        repo_full_name: "owner/repo"
      )
    rescue => e
      # Expected — SSH/Dokku calls fail in test
    end

    preview = AppRecord.find_by(name: "#{@parent_app.name}-pr-88")
    assert preview, "Expected preview AppRecord to have been persisted"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
    Dokku::Apps.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :create
    end
    Dokku::Config.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :list
      remove_method :set
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end
end
