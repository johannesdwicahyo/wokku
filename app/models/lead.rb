class Lead < ApplicationRecord
  belongs_to :user, optional: true

  validates :pain_text, presence: true, length: { maximum: 5_000 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  CHANNELS = %w[form wa].freeze
  validates :channel, inclusion: { in: CHANNELS }, allow_nil: true
end
