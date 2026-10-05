# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "wokku:shared:ensure_parents" do
  before(:all) do
    Rake::Task.define_task(:environment)
    load Wokku::Engine.root.join("lib/tasks/wokku_shared.rake").to_s unless Rake::Task.task_defined?("wokku:shared:ensure_parents")
  end

  let(:task) { Rake::Task["wokku:shared:ensure_parents"] }
  let!(:server) { create(:server, wokkud_services_enabled: true) }
  let(:ensured) { [] }

  before do
    task.reenable
    allow(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, **|
      ensured << [ service.name, kind ]
      build_stubbed(:service_op, status: :succeeded)
    end
  end

  it "births (row) and ensures the mariadb parent on each wokkud server by default" do
    expect { task.invoke }.to output(/dokku-shared-mariadb ensured/).to_stdout

    parent = DatabaseService.find_by!(server: server, name: "dokku-shared-mariadb")
    expect(parent).to have_attributes(tier_name: "shared_host", wokkud_managed: true)
    expect(ensured).to include([ "dokku-shared-mariadb", "service.ensure" ])
  end

  it "never creates a postgres parent from nothing (adopted only) — skips servers without one" do
    expect { task.invoke("postgres") }.to output(/skipped/).to_stdout
    expect(DatabaseService.where(server: server, name: "dokku-shared-postgres")).to be_empty
    expect(ensured).to be_empty
  end

  it "keeps going when one server's ensure fails" do
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "slow pull")
    expect { task.invoke }.to output(/FAILED Services::Ops::Timeout/).to_stdout
  end
end
