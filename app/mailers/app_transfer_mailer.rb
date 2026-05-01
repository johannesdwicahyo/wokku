class AppTransferMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM_HELLO", "Wokku <hello@wokku.cloud>")

  def request_email
    @transfer = params[:transfer]
    @app      = @transfer.app_record
    @from     = @transfer.from_user
    @to       = @transfer.to_user
    @url      = dashboard_app_transfer_url(@transfer, host: host)
    mail(to: @to.email, subject: "[Wokku] #{@from.email} wants to transfer #{@app.name} to you")
  end

  def accepted_email
    @transfer = params[:transfer]
    @app      = @transfer.app_record
    mail(to: @transfer.from_user.email, subject: "[Wokku] #{@transfer.to_user.email} accepted ownership of #{@app.name}")
  end

  def declined_email
    @transfer = params[:transfer]
    @app      = @transfer.app_record
    mail(to: @transfer.from_user.email, subject: "[Wokku] #{@transfer.to_user.email} declined the transfer of #{@app.name}")
  end

  private

  def host
    ENV.fetch("APP_URL", "https://wokku.cloud").sub(%r{\Ahttps?://}, "")
  end
end
