module Webhooks
  class StripeController < ActionController::API
    def create
      payload = request.body.read
      sig_header = request.headers["Stripe-Signature"]

      begin
        event = Stripe::Webhook.construct_event(payload, sig_header, ENV["STRIPE_WEBHOOK_SECRET"])
      rescue JSON::ParserError, Stripe::SignatureVerificationError
        return head :bad_request
      end

      case event.type
      when "checkout.session.completed"
        handle_checkout_completed(event.data.object)
      when "invoice.paid"
        handle_invoice_paid(event.data.object)
      when "invoice.payment_failed"
        handle_payment_failed(event.data.object)
      when "customer.subscription.updated"
        handle_subscription_updated(event.data.object)
      when "customer.subscription.deleted"
        handle_subscription_deleted(event.data.object)
      end

      head :ok
    end

    private

    def handle_checkout_completed(session)
      user = User.find_by(email: session.customer_email)
      return unless user

      stripe_sub = Stripe::Subscription.retrieve(session.subscription)
      plan = Plan.find_by(stripe_price_id: stripe_sub.items.data.first.price.id)
      return unless plan

      user.subscriptions.create!(
        plan: plan,
        status: :active,
        stripe_subscription_id: stripe_sub.id,
        current_period_end: Time.at(stripe_sub.current_period_end)
      )
    end

    def handle_invoice_paid(invoice)
      user = User.find_by(stripe_customer_id: invoice.customer)
      return unless user

      user.invoices.create!(
        amount_cents: invoice.amount_paid,
        status: :paid,
        stripe_invoice_id: invoice.id,
        paid_at: Time.current
      )
    end

    def handle_payment_failed(invoice)
      user = User.find_by(stripe_customer_id: invoice.customer)
      return unless user

      sub = user.subscriptions.find_by(stripe_subscription_id: invoice.subscription)
      sub&.update!(status: :past_due)
    end

    def handle_subscription_updated(subscription)
      sub = Subscription.find_by(stripe_subscription_id: subscription.id)
      return unless sub

      new_plan = Plan.find_by(stripe_price_id: subscription.items.data.first.price.id)
      sub.update!(
        plan: new_plan,
        status: subscription.status == "active" ? :active : :past_due,
        current_period_end: Time.at(subscription.current_period_end)
      )
    end

    def handle_subscription_deleted(subscription)
      sub = Subscription.find_by(stripe_subscription_id: subscription.id)
      sub&.update!(status: :canceled)
    end
  end
end
