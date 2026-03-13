module Api
  module V1
    class BillingController < BaseController
      def current_plan
        plan = current_user.current_plan
        render json: {
          plan: plan&.name || "free",
          max_apps: plan&.max_apps || 5,
          max_databases: plan&.max_databases || 1
        }
      end

      def create_checkout
        plan = Plan.find(params[:plan_id])
        return render json: { error: "No Stripe price configured" }, status: :unprocessable_entity unless plan.stripe_price_id

        session = Stripe::Checkout::Session.create(
          mode: "subscription",
          customer_email: current_user.email,
          line_items: [{ price: plan.stripe_price_id, quantity: 1 }],
          success_url: "#{request.base_url}/billing/success?session_id={CHECKOUT_SESSION_ID}",
          cancel_url: "#{request.base_url}/billing"
        )
        render json: { url: session.url }
      end

      def portal
        customer = find_or_create_stripe_customer
        session = Stripe::BillingPortal::Session.create(
          customer: customer.id,
          return_url: "#{request.base_url}/billing"
        )
        render json: { url: session.url }
      end

      private

      def find_or_create_stripe_customer
        if current_user.stripe_customer_id.present?
          Stripe::Customer.retrieve(current_user.stripe_customer_id)
        else
          customer = Stripe::Customer.create(email: current_user.email)
          current_user.update!(stripe_customer_id: customer.id)
          customer
        end
      end
    end
  end
end
