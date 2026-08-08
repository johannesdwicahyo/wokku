# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::ScheduledTaskFormComponent, type: :component do
  let(:app) { create(:app_record) }
  let(:task) { app.scheduled_tasks.new }

  it "renders a form that posts to the app's scheduled_tasks create path" do
    render_inline(described_class.new(task: task, app: app))

    form = page.find("form")
    expect(form[:method]).to eq("post")
    expect(form[:action]).to eq(
      Rails.application.routes.url_helpers.dashboard_app_scheduled_tasks_path(app)
    )
  end

  it "scopes fields under scheduled_task[...] so the controller's strong params match" do
    render_inline(described_class.new(task: task, app: app))
    expect(page).to have_field("scheduled_task[command]")
    expect(page).to have_field("scheduled_task[schedule]")
  end
end
