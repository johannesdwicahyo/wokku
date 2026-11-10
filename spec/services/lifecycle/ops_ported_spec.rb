require "rails_helper"

RSpec.describe Lifecycle::Ops do
  let(:server) { create(:server) }
  let(:app) { create(:app_record, server: server) }
  let(:tier) { create(:dyno_tier, memory_mb: 512, cpu_shares: 0.5) }

  before do
    create(:dyno_allocation, app_record: app, dyno_tier: tier, process_type: "web")
    # The live-spec fallback SSHes to the host; default it to "no service"
    # so the no-image paths keep their meaning. Exercised in its own describe.
    allow(described_class).to receive(:live_web_spec).and_return([ nil, nil ])
    # cp env truth (B6 W3): converge assembles env from EnvVar rows.
    app.env_vars.create!(key: "FOO", value: "bar")
  end

  describe ".converge!" do
    let!(:deploy) do
      create(:deploy, :succeeded, :wokkud, app_record: app, formation_json: { "web" => "bundle exec puma" })
    end

    it "assembles desired-state params from records" do
      app.process_scales.create!(process_type: "web", count: 2)
      app.process_scales.create!(process_type: "worker", count: 1)

      op = described_class.converge!(app, wait: false)

      expect(op).to be_a(LifecycleOp)
      expect(op.kind).to eq("stack.converge")
      expect(op).to be_pending
      expect(op.app_record).to eq(app)
      expect(op.server).to eq(server)
      params = op.params
      expect(params["deploy_id"]).to eq(deploy.id)
      expect(params["image_ref"]).to eq(deploy.wokkud_image_ref)
      expect(params["formation"]).to eq("web" => 2, "worker" => 1)
      expect(params["formation_commands"]).to eq("web" => "/bin/bash -l -c 'exec bundle exec puma'")
      expect(params["env"]).to eq("FOO" => "bar", "PORT" => app.container_port.to_s)
      expect(params["resources"]).to eq(
        "web" => { "memory_mb" => 512, "cpu" => 0.5 },
        "worker" => { "memory_mb" => 512, "cpu" => 0.5 }
      )
      expect(params["container_port"]).to eq(app.container_port)
      expect(params["published_port"]).to eq(app.reload.swarm_port)
      expect(params["published_port"]).to be_between(20_000, 29_999)
      expect(params["networks"]).to eq([ DatabaseProvisioner::DEDICATED_NETWORK ])
      expect(params["restart"]).to eq(false)
      expect(params["tag_from_local"]).to eq(false)
    end

    it "honors an explicit formation_commands override (adopt's dokku-argv snapshot)" do
      op = described_class.converge!(app, wait: false,
                                     formation_commands: { "web" => "uvicorn app.main:app --port 5000" })

      expect(op.params["formation_commands"]).to eq("web" => "uvicorn app.main:app --port 5000")
    end

    it "expands $VAR / ${VAR} in formation commands from the assembled env" do
      # Swarm ContainerSpec commands exec directly — no shell, no expansion.
      # wicara-rails' Procfile `bin/rails server -p $PORT` crash-looped with
      # Thor's `Expected numeric value for '--port'; got \"$PORT\"`. The env
      # is fully assembled right here, so bake the values in. Unknown vars
      # stay untouched (visible in logs beats silently vanishing).
      wokkud_deploy = create(:deploy, :succeeded, :wokkud, app_record: app,
        formation_json: { "web" => "bin/rails server -p $PORT -b 0.0.0.0",
                          "worker" => "run --level ${LOG_LEVEL} --keep $UNSET_VAR" })
      app.env_vars.create!(key: "LOG_LEVEL", value: "warn")

      op = described_class.converge!(app, wait: false, deploy: wokkud_deploy)

      expect(op.params["formation_commands"]).to eq(
        "web" => "/bin/bash -l -c 'exec bin/rails server -p #{app.container_port} -b 0.0.0.0'",
        "worker" => "/bin/bash -l -c 'exec run --level warn --keep $UNSET_VAR'"
      )
    end

    it "falls back to the previous converge op's formation_commands when the deploy is dokku-built" do
      # Post-adopt restarts/scales/sleeps rebuild params from the deploy —
      # a dokku-built deploy has no formation_json, so without this fallback
      # the first restart after a tag_from_local adopt silently reverts the
      # task to the image's default CMD (voucher-bot: uvicorn back on 8000).
      dokku_deploy = create(:deploy, :succeeded, app_record: app) # builder nil
      app.lifecycle_ops.create!(server: server, kind: "stack.converge", status: :succeeded,
                                params: { "image_ref" => "127.0.0.1:5000/wokku/#{app.name}:adopt-1",
                                          "formation_commands" => { "web" => "uvicorn app.main:app --port 5000" } })

      op = described_class.converge!(app, wait: false, deploy: dokku_deploy)

      expect(op.params["formation_commands"]).to eq("web" => "uvicorn app.main:app --port 5000")
    end

    it "prefers a wokkud-built deploy's formation_json over the previous op's commands, even when empty" do
      # After the app's first real wokkud build, the new image's own CMD is
      # the truth — a stale adopt snapshot must not override it.
      app.lifecycle_ops.create!(server: server, kind: "stack.converge", status: :succeeded,
                                params: { "image_ref" => "x", "formation_commands" => { "web" => "stale cmd" } })
      wokkud_deploy = create(:deploy, :succeeded, :wokkud, app_record: app, formation_json: {})

      op = described_class.converge!(app, wait: false, deploy: wokkud_deploy)

      expect(op.params["formation_commands"]).to eq({})
    end

    it "forces PORT to container_port even when user config sets a different PORT" do
      app.env_vars.create!(key: "PORT", value: "9999")

      op = described_class.converge!(app, wait: false)

      expect(op.params["env"]).to eq("FOO" => "bar", "PORT" => app.container_port.to_s)
    end

    it "defaults formation to web=>1 when there are no process_scales" do
      op = described_class.converge!(app, wait: false)
      expect(op.params["formation"]).to eq("web" => 1)
    end

    it "sets restart => true when restart: true is passed" do
      op = described_class.converge!(app, restart: true, wait: false)
      expect(op.params["restart"]).to eq(true)
    end

    it "allocates a swarm_port once and reuses it on a second converge" do
      op1 = described_class.converge!(app, wait: false)
      first_port = op1.params["published_port"]
      expect(app.reload.swarm_port).to eq(first_port)
      op1.update!(status: :succeeded) # only one live op per app — resolve before issuing another

      op2 = described_class.converge!(app, wait: false)
      expect(op2.params["published_port"]).to eq(first_port)
    end

    context "when the explicit formation omits web while the app currently runs web" do
      before { app.process_scales.create!(process_type: "web", count: 1) }

      it "raises EmptyFormation" do
        expect { described_class.converge!(app, formation: { "worker" => 1 }, wait: false) }
          .to raise_error(Lifecycle::Ops::EmptyFormation, /formation_would_empty/)
      end

      it "skips the guard when allow_empty: true" do
        op = described_class.converge!(app, formation: { "worker" => 1 }, allow_empty: true, wait: false)
        expect(op.params["formation"]).to eq("worker" => 1)
      end
    end

    context "when the explicit formation sets web => 0 while the app currently runs web" do
      before { app.process_scales.create!(process_type: "web", count: 1) }

      it "raises EmptyFormation" do
        expect { described_class.converge!(app, formation: { "web" => 0 }, wait: false) }
          .to raise_error(Lifecycle::Ops::EmptyFormation, /formation_would_empty/)
      end

      it "skips the guard when allow_empty: true" do
        op = described_class.converge!(app, formation: { "web" => 0 }, allow_empty: true, wait: false)
        expect(op.params["formation"]).to eq("web" => 0)
      end
    end

    # 2026-10-09 jev-trading-bot: a background bot could never become
    # worker-only — explicit web: 0 was refused even with a worker scaled up.
    context "when the formation explicitly sets web => 0 and scales another process up (worker-only app)" do
      before { app.process_scales.create!(process_type: "web", count: 1) }

      it "allows it" do
        op = described_class.converge!(app, formation: { "web" => 0, "worker" => 1 }, wait: false)
        expect(op.params["formation"]).to eq("web" => 0, "worker" => 1)
      end
    end

    it "raises ArgumentError when there is no succeeded deploy and no image_ref/tag_from_local" do
      deploy.update!(status: :pending)
      expect { described_class.converge!(app, wait: false) }.to raise_error(ArgumentError, /no image/)
    end

    context "when there is no wokkud-built deploy but a prior succeeded stack.converge op exists (post-adopt)" do
      let!(:deploy) { nil } # override outer let! — no succeeded Deploy row at all

      it "falls back to the last succeeded converge op's image_ref instead of raising" do
        create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge", status: :succeeded,
                               params: { "image_ref" => "127.0.0.1:5000/wokku/#{app.name}:adopt-111" },
                               created_at: 1.hour.ago)
        create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge", status: :succeeded,
                               params: { "image_ref" => "127.0.0.1:5000/wokku/#{app.name}:adopt-222" })

        op = described_class.converge!(app, wait: false)

        expect(op.params["image_ref"]).to eq("127.0.0.1:5000/wokku/#{app.name}:adopt-222")
      end

      it "recovers both image_ref and formation_commands from the same old-shape historical op (fallback wiring)" do
        # Pins converge! to actually ROUTE through image_ref_from/formation_commands_from
        # rather than duplicating a single-shape `params.dig("image_ref")` lookup inline.
        # Every op in production's lifecycle_ops table today is old-shape (pre-B5b), so a
        # revert to a plain dig would pass every other spec here yet silently revert a real
        # adopted app's next restart/scale to its image's default CMD — the B5a bug that
        # took voucher-bot down for ~2 minutes. Verified by temporarily making both readers
        # new-shape-only and watching this example fail before restoring them.
        create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge", status: :succeeded,
                               params: { "image_ref" => "127.0.0.1:5000/wokku/#{app.name}:adopt-333",
                                         "formation_commands" => { "web" => "uvicorn app.main:app --port 5000" } })

        op = described_class.converge!(app, wait: false)

        expect(op.params["image_ref"]).to eq("127.0.0.1:5000/wokku/#{app.name}:adopt-333")
        expect(op.params["formation_commands"]).to eq("web" => "uvicorn app.main:app --port 5000")
      end

      it "recovers both image_ref and formation_commands from a NEW-shape-only historical op " \
         "(services map, no legacy top-level keys at all)" do
        # A legacy-shaped fixture can't discriminate this: for legacy params,
        # image_ref_from(params) reduces to params["image_ref"].presence — behaviourally
        # identical to a bare params.dig("image_ref"), so no legacy fixture can ever tell
        # the reader-routed implementation apart from the reverted one. This fixture has
        # NO top-level image_ref/formation_commands keys, only a services map — the shape
        # every historical op will carry once the legacy trio is dropped from stack.converge
        # params (agent floor raised, see the "Legacy trio" comment in ops.rb). Under a
        # reverted call site (`prev_converge&.params&.dig("image_ref")`), image_ref stays
        # nil and this app has no wokkud deploy either, so converge! would raise
        # ArgumentError instead of recovering — a restarted adopted app would otherwise
        # silently fall back to its image's default CMD.
        create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge", status: :succeeded,
                               params: { "services" => { "web" => {
                                 "image" => "127.0.0.1:5000/wokku/#{app.name}:adopt-444",
                                 "command" => "uvicorn app.main:app --port 5000"
                               } } })

        op = described_class.converge!(app, wait: false)

        expect(op.params["image_ref"]).to eq("127.0.0.1:5000/wokku/#{app.name}:adopt-444")
        expect(op.params["formation_commands"]).to eq("web" => "uvicorn app.main:app --port 5000")
      end

      it "routes the fallback through image_ref_from/formation_commands_from (call-site wiring pin)" do
        # Complements the new-shape fixture above: this pins the CALL SITES directly via
        # message expectations, so it catches a revert to bare params.dig(...) regardless
        # of the historical op's param shape (even a legacy-shaped fixture, which the
        # shape-based spec above cannot use to discriminate).
        create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge", status: :succeeded,
                               params: { "image_ref" => "127.0.0.1:5000/wokku/#{app.name}:adopt-555",
                                         "formation_commands" => { "web" => "uvicorn app.main:app --port 6000" } })

        expect(described_class).to receive(:image_ref_from).and_call_original
        expect(described_class).to receive(:formation_commands_from).and_call_original

        op = described_class.converge!(app, wait: false)

        expect(op.params["image_ref"]).to eq("127.0.0.1:5000/wokku/#{app.name}:adopt-555")
        expect(op.params["formation_commands"]).to eq("web" => "uvicorn app.main:app --port 6000")
      end

      it "still raises ArgumentError when no converge op succeeded either" do
        create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge", status: :failed,
                               params: { "image_ref" => "127.0.0.1:5000/wokku/#{app.name}:adopt-111" })

        expect { described_class.converge!(app, wait: false) }.to raise_error(ArgumentError, /no image/)
      end
    end

    it "omits local_ref when tag_from_local is false" do
      op = described_class.converge!(app, wait: false)
      expect(op.params).not_to have_key("local_ref")
    end

    context "when tag_from_local: true (adopt on an app with no succeeded deploy)" do
      let!(:deploy) { nil } # override the outer let! — no succeeded deploy for this app

      it "sets local_ref to the conventional dokku-built local image name" do
        op = described_class.converge!(app, tag_from_local: true, wait: false)
        expect(op.params["local_ref"]).to eq("dokku/#{app.name}:latest")
        expect(op.params["tag_from_local"]).to eq(true)
      end

      it "mints a registry image_ref for the adopt push target (spec §3.6) when none is passed" do
        op = described_class.converge!(app, tag_from_local: true, wait: false)
        expect(op.params["image_ref"]).to match(%r{\A127\.0\.0\.1:5000/wokku/#{app.name}:adopt-\d+\z})
      end
    end

    it "accepts a symbol-keyed formation (I6)" do
      app.process_scales.create!(process_type: "web", count: 1)
      op = described_class.converge!(app, formation: { web: 2, worker: 1 }, wait: false)
      expect(op.params["formation"]).to eq("web" => 2, "worker" => 1)
    end

    context "when passed an explicit deploy: (C5 — mid-deploy converge)" do
      let!(:older) do
        create(:deploy, :succeeded, :wokkud, app_record: app,
                                    formation_json: { "web" => "old cmd" }, created_at: 1.day.ago)
      end
      let(:building) do
        create(:deploy, :wokkud, app_record: app, status: :building,
                                 formation_json: { "web" => "new cmd" })
      end

      it "uses the passed deploy's formation_json/image_ref even though an older succeeded deploy exists" do
        op = described_class.converge!(app, deploy: building, wait: false)
        expect(op.params["formation_commands"]).to eq("web" => "/bin/bash -l -c 'exec new cmd'")
        expect(op.params["image_ref"]).to eq(building.wokkud_image_ref)
        expect(op.params["deploy_id"]).to eq(building.id)
      end
    end

    context "when the latest succeeded deploy was dokku-built (I8)" do
      let!(:deploy) { create(:deploy, :succeeded, app_record: app) } # builder nil => not registry-backed

      it "does not default image_ref to the never-pushed registry tag" do
        expect { described_class.converge!(app, wait: false) }.to raise_error(ArgumentError, /no image/)
      end

      it "mints the adopt ref when tag_from_local: true" do
        op = described_class.converge!(app, tag_from_local: true, wait: false)
        expect(op.params["image_ref"]).to match(%r{/wokku/#{app.name}:adopt-\d+\z})
      end
    end

    it "stop_formation zeroes every process in the current formation (C3/I1)" do
      app.process_scales.create!(process_type: "web", count: 2)
      app.process_scales.create!(process_type: "worker", count: 3)
      expect(described_class.stop_formation(app)).to eq("web" => 0, "worker" => 0)
    end

    it "issue! returns the op once terminal (stubbed transition)" do
      allow(described_class).to receive(:sleep)
      op = build(:lifecycle_op, app_record: app, server: server, kind: "stack.converge")
      allow(LifecycleOp).to receive(:create!).and_return(op)
      allow(op).to receive(:reload) { op.status = :succeeded; op }
      expect(described_class.converge!(app)).to be_succeeded
    end

    it "raises Failed with the op's error on failure" do
      allow(described_class).to receive(:sleep)
      op = build(:lifecycle_op, app_record: app, server: server, kind: "stack.converge")
      allow(LifecycleOp).to receive(:create!).and_return(op)
      allow(op).to receive(:reload) { op.assign_attributes(status: :failed, error: "boom", error_code: "converge_failed"); op }
      expect { described_class.converge!(app) }.to raise_error(Lifecycle::Ops::Failed, /boom/)
    end

    it "raises Timeout when the deadline passes" do
      allow(described_class).to receive(:sleep)
      op = create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge") # stays pending
      allow(LifecycleOp).to receive(:create!).and_return(op)
      expect { described_class.converge!(app, timeout: 0) }.to raise_error(Lifecycle::Ops::Timeout)
    end
  end

  describe "B5b per-service params" do
    let(:app) { create(:app_record, server: server, container_port: 3000) }

    it "emits a services map alongside the legacy keys" do
      allow(described_class).to receive(:issue!) { |_a, _k, params, **| params }
      params = described_class.converge!(app, image_ref: "img:1", formation: { "web" => 1 }, wait: false)

      expect(params[:services]["web"]).to include(
        "image" => "img:1", "replicas" => 1, "public" => true, "target_port" => 3000
      )
      # Legacy keys stay until the agent floor is raised, so rolling the agent
      # back does not strand a Rails that only speaks the new shape.
      expect(params[:formation]).to eq("web" => 1)
      expect(params[:image_ref]).to eq("img:1")
    end

    it "keeps public => false on a non-web service instead of dropping it via .compact" do
      # The service hash is built with .compact, which drops nil values — but
      # `false` survives .compact. A worker entry missing the "public" key
      # entirely (vs. explicitly false) decodes differently on the Go agent
      # side (absent key = zero value), which can flip which service publishes
      # a port.
      allow(described_class).to receive(:issue!) { |_a, _k, params, **| params }
      params = described_class.converge!(app, image_ref: "img:1", formation: { "web" => 1, "worker" => 1 }, wait: false)

      expect(params[:services]["worker"]).to include("public" => false)
      expect(params[:services]["worker"]).not_to have_key("target_port")
    end

    it "includes mounts in the web service when the app declares storage_mounts" do
      app.update!(storage_mounts: [ "/data" ])
      allow(described_class).to receive(:issue!) { |_a, _k, params, **| params }
      params = described_class.converge!(app, image_ref: "img:1", formation: { "web" => 1 }, wait: false)

      expect(params[:services]["web"]["mounts"]).to eq(app.mounts_for_converge)
    end

    it "omits mounts from the web service when the app has no storage_mounts" do
      allow(described_class).to receive(:issue!) { |_a, _k, params, **| params }
      params = described_class.converge!(app, image_ref: "img:1", formation: { "web" => 1 }, wait: false)

      expect(params[:services]["web"]).not_to have_key("mounts")
    end

    it "carries app.healthcheck_json onto the web service spec verbatim" do
      hc = { "test" => [ "CMD-SHELL", "curl -f localhost:2368" ], "interval_sec" => 10,
             "timeout_sec" => 5, "retries" => 5, "start_period_sec" => 90 }
      app.update!(healthcheck_json: hc)
      allow(described_class).to receive(:issue!) { |_a, _k, params, **| params }
      params = described_class.converge!(app, image_ref: "img:1", formation: { "web" => 1, "worker" => 1 }, wait: false)

      expect(params[:services]["web"]["healthcheck"]).to eq(hc)
      expect(params[:services]["worker"]).not_to have_key("healthcheck")
    end

    it "omits the healthcheck key entirely when healthcheck_json is nil (spec-hash stability)" do
      # A nil-valued key would still be a key — changing every existing app's
      # converge spec hash and rotating the fleet on its next converge.
      allow(described_class).to receive(:issue!) { |_a, _k, params, **| params }
      params = described_class.converge!(app, image_ref: "img:1", formation: { "web" => 1 }, wait: false)

      expect(params[:services]["web"]).not_to have_key("healthcheck")
    end

    it "reads image_ref from an old-shape historical op" do
      old = { "image_ref" => "old:1", "formation_commands" => { "web" => "rails s" } }
      expect(described_class.image_ref_from(old)).to eq("old:1")
      expect(described_class.formation_commands_from(old)).to eq("web" => "rails s")
    end

    it "reads image_ref from a new-shape historical op" do
      new_shape = { "services" => { "web" => { "image" => "new:1", "command" => "rails s", "public" => true } } }
      expect(described_class.image_ref_from(new_shape)).to eq("new:1")
      expect(described_class.formation_commands_from(new_shape)).to eq("web" => "rails s")
    end
  end

  describe ".allocate_swarm_port!" do
    it "retries and succeeds when update! collides on a taken port" do
      call_count = 0
      allow_any_instance_of(AppRecord).to receive(:update!).and_wrap_original do |original, *args|
        call_count += 1
        raise ActiveRecord::RecordNotUnique, "duplicate key" if call_count == 1
        original.call(*args)
      end

      port = described_class.allocate_swarm_port!(app)

      expect(call_count).to eq(2)
      expect(port).to eq(app.reload.swarm_port)
      expect(port).to be_between(20_000, 29_999)
    end

    it "never hands a deleted app's port to the next app (its service may outlive the row)" do
      gone = create(:app_record, server: server)
      gone_port = described_class.allocate_swarm_port!(gone)
      gone.delete

      expect(described_class.allocate_swarm_port!(app)).to be > gone_port
    end

    it "re-raises after exhausting retry attempts" do
      allow_any_instance_of(AppRecord).to receive(:update!).and_raise(ActiveRecord::RecordNotUnique, "duplicate key")

      expect { described_class.allocate_swarm_port!(app) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".run!" do
    let!(:deploy) do
      create(:deploy, :succeeded, :wokkud, app_record: app, image_ref: "127.0.0.1:5000/wokku/#{app.name}:d1")
    end

    it "issues stack.run with the deploy's image, wrapped command, env and network" do
      op = described_class.run!(app, "bin/rails db:migrate", wait: false)
      expect(op.kind).to eq("stack.run")
      expect(op.params["image_ref"]).to eq(deploy.wokkud_image_ref)
      expect(op.params["command"]).to eq("/bin/bash -l -c 'exec bin/rails db:migrate'")
      expect(op.params["networks"]).to eq([ DatabaseProvisioner::DEDICATED_NETWORK ])
      expect(op.params["env"]).to include("PORT" => app.container_port.to_s)
    end

    it "does not bash-l-wrap when the command carries quotes or control operators" do
      op = described_class.run!(app, "sh -c 'a && b'", wait: false)
      expect(op.params["command"]).to eq("sh -c 'a && b'")
    end

    it "does not wrap for non-wokkud-built images" do
      deploy.update!(builder: nil)
      create(:lifecycle_op, app_record: app, server: app.server, kind: "stack.converge", status: :succeeded,
                            params: { "image_ref" => "chatwoot/chatwoot:v3" })
      op = described_class.run!(app, "bundle exec rails db:migrate", wait: false)
      expect(op.params["image_ref"]).to eq("chatwoot/chatwoot:v3")
      expect(op.params["command"]).to eq("bundle exec rails db:migrate")
    end

    it "bakes $VARs from the assembled env" do
      app.env_vars.create!(key: "DATABASE_URL", value: "postgres://x")
      op = described_class.run!(app, "echo $DATABASE_URL", wait: false)
      expect(op.params["command"]).to include("postgres://x")
    end

    it "raises on a blank command" do
      expect { described_class.run!(app, " ") }.to raise_error(ArgumentError, /command/)
    end

    it "raises when no image exists yet" do
      deploy.destroy!
      expect { described_class.run!(app, "x") }.to raise_error(ArgumentError, /no image/)
    end

    it "honors an explicitly passed in-flight deploy for image and wrap (first-deploy post_deploy)" do
      deploy.destroy!
      in_flight = create(:deploy, app_record: app, status: :building, builder: "wokkud")
      op = described_class.run!(app, "bin/rails db:migrate", wait: false, deploy: in_flight)
      expect(op.params["image_ref"]).to eq(in_flight.wokkud_image_ref)
      expect(op.params["command"]).to eq("/bin/bash -l -c 'exec bin/rails db:migrate'")
    end
  end

  describe ".remove!" do
    it "issues a stack.remove op with empty params" do
      op = described_class.remove!(app, wait: false)
      expect(op.kind).to eq("stack.remove")
      expect(op.params).to eq({})
      expect(op).to be_pending
    end
  end

  describe ".remove_if_flagged!" do
    before { app.update!(wokkud_lifecycle: true) }

    it "swallows the Busy collision (live op already exists) instead of raising (destroy-during-deploy)" do
      create(:lifecycle_op, app_record: app, server: server, kind: "stack.converge", status: :pending)

      expect(Rails.logger).to receive(:warn).with(/Lifecycle::Ops::Busy/)
      expect { described_class.remove_if_flagged!(app) }.not_to raise_error
    end
  end

  describe ".issue!" do
    it "converts a real live-op collision (partial unique index) into Busy" do
      create(:lifecycle_op, app_record: app, server: server, status: :pending)

      expect {
        described_class.issue!(app, "stack.converge", {}, wait: false, timeout: 10)
      }.to raise_error(Lifecycle::Ops::Busy, /#{Regexp.escape(app.name)}.*retry shortly/)
    end

    it "creates the op normally when there is no live op in flight" do
      op = described_class.issue!(app, "stack.converge", {}, wait: false, timeout: 10)
      expect(op).to be_persisted
      expect(op).to be_pending
    end
  end

  describe "live Swarm spec fallback (no deploy, no prior converge)" do
    before { allow(described_class).to receive(:issue!) { |_a, _k, params, **| params } }

    it "converges from the running service's image and argv, and records them for the next restore" do
      allow(described_class).to receive(:live_web_spec).and_return([ "127.0.0.1:5000/wokku/x:adopt-1", { "web" => "/start web" } ])
      params = described_class.converge!(app, formation: { "web" => 0 }, allow_empty: true, wait: false)
      expect(params[:image_ref]).to eq("127.0.0.1:5000/wokku/x:adopt-1")
      expect(params[:services]["web"]).to include("image" => "127.0.0.1:5000/wokku/x:adopt-1", "command" => "/start web")
    end

    it "still raises when the service can't be read either" do
      expect { described_class.converge!(app, wait: false) }.to raise_error(ArgumentError, /no image/)
    end

    describe ".live_web_spec" do
      before { allow(described_class).to receive(:live_web_spec).and_call_original }

      def stub_inspect(json) = allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_return(json)

      it "parses image (digest stripped) and joins command + args" do
        stub_inspect({ "Image" => "reg/x:adopt-1@sha256:abc123", "Command" => [ "docker-php-entrypoint" ], "Args" => [ "/start.sh" ] }.to_json)
        expect(described_class.live_web_spec(app)).to eq([ "reg/x:adopt-1", { "web" => "docker-php-entrypoint /start.sh" } ])
      end

      it "leaves commands to the image CMD when an arg holds whitespace" do
        stub_inspect({ "Image" => "reg/w:1", "Command" => [ "nginx", "-g", "daemon off;" ] }.to_json)
        expect(described_class.live_web_spec(app)).to eq([ "reg/w:1", nil ])
      end

      it "returns [nil, nil] when the service doesn't exist" do
        allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError.new("no such service"))
        expect(described_class.live_web_spec(app)).to eq([ nil, nil ])
      end
    end
  end
end
