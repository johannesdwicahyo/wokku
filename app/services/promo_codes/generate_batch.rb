module PromoCodes
  class GenerateBatch
    Result = Struct.new(:ok?, :batch_id, :codes, :error, keyword_init: true)

    MAX_COUNT = 100
    PREFIX_RE = /\A[A-Z0-9-]{1,16}\z/
    LABEL_MAX = 80
    SUFFIX_LEN = 7
    MAX_RETRIES = 3

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(count:, prefix:, batch_label:, kind:, redeemer_bonus_idr:,
                   inviter_bonus_idr:, expires_at:, description:, created_by:,
                   min_deposit_idr: nil) # legacy kwarg accepted + ignored
      @count = count.to_i
      @prefix = prefix.to_s.strip.upcase
      @batch_label = batch_label.to_s.strip
      @kind = kind
      @redeemer_bonus_idr = redeemer_bonus_idr.to_i
      @inviter_bonus_idr = inviter_bonus_idr.to_i
      @expires_at = expires_at
      @description = description.presence
      @created_by = created_by
    end

    def call
      err = validate
      return failure(err) if err

      batch_id = SecureRandom.uuid
      created = []

      ActiveRecord::Base.transaction do
        @count.times do
          created << create_one!(batch_id)
        end
      end

      Result.new(ok?: true, batch_id: batch_id, codes: created, error: nil)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      failure("Could not generate batch — please retry (#{e.message})")
    end

    private

    def validate
      return "Count must be between 1 and #{MAX_COUNT}." unless @count.between?(1, MAX_COUNT)
      return "Prefix must be 1–16 chars, A–Z/0–9/dash only." unless @prefix.match?(PREFIX_RE)
      return "Batch label is required." if @batch_label.blank?
      return "Batch label must be #{LABEL_MAX} chars or less." if @batch_label.length > LABEL_MAX
      return "Invalid kind." unless PromoCode::KINDS.include?(@kind)
      nil
    end

    def create_one!(batch_id)
      MAX_RETRIES.times do
        code = "#{@prefix}-#{SecureRandom.alphanumeric(SUFFIX_LEN).upcase}"
        record = PromoCode.new(
          code: code,
          kind: @kind,
          redeemer_bonus_idr: @redeemer_bonus_idr,
          inviter_bonus_idr: @inviter_bonus_idr,
          max_redemptions: 1,
          expires_at: @expires_at,
          description: @description,
          created_by: @created_by,
          batch_id: batch_id,
          batch_label: @batch_label
        )
        return record if record.save
        # retry on uniqueness collision; raise on any other error
        raise ActiveRecord::RecordInvalid.new(record) unless record.errors.of_kind?(:code, :taken)
      end
      raise ActiveRecord::RecordNotUnique, "Could not generate a unique code after #{MAX_RETRIES} retries"
    end

    def failure(msg)
      Result.new(ok?: false, batch_id: nil, codes: [], error: msg)
    end
  end
end
