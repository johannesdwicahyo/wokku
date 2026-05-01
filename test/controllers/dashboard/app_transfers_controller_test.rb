require "test_helper"

class Dashboard::AppTransfersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = users(:one)
    @target = users(:two)
    @app = app_records(:one) # owned by users(:one) via team
  end

  test "POST apps#transfer creates a pending AppTransfer instead of flipping ownership" do
    sign_in @owner
    assert_difference -> { AppTransfer.count }, +1 do
      assert_enqueued_emails 1 do
        post transfer_dashboard_app_path(@app), params: { email: @target.email }
      end
    end
    transfer = AppTransfer.last
    assert_equal "pending", transfer.status
    assert_equal @owner.id, transfer.from_user_id
    assert_equal @target.id, transfer.to_user_id
    # Ownership unchanged.
    assert_equal @owner.teams.first.id, @app.reload.team_id
  end

  test "POST apps#transfer rejects a second pending transfer for the same app" do
    sign_in @owner
    AppTransfer.create!(app_record: @app, from_user: @owner, to_user: @target)
    assert_no_difference -> { AppTransfer.count } do
      post transfer_dashboard_app_path(@app), params: { email: @target.email }
    end
    assert_match(/already pending/i, flash[:alert].to_s)
  end

  test "accept rotates ownership and marks transfer accepted" do
    transfer = AppTransfer.create!(app_record: @app, from_user: @owner, to_user: @target)
    sign_in @target

    AppOwnershipTransfer.expects(:call).with(app: @app, target_user: @target).returns(
      AppOwnershipTransfer::Result.new(ok?: true, error: nil)
    )

    post accept_dashboard_app_transfer_path(transfer)
    assert_response :redirect
    assert_equal "accepted", transfer.reload.status
    assert_not_nil transfer.accepted_at
  end

  test "decline marks declined and leaves ownership untouched" do
    transfer = AppTransfer.create!(app_record: @app, from_user: @owner, to_user: @target)
    sign_in @target
    post decline_dashboard_app_transfer_path(transfer)
    assert_response :redirect
    assert_equal "declined", transfer.reload.status
    assert_equal @owner.teams.first.id, @app.reload.team_id
  end

  test "destroy lets the source-owner cancel their pending transfer" do
    transfer = AppTransfer.create!(app_record: @app, from_user: @owner, to_user: @target)
    sign_in @owner
    delete dashboard_app_transfer_path(transfer)
    assert_response :redirect
    assert_equal "cancelled", transfer.reload.status
  end

  test "non-target cannot accept" do
    transfer = AppTransfer.create!(app_record: @app, from_user: @owner, to_user: @target)
    sign_in users(:admin)
    post accept_dashboard_app_transfer_path(transfer)
    assert_response :redirect
    assert_equal "pending", transfer.reload.status
  end
end
