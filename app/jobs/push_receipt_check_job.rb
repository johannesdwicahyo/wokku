class PushReceiptCheckJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    client = Expo::Push::Client.new

    PushTicket.pending.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      ticket_ids = batch.map(&:ticket_id)
      ticket_map = batch.index_by(&:ticket_id)

      receipts = client.receipts(ticket_ids)

      receipts.each do |receipt|
        ticket = ticket_map[receipt.receipt_id]
        next unless ticket

        ticket.update!(checked_at: Time.current)
      end

      receipts.each_error do |receipt|
        next if receipt.is_a?(Expo::Push::Error)

        ticket = ticket_map[receipt.receipt_id]
        next unless ticket

        error_code = receipt.data.dig("details", "error")

        if error_code == "DeviceNotRegistered"
          Rails.logger.info("Removed invalid device token #{ticket.device_token_id}")
          ticket.device_token.destroy!
        else
          ticket.update!(checked_at: Time.current)
        end
      end
    end

    PushTicket.stale.delete_all
  rescue StandardError => e
    Rails.logger.warn("Push receipt check failed: #{e.message}")
  end
end
