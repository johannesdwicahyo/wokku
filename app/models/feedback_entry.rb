class FeedbackEntry < ApplicationRecord
  belongs_to :user, optional: true

  validates :message, presence: true, length: { maximum: 5_000 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
end
