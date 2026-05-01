require "test_helper"

class AppTransferMailerTest < ActionMailer::TestCase
  test "request_email addresses target and references the app" do
    transfer = AppTransfer.create!(
      app_record: app_records(:one),
      from_user: users(:one),
      to_user: users(:two)
    )
    mail = AppTransferMailer.with(transfer: transfer).request_email
    assert_equal [ users(:two).email ], mail.to
    assert_match users(:one).email, mail.subject
    assert_match app_records(:one).name, mail.subject
    assert_match "Review and respond", mail.body.to_s
  end
end
