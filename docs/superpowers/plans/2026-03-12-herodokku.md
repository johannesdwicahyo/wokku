# Herodokku Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full Heroku-like PaaS on top of Dokku with Rails 8 web dashboard, Ruby CLI gem, and MCP server.

**Architecture:** Rails 8 monolith communicates with Dokku servers via SSH. Three clients (browser, CLI, MCP) share a single REST API. Hotwire/Turbo for the dashboard, Action Cable for real-time features, Solid Queue for background jobs.

**Tech Stack:** Ruby 3.3+, Rails 8, PostgreSQL, Redis, Devise, Pundit, Thor, net-ssh, Hotwire/Turbo/Stimulus, Solid Queue, Action Cable, Chartkick

**Spec:** `docs/superpowers/specs/2026-03-12-herodokku-design.md`

---

## Chunk 1: Rails Foundation & Auth

### Task 1: Scaffold Rails 8 App

**Files:**
- Create: entire Rails app scaffold
- Modify: `Gemfile`

- [ ] **Step 1: Generate Rails app**

```bash
cd /Users/johannesdwicahyo/Projects/2026
rails new herodokku --database=postgresql --css=tailwind --skip-jbuilder --force
cd herodokku
```

Note: `--force` because the directory exists with docs already. Rails will not overwrite existing files in `docs/`.

- [ ] **Step 2: Add required gems to Gemfile**

Append to `Gemfile`:

```ruby
# Auth & Authorization
gem "devise"
gem "pundit"

# SSH
gem "net-ssh"
gem "sshkit"

# Background Jobs (Rails 8 default, verify present)
gem "solid_queue"
gem "mission_control-jobs"

# Real-time
gem "redis"

# Encryption
gem "lockbox"
gem "blind_index"

# Charts
gem "chartkick"
gem "groupdate"

# API
gem "rack-cors"
```

- [ ] **Step 3: Bundle install**

Run: `bundle install`
Expected: Success, all gems resolved.

- [ ] **Step 4: Create database**

Run: `bin/rails db:create`
Expected: `Created database 'herodokku_development'` and `'herodokku_test'`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: scaffold Rails 8 app with dependencies"
```

---

### Task 2: Setup Devise Authentication

**Files:**
- Create: `app/models/user.rb`, `config/initializers/devise.rb`, devise migrations
- Modify: `config/routes.rb`

- [ ] **Step 1: Install Devise**

```bash
bin/rails generate devise:install
bin/rails generate devise User
```

- [ ] **Step 2: Add role to User migration**

Edit the generated migration to add:

```ruby
t.integer :role, default: 0, null: false
```

- [ ] **Step 3: Add role enum to User model**

In `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { member: 0, admin: 1 }

  has_many :api_tokens, dependent: :destroy
  has_many :ssh_public_keys, dependent: :destroy
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
end
```

- [ ] **Step 4: Run migration**

Run: `bin/rails db:migrate`
Expected: Success

- [ ] **Step 5: Write model test**

Create `test/models/user_test.rb`:

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "default role is member" do
    user = User.new(email: "test@example.com", password: "password123456")
    assert_equal "member", user.role
  end

  test "valid user with email and password" do
    user = User.new(email: "test@example.com", password: "password123456")
    assert user.valid?
  end
end
```

- [ ] **Step 6: Run test**

Run: `bin/rails test test/models/user_test.rb`
Expected: 2 tests, 0 failures

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: setup Devise auth with User model and roles"
```

---

### Task 3: ApiToken Model

**Files:**
- Create: `app/models/api_token.rb`, migration, `test/models/api_token_test.rb`

- [ ] **Step 1: Generate model**

```bash
bin/rails generate model ApiToken \
  user:references \
  token_digest:string:index \
  name:string \
  last_used_at:datetime \
  expires_at:datetime \
  revoked_at:datetime
```

- [ ] **Step 2: Add unique index and null constraints to migration**

Edit migration — ensure `token_digest` has `null: false` and a unique index.

- [ ] **Step 3: Implement ApiToken model**

```ruby
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.generate_token
    SecureRandom.hex(32)
  end

  def self.find_by_token(plain_token)
    return nil if plain_token.blank?
    find_by(token_digest: Digest::SHA256.hexdigest(plain_token))
  end

  def self.create_with_token!(attributes = {})
    plain_token = generate_token
    token = create!(attributes.merge(token_digest: Digest::SHA256.hexdigest(plain_token)))
    [token, plain_token]
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def active?
    !revoked? && !expired?
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end
end
```

- [ ] **Step 4: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 5: Write tests**

Create `test/models/api_token_test.rb`:

```ruby
require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
  end

  test "create_with_token! returns token and plain text" do
    token, plain = ApiToken.create_with_token!(user: @user, name: "test")
    assert token.persisted?
    assert_equal 64, plain.length
  end

  test "find_by_token finds active token" do
    token, plain = ApiToken.create_with_token!(user: @user, name: "test")
    found = ApiToken.find_by_token(plain)
    assert_equal token.id, found.id
  end

  test "revoked token is not active" do
    token, _ = ApiToken.create_with_token!(user: @user, name: "test")
    token.revoke!
    assert_not token.active?
  end

  test "expired token is not active" do
    token, _ = ApiToken.create_with_token!(user: @user, name: "test", expires_at: 1.hour.ago)
    assert_not token.active?
  end
end
```

- [ ] **Step 6: Run tests**

Run: `bin/rails test test/models/api_token_test.rb`
Expected: 4 tests, 0 failures

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add ApiToken model with SHA256 hashing"
```

---

### Task 4: API Token Authentication Concern

**Files:**
- Create: `app/controllers/concerns/api_authenticatable.rb`
- Create: `app/controllers/api/v1/base_controller.rb`
- Create: `test/controllers/api/v1/base_controller_test.rb`

- [ ] **Step 1: Create API auth concern**

```ruby
# app/controllers/concerns/api_authenticatable.rb
module ApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_token!
    attr_reader :current_api_token
  end

  private

  def authenticate_api_token!
    token_string = extract_token_from_header
    if token_string.blank?
      render json: { error: "Missing authorization token" }, status: :unauthorized
      return
    end

    @current_api_token = ApiToken.find_by_token(token_string)
    if @current_api_token.nil? || !@current_api_token.active?
      render json: { error: "Invalid or expired token" }, status: :unauthorized
      return
    end

    @current_api_token.touch_last_used!
    sign_in(@current_api_token.user, store: false) if respond_to?(:sign_in)
  end

  def extract_token_from_header
    header = request.headers["Authorization"]
    header&.match(/^Bearer\s+(.+)$/)&.captures&.first
  end

  def current_user
    @current_api_token&.user || super
  end
end
```

- [ ] **Step 2: Create API base controller**

```ruby
# app/controllers/api/v1/base_controller.rb
module Api
  module V1
    class BaseController < ActionController::API
      include ApiAuthenticatable
    end
  end
end
```

- [ ] **Step 3: Write integration test**

Create `test/controllers/api/v1/base_controller_test.rb`:

```ruby
require "test_helper"

class Api::V1::BaseControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @token, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "returns 401 without token" do
    get api_v1_auth_whoami_path
    assert_response :unauthorized
  end

  test "returns 401 with invalid token" do
    get api_v1_auth_whoami_path, headers: { "Authorization" => "Bearer invalid" }
    assert_response :unauthorized
  end

  test "returns 401 with revoked token" do
    @token.revoke!
    get api_v1_auth_whoami_path, headers: { "Authorization" => "Bearer #{@plain_token}" }
    assert_response :unauthorized
  end
end
```

Note: This test will pass after Task 5 (Auth controller) creates the route.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add API token authentication concern"
```

---

### Task 5: Auth API Controller

**Files:**
- Create: `app/controllers/api/v1/auth_controller.rb`
- Create: `test/controllers/api/v1/auth_controller_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Add API routes**

In `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  devise_for :users

  namespace :api do
    namespace :v1 do
      namespace :auth do
        post :login
        delete :logout
        get :whoami
        resources :tokens, only: [:index, :create, :destroy]
      end
    end
  end

  root "dashboard/apps#index"
end
```

- [ ] **Step 2: Create Auth controller**

```ruby
# app/controllers/api/v1/auth_controller.rb
module Api
  module V1
    class AuthController < ActionController::API
      include ApiAuthenticatable

      skip_before_action :authenticate_api_token!, only: [:login]

      def login
        user = User.find_by(email: params[:email])
        if user&.valid_password?(params[:password])
          token, plain_token = ApiToken.create_with_token!(
            user: user,
            name: params[:name] || "cli-#{Time.current.to_i}"
          )
          render json: {
            token: plain_token,
            user: { id: user.id, email: user.email, role: user.role }
          }, status: :created
        else
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

      def logout
        current_api_token.revoke!
        render json: { message: "Logged out" }
      end

      def whoami
        render json: {
          id: current_user.id,
          email: current_user.email,
          role: current_user.role
        }
      end
    end
  end
end
```

- [ ] **Step 3: Create Tokens controller**

```ruby
# app/controllers/api/v1/auth/tokens_controller.rb
module Api
  module V1
    module Auth
      class TokensController < Api::V1::BaseController
        def index
          tokens = current_user.api_tokens.active.select(:id, :name, :last_used_at, :expires_at, :created_at)
          render json: tokens
        end

        def create
          token, plain_token = ApiToken.create_with_token!(
            user: current_user,
            name: params[:name] || "token-#{Time.current.to_i}",
            expires_at: params[:expires_at]
          )
          render json: { id: token.id, token: plain_token, name: token.name }, status: :created
        end

        def destroy
          token = current_user.api_tokens.find(params[:id])
          token.revoke!
          render json: { message: "Token revoked" }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write tests**

Create `test/controllers/api/v1/auth_controller_test.rb`:

```ruby
require "test_helper"

class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @token, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "login returns token" do
    post api_v1_auth_login_path, params: { email: @user.email, password: "password123456" }
    assert_response :created
    assert_not_nil JSON.parse(response.body)["token"]
  end

  test "login rejects bad password" do
    post api_v1_auth_login_path, params: { email: @user.email, password: "wrong" }
    assert_response :unauthorized
  end

  test "whoami returns current user" do
    get api_v1_auth_whoami_path, headers: auth_headers
    assert_response :success
    assert_equal @user.email, JSON.parse(response.body)["email"]
  end

  test "logout revokes token" do
    delete api_v1_auth_logout_path, headers: auth_headers
    assert_response :success
    assert @token.reload.revoked?
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
```

- [ ] **Step 5: Run all tests**

Run: `bin/rails test`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add auth API (login, logout, whoami, token management)"
```

---

### Task 6: SshPublicKey Model

**Files:**
- Create: `app/models/ssh_public_key.rb`, migration, test

- [ ] **Step 1: Generate model**

```bash
bin/rails generate model SshPublicKey \
  user:references \
  name:string \
  public_key:text \
  fingerprint:string:index
```

- [ ] **Step 2: Add validations and null constraints**

Edit migration: `null: false` on `name`, `public_key`, `fingerprint`. Unique index on `fingerprint`.

Model:

```ruby
class SshPublicKey < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :public_key, presence: true, uniqueness: true
  validates :fingerprint, presence: true, uniqueness: true

  before_validation :compute_fingerprint, if: -> { public_key.present? && fingerprint.blank? }

  private

  def compute_fingerprint
    key = Net::SSH::KeyFactory.load_data_public_key(public_key)
    self.fingerprint = OpenSSL::Digest::SHA256.hexdigest(key.to_blob)
  rescue StandardError
    errors.add(:public_key, "is not a valid SSH public key")
  end
end
```

- [ ] **Step 3: Write test**

```ruby
require "test_helper"

class SshPublicKeyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
  end

  test "validates presence of name and public_key" do
    key = SshPublicKey.new(user: @user)
    assert_not key.valid?
    assert_includes key.errors[:name], "can't be blank"
    assert_includes key.errors[:public_key], "can't be blank"
  end
end
```

- [ ] **Step 4: Run migration and tests**

```bash
bin/rails db:migrate
bin/rails test test/models/ssh_public_key_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SshPublicKey model with fingerprint computation"
```

---

### Task 7: Install Pundit

**Files:**
- Create: `app/policies/application_policy.rb`

- [ ] **Step 1: Generate Pundit install**

```bash
bin/rails generate pundit:install
```

- [ ] **Step 2: Add Pundit to ApplicationController**

In `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: install Pundit authorization"
```

---

## Chunk 2: Core Models & Dokku SSH Client

### Task 8: Team & TeamMembership Models

**Files:**
- Create: `app/models/team.rb`, `app/models/team_membership.rb`, migrations, tests

- [ ] **Step 1: Generate models**

```bash
bin/rails generate model Team name:string owner:references
bin/rails generate model TeamMembership user:references team:references role:integer
```

- [ ] **Step 2: Edit migrations**

Team: `null: false` on `name`, unique index on `name`.
TeamMembership: `null: false` on `role`, default `role: 0`, unique index on `[:user_id, :team_id]`.

- [ ] **Step 3: Implement models**

```ruby
# app/models/team.rb
class Team < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :servers, dependent: :destroy
  has_many :app_records, dependent: :destroy
  has_many :notifications, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
```

```ruby
# app/models/team_membership.rb
class TeamMembership < ApplicationRecord
  belongs_to :user
  belongs_to :team

  enum :role, { viewer: 0, member: 1, admin: 2 }

  validates :user_id, uniqueness: { scope: :team_id }
  validates :role, presence: true
end
```

- [ ] **Step 4: Run migrations and write tests**

```ruby
# test/models/team_test.rb
require "test_helper"

class TeamTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "owner@example.com", password: "password123456")
  end

  test "creates team with owner" do
    team = Team.create!(name: "My Team", owner: @user)
    assert team.persisted?
  end

  test "name must be unique" do
    Team.create!(name: "My Team", owner: @user)
    duplicate = Team.new(name: "My Team", owner: @user)
    assert_not duplicate.valid?
  end
end
```

- [ ] **Step 5: Run tests**

Run: `bin/rails test test/models/team_test.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Team and TeamMembership models"
```

---

### Task 9: Server Model

**Files:**
- Create: `app/models/server.rb`, migration, test

- [ ] **Step 1: Generate model**

```bash
bin/rails generate model Server \
  name:string \
  host:string \
  port:integer \
  ssh_user:string \
  ssh_private_key:text \
  team:references \
  status:integer
```

- [ ] **Step 2: Edit migration**

`null: false` on `name`, `host`. Default `port: 22`, `ssh_user: "dokku"`, `status: 0`. Unique index on `[:name, :team_id]`.

- [ ] **Step 3: Implement model**

```ruby
class Server < ApplicationRecord
  belongs_to :team

  encrypts :ssh_private_key

  enum :status, { connected: 0, unreachable: 1, auth_failed: 2, syncing: 3 }

  has_many :app_records, dependent: :destroy
  has_many :database_services, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :team_id }
  validates :host, presence: true
  validates :port, numericality: { only_integer: true, greater_than: 0 }
end
```

- [ ] **Step 4: Write test**

```ruby
require "test_helper"

class ServerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
  end

  test "creates server with required fields" do
    server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    assert server.persisted?
    assert_equal "connected", server.status
    assert_equal 22, server.port
  end

  test "encrypts ssh_private_key" do
    server = Server.create!(name: "prod", host: "1.2.3.4", team: @team, ssh_private_key: "secret-key")
    assert_equal "secret-key", server.ssh_private_key
    raw = Server.find(server.id).ciphertext_for(:ssh_private_key)
    assert_not_equal "secret-key", raw
  end
end
```

- [ ] **Step 5: Run migration and tests**

```bash
bin/rails db:migrate
bin/rails test test/models/server_test.rb
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Server model with encrypted SSH key"
```

---

### Task 10: AppRecord Model

**Files:**
- Create: `app/models/app_record.rb`, migration, test

- [ ] **Step 1: Generate model**

```bash
bin/rails generate model AppRecord \
  name:string \
  server:references \
  team:references \
  status:integer \
  created_by:references \
  deploy_branch:string \
  synced_at:datetime
```

Foreign key for `created_by` points to `users`. Default `status: 0`, `deploy_branch: "main"`.

- [ ] **Step 2: Implement model**

```ruby
class AppRecord < ApplicationRecord
  belongs_to :server
  belongs_to :team
  belongs_to :creator, class_name: "User", foreign_key: :created_by_id

  has_many :releases, dependent: :destroy
  has_many :deploys, dependent: :destroy
  has_many :domains, dependent: :destroy
  has_many :env_vars, dependent: :destroy
  has_many :process_scales, dependent: :destroy
  has_many :app_databases, dependent: :destroy
  has_many :database_services, through: :app_databases
  has_many :notifications, dependent: :destroy

  enum :status, { running: 0, stopped: 1, crashed: 2, deploying: 3 }

  validates :name, presence: true,
    uniqueness: { scope: :server_id },
    format: { with: /\A[a-z][a-z0-9-]*\z/, message: "must be lowercase alphanumeric with hyphens" }

  scope :stale, -> { where("synced_at < ? OR synced_at IS NULL", 5.minutes.ago) }
end
```

- [ ] **Step 3: Write test**

```ruby
require "test_helper"

class AppRecordTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
  end

  test "validates name format" do
    app = AppRecord.new(name: "My App!", server: @server, team: @team, creator: @user)
    assert_not app.valid?
    assert_includes app.errors[:name], "must be lowercase alphanumeric with hyphens"
  end

  test "valid app name" do
    app = AppRecord.create!(name: "my-app", server: @server, team: @team, creator: @user)
    assert app.persisted?
  end
end
```

- [ ] **Step 4: Run migration and tests**

```bash
bin/rails db:migrate
bin/rails test test/models/app_record_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AppRecord model"
```

---

### Task 11: Remaining Core Models (Release, Deploy, Domain, EnvVar, ProcessScale, DatabaseService, AppDatabase, Certificate, Notification)

**Files:**
- Create: all model files, migrations, tests

- [ ] **Step 1: Generate all models**

```bash
bin/rails generate model Release app_record:references version:integer deploy:references description:string
bin/rails generate model Deploy app_record:references release:references status:integer commit_sha:string log:text started_at:datetime finished_at:datetime
bin/rails generate model Domain app_record:references hostname:string ssl_enabled:boolean
bin/rails generate model EnvVar app_record:references key:string encrypted_value:text
bin/rails generate model ProcessScale app_record:references process_type:string count:integer
bin/rails generate model DatabaseService server:references service_type:string name:string status:integer
bin/rails generate model AppDatabase app_record:references database_service:references alias_name:string
bin/rails generate model Certificate domain:references expires_at:datetime auto_renew:boolean
bin/rails generate model Notification app_record:references team:references channel:integer events:json config:json
```

- [ ] **Step 2: Edit migrations — add constraints, defaults, indexes**

Key constraints:
- Release: unique index on `[:app_record_id, :version]`, `deploy_id` nullable
- Deploy: `status` default 0 (pending), enum: `{ pending: 0, building: 1, succeeded: 2, failed: 3, timed_out: 4 }`
- Domain: unique index on `hostname`, `ssl_enabled` default false
- EnvVar: unique index on `[:app_record_id, :key]`
- ProcessScale: unique index on `[:app_record_id, :process_type]`, `count` default 1
- DatabaseService: `status` default 0, unique index on `[:server_id, :name]`
- AppDatabase: unique index on `[:app_record_id, :database_service_id]`
- Certificate: `auto_renew` default true
- Notification: `channel` enum, `app_record_id` nullable

- [ ] **Step 3: Implement all models**

```ruby
# app/models/release.rb
class Release < ApplicationRecord
  belongs_to :app_record
  belongs_to :deploy, optional: true

  validates :version, presence: true, uniqueness: { scope: :app_record_id }

  before_validation :set_version, on: :create

  private

  def set_version
    self.version ||= (app_record.releases.maximum(:version) || 0) + 1
  end
end

# app/models/deploy.rb
class Deploy < ApplicationRecord
  belongs_to :app_record
  belongs_to :release, optional: true

  enum :status, { pending: 0, building: 1, succeeded: 2, failed: 3, timed_out: 4 }

  validates :status, presence: true

  scope :recent, -> { order(created_at: :desc).limit(20) }

  def duration
    return nil unless started_at && finished_at
    finished_at - started_at
  end
end

# app/models/domain.rb
class Domain < ApplicationRecord
  belongs_to :app_record
  has_one :certificate, dependent: :destroy

  validates :hostname, presence: true, uniqueness: true
end

# app/models/env_var.rb
class EnvVar < ApplicationRecord
  belongs_to :app_record

  encrypts :encrypted_value

  validates :key, presence: true, uniqueness: { scope: :app_record_id },
    format: { with: /\A[A-Z_][A-Z0-9_]*\z/, message: "must be uppercase with underscores" }
end

# app/models/process_scale.rb
class ProcessScale < ApplicationRecord
  belongs_to :app_record

  validates :process_type, presence: true, uniqueness: { scope: :app_record_id }
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end

# app/models/database_service.rb
class DatabaseService < ApplicationRecord
  belongs_to :server

  has_many :app_databases, dependent: :destroy
  has_many :app_records, through: :app_databases

  enum :status, { running: 0, stopped: 1, creating: 2, error: 3 }

  validates :name, presence: true, uniqueness: { scope: :server_id }
  validates :service_type, presence: true, inclusion: {
    in: %w[postgres redis mysql mongodb memcached rabbitmq]
  }
end

# app/models/app_database.rb
class AppDatabase < ApplicationRecord
  belongs_to :app_record
  belongs_to :database_service

  validates :app_record_id, uniqueness: { scope: :database_service_id }
  validates :alias_name, presence: true
end

# app/models/certificate.rb
class Certificate < ApplicationRecord
  belongs_to :domain
end

# app/models/notification.rb
class Notification < ApplicationRecord
  belongs_to :team
  belongs_to :app_record, optional: true

  enum :channel, { email: 0, slack: 1, webhook: 2 }

  validates :channel, presence: true
  validates :events, presence: true
end
```

- [ ] **Step 4: Run all migrations**

```bash
bin/rails db:migrate
```

- [ ] **Step 5: Write basic model tests for each**

Create individual test files verifying validations and associations. One test per model covering the critical constraint (e.g., uniqueness, presence, enum).

- [ ] **Step 6: Run all tests**

Run: `bin/rails test`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add all core models (Release, Deploy, Domain, EnvVar, etc.)"
```

---

### Task 12: Dokku SSH Client Service

**Files:**
- Create: `app/services/dokku/client.rb`
- Create: `test/services/dokku/client_test.rb`

This is the core service that executes commands on Dokku servers via SSH.

- [ ] **Step 1: Create service**

```ruby
# app/services/dokku/client.rb
module Dokku
  class Client
    class CommandError < StandardError
      attr_reader :exit_code, :stderr

      def initialize(message, exit_code: nil, stderr: nil)
        @exit_code = exit_code
        @stderr = stderr
        super(message)
      end
    end

    class ConnectionError < StandardError; end

    def initialize(server)
      @server = server
    end

    def run(command, timeout: 30)
      output = ""
      error = ""
      exit_code = nil

      begin
        Net::SSH.start(@server.host, @server.ssh_user || "dokku", ssh_options) do |ssh|
          channel = ssh.open_channel do |ch|
            ch.exec("dokku #{command}") do |_ch, success|
              raise ConnectionError, "Failed to execute command" unless success

              ch.on_data { |_, data| output << data }
              ch.on_extended_data { |_, _, data| error << data }
              ch.on_request("exit-status") { |_, buf| exit_code = buf.read_long }
            end
          end
          channel.wait
        end
      rescue Net::SSH::AuthenticationFailed => e
        @server.update_column(:status, Server.statuses[:auth_failed])
        raise ConnectionError, "SSH authentication failed: #{e.message}"
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
        @server.update_column(:status, Server.statuses[:unreachable])
        raise ConnectionError, "Cannot connect to server: #{e.message}"
      end

      if exit_code && exit_code != 0
        raise CommandError.new(
          "Dokku command failed: #{command}\n#{error}",
          exit_code: exit_code,
          stderr: error
        )
      end

      output.strip
    end

    def run_streaming(command, &block)
      Net::SSH.start(@server.host, @server.ssh_user || "dokku", ssh_options) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec("dokku #{command}") do |_ch, success|
            raise ConnectionError, "Failed to execute command" unless success

            ch.on_data { |_, data| block.call(data) }
            ch.on_extended_data { |_, _, data| block.call(data) }
          end
        end
        channel.wait
      end
    end

    def connected?
      run("version")
      true
    rescue ConnectionError, CommandError
      false
    end

    private

    def ssh_options
      opts = {
        port: @server.port || 22,
        non_interactive: true,
        timeout: 10
      }

      if @server.ssh_private_key.present?
        key_file = Tempfile.new("dokku_key")
        key_file.write(@server.ssh_private_key)
        key_file.close
        File.chmod(0600, key_file.path)
        opts[:keys] = [key_file.path]
      end

      opts
    end
  end
end
```

- [ ] **Step 2: Write test with mock**

```ruby
# test/services/dokku/client_test.rb
require "test_helper"

class Dokku::ClientTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    @server = Server.create!(name: "prod", host: "dokku.example.com", team: @team)
    @client = Dokku::Client.new(@server)
  end

  test "initializes with server" do
    assert_equal @server, @client.instance_variable_get(:@server)
  end

  test "raises ConnectionError on auth failure" do
    Net::SSH.stub(:start, ->(*_args) { raise Net::SSH::AuthenticationFailed.new("test") }) do
      assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
      assert_equal "auth_failed", @server.reload.status
    end
  end

  test "raises ConnectionError on connection refused" do
    Net::SSH.stub(:start, ->(*_args) { raise Errno::ECONNREFUSED }) do
      assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
      assert_equal "unreachable", @server.reload.status
    end
  end
end
```

- [ ] **Step 3: Run tests**

Run: `bin/rails test test/services/dokku/client_test.rb`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Dokku SSH client service"
```

---

### Task 13: Dokku Service Modules (Apps, Config, Domains, etc.)

**Files:**
- Create: `app/services/dokku/apps.rb`, `config.rb`, `domains.rb`, `databases.rb`, `processes.rb`, `logs.rb`
- Create: tests for each

- [ ] **Step 1: Create Apps service**

```ruby
# app/services/dokku/apps.rb
module Dokku
  class Apps
    def initialize(client)
      @client = client
    end

    def list
      output = @client.run("apps:list")
      output.lines.map(&:strip).reject { |l| l.start_with?("=") || l.blank? }
    end

    def create(name)
      @client.run("apps:create #{name}")
    end

    def destroy(name)
      @client.run("-- --force apps:destroy #{name}")
    end

    def info(name)
      output = @client.run("apps:report #{name}")
      parse_report(output)
    end

    def rename(old_name, new_name)
      @client.run("apps:rename #{old_name} #{new_name}")
    end

    private

    def parse_report(output)
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        key, value = line.split(":", 2).map(&:strip)
        result[key.to_s.parameterize(separator: "_")] = value if key
      end
      result
    end
  end
end
```

- [ ] **Step 2: Create Config service**

```ruby
# app/services/dokku/config.rb
module Dokku
  class Config
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("config:show #{app_name}")
      parse_env(output)
    end

    def set(app_name, vars = {})
      pairs = vars.map { |k, v| "#{k}=#{Shellwords.escape(v)}" }.join(" ")
      @client.run("config:set --no-restart #{app_name} #{pairs}")
    end

    def unset(app_name, *keys)
      @client.run("config:unset --no-restart #{app_name} #{keys.join(' ')}")
    end

    def get(app_name, key)
      @client.run("config:get #{app_name} #{key}")
    end

    private

    def parse_env(output)
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        if (match = line.match(/\A(\w+):\s*(.*)\z/))
          result[match[1]] = match[2]
        end
      end
      result
    end
  end
end
```

- [ ] **Step 3: Create Domains service**

```ruby
# app/services/dokku/domains.rb
module Dokku
  class Domains
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("domains:report #{app_name}")
      vhosts = output.lines.find { |l| l.include?("Domains app vhosts:") }
      return [] unless vhosts
      vhosts.split(":").last.strip.split
    end

    def add(app_name, domain)
      @client.run("domains:add #{app_name} #{domain}")
    end

    def remove(app_name, domain)
      @client.run("domains:remove #{app_name} #{domain}")
    end

    def enable_ssl(app_name)
      @client.run("letsencrypt:enable #{app_name}")
    end
  end
end
```

- [ ] **Step 4: Create Databases service**

```ruby
# app/services/dokku/databases.rb
module Dokku
  class Databases
    SUPPORTED_TYPES = %w[postgres redis mysql mongodb memcached rabbitmq].freeze

    def initialize(client)
      @client = client
    end

    def list(service_type)
      validate_type!(service_type)
      output = @client.run("#{service_type}:list")
      output.lines.map(&:strip).reject { |l| l.start_with?("=") || l.blank? }
    end

    def create(service_type, name)
      validate_type!(service_type)
      @client.run("#{service_type}:create #{name}")
    end

    def destroy(service_type, name)
      validate_type!(service_type)
      @client.run("-- --force #{service_type}:destroy #{name}")
    end

    def info(service_type, name)
      validate_type!(service_type)
      output = @client.run("#{service_type}:info #{name}")
      parse_report(output)
    end

    def link(service_type, db_name, app_name)
      validate_type!(service_type)
      @client.run("#{service_type}:link #{db_name} #{app_name}")
    end

    def unlink(service_type, db_name, app_name)
      validate_type!(service_type)
      @client.run("#{service_type}:unlink #{db_name} #{app_name}")
    end

    private

    def validate_type!(type)
      raise ArgumentError, "Unsupported service type: #{type}" unless SUPPORTED_TYPES.include?(type)
    end

    def parse_report(output)
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        key, value = line.split(":", 2).map(&:strip)
        result[key.to_s.parameterize(separator: "_")] = value if key
      end
      result
    end
  end
end
```

- [ ] **Step 5: Create Processes service**

```ruby
# app/services/dokku/processes.rb
module Dokku
  class Processes
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("ps:report #{app_name}")
      parse_report(output)
    end

    def scale(app_name, scaling = {})
      pairs = scaling.map { |type, count| "#{type}=#{count}" }.join(" ")
      @client.run("ps:scale #{app_name} #{pairs}")
    end

    def restart(app_name)
      @client.run("ps:restart #{app_name}")
    end

    def stop(app_name)
      @client.run("ps:stop #{app_name}")
    end

    def start(app_name)
      @client.run("ps:start #{app_name}")
    end

    private

    def parse_report(output)
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        key, value = line.split(":", 2).map(&:strip)
        result[key.to_s.parameterize(separator: "_")] = value if key
      end
      result
    end
  end
end
```

- [ ] **Step 6: Create Logs service**

```ruby
# app/services/dokku/logs.rb
module Dokku
  class Logs
    def initialize(client)
      @client = client
    end

    def recent(app_name, lines: 100)
      @client.run("logs #{app_name} --num #{lines}")
    end

    def tail(app_name, &block)
      @client.run_streaming("logs #{app_name} --tail", &block)
    end
  end
end
```

- [ ] **Step 7: Write tests for Dokku::Apps (as representative)**

```ruby
# test/services/dokku/apps_test.rb
require "test_helper"

class Dokku::AppsTest < ActiveSupport::TestCase
  setup do
    @mock_client = Minitest::Mock.new
    @apps = Dokku::Apps.new(@mock_client)
  end

  test "list parses app names" do
    @mock_client.expect(:run, "=====> My Apps\napp-one\napp-two\n", ["apps:list"])
    result = @apps.list
    assert_equal ["app-one", "app-two"], result
    @mock_client.verify
  end

  test "create calls apps:create" do
    @mock_client.expect(:run, "Creating app-one...", ["apps:create app-one"])
    @apps.create("app-one")
    @mock_client.verify
  end
end
```

- [ ] **Step 8: Run all tests**

Run: `bin/rails test`

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add Dokku service modules (apps, config, domains, databases, processes, logs)"
```

---

## Chunk 3: Server & App API Controllers

### Task 14: Servers API Controller

**Files:**
- Create: `app/controllers/api/v1/servers_controller.rb`
- Create: `app/policies/server_policy.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/v1/servers_controller_test.rb`

- [ ] **Step 1: Add routes**

Add inside the `api > v1` namespace in `config/routes.rb`:

```ruby
resources :servers, only: [:index, :show, :create, :destroy] do
  member do
    get :status
  end
end
```

- [ ] **Step 2: Create policy**

```ruby
# app/policies/server_policy.rb
class ServerPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    user_in_team?
  end

  def create?
    true
  end

  def destroy?
    team_admin?
  end

  def status?
    user_in_team?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(team: :team_memberships).where(team_memberships: { user_id: user.id })
    end
  end

  private

  def user_in_team?
    record.team.team_memberships.exists?(user_id: user.id)
  end

  def team_admin?
    record.team.team_memberships.exists?(user_id: user.id, role: :admin)
  end
end
```

- [ ] **Step 3: Create controller**

```ruby
# app/controllers/api/v1/servers_controller.rb
module Api
  module V1
    class ServersController < BaseController
      def index
        servers = policy_scope(Server)
        render json: servers.select(:id, :name, :host, :port, :status, :created_at)
      end

      def show
        server = Server.find(params[:id])
        authorize server
        render json: server.as_json(except: [:ssh_private_key])
      end

      def create
        team = current_user.teams.find(params[:team_id])
        server = team.servers.build(server_params)
        authorize server

        if server.save
          render json: server.as_json(except: [:ssh_private_key]), status: :created
        else
          render json: { errors: server.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        server = Server.find(params[:id])
        authorize server
        server.destroy!
        render json: { message: "Server removed" }
      end

      def status
        server = Server.find(params[:id])
        authorize server
        client = Dokku::Client.new(server)
        connected = client.connected?
        server.update_column(:status, connected ? :connected : :unreachable)
        render json: { status: server.reload.status, connected: connected }
      end

      private

      def server_params
        params.permit(:name, :host, :port, :ssh_user, :ssh_private_key)
      end
    end
  end
end
```

- [ ] **Step 4: Write tests**

```ruby
# test/controllers/api/v1/servers_controller_test.rb
require "test_helper"

class Api::V1::ServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's servers" do
    get api_v1_servers_path, headers: auth_headers
    assert_response :success
    servers = JSON.parse(response.body)
    assert_equal 1, servers.length
    assert_equal "prod", servers.first["name"]
  end

  test "create adds server" do
    post api_v1_servers_path,
      params: { team_id: @team.id, name: "staging", host: "5.6.7.8" },
      headers: auth_headers
    assert_response :created
  end

  test "destroy removes server" do
    delete api_v1_server_path(@server), headers: auth_headers
    assert_response :success
    assert_not Server.exists?(@server.id)
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
```

- [ ] **Step 5: Run tests**

Run: `bin/rails test test/controllers/api/v1/servers_controller_test.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Servers API controller with Pundit authorization"
```

---

### Task 15: Apps API Controller

**Files:**
- Create: `app/controllers/api/v1/apps_controller.rb`
- Create: `app/policies/app_record_policy.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/v1/apps_controller_test.rb`

- [ ] **Step 1: Add routes**

```ruby
resources :apps, only: [:index, :show, :create, :update, :destroy] do
  member do
    post :restart
    post :stop
    post :start
  end
end
```

- [ ] **Step 2: Create policy**

```ruby
# app/policies/app_record_policy.rb
class AppRecordPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    user_in_team?
  end

  def create?
    team_member_or_above?
  end

  def update?
    team_member_or_above?
  end

  def destroy?
    team_admin?
  end

  def restart?
    team_member_or_above?
  end

  def stop?
    team_member_or_above?
  end

  def start?
    team_member_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(team: :team_memberships).where(team_memberships: { user_id: user.id })
    end
  end

  private

  def user_in_team?
    record.team.team_memberships.exists?(user_id: user.id)
  end

  def team_member_or_above?
    record.team.team_memberships.exists?(user_id: user.id, role: [:member, :admin])
  end

  def team_admin?
    record.team.team_memberships.exists?(user_id: user.id, role: :admin)
  end
end
```

- [ ] **Step 3: Create controller**

```ruby
# app/controllers/api/v1/apps_controller.rb
module Api
  module V1
    class AppsController < BaseController
      def index
        apps = policy_scope(AppRecord)
        apps = apps.where(server_id: params[:server_id]) if params[:server_id]
        render json: apps.select(:id, :name, :status, :server_id, :created_at)
      end

      def show
        app = AppRecord.find(params[:id])
        authorize app
        render json: app
      end

      def create
        server = Server.find(params[:server_id])
        team = server.team
        app = team.app_records.build(
          name: params[:name],
          server: server,
          creator: current_user
        )
        authorize app

        client = Dokku::Client.new(server)
        dokku_apps = Dokku::Apps.new(client)
        dokku_apps.create(params[:name])
        app.save!

        render json: app, status: :created
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def update
        app = AppRecord.find(params[:id])
        authorize app

        if params[:name].present?
          client = Dokku::Client.new(app.server)
          Dokku::Apps.new(client).rename(app.name, params[:name])
          app.update!(name: params[:name])
        end

        render json: app
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def destroy
        app = AppRecord.find(params[:id])
        authorize app

        client = Dokku::Client.new(app.server)
        Dokku::Apps.new(client).destroy(app.name)
        app.destroy!

        render json: { message: "App destroyed" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def restart
        app = AppRecord.find(params[:id])
        authorize app
        client = Dokku::Client.new(app.server)
        Dokku::Processes.new(client).restart(app.name)
        render json: { message: "App restarted" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def stop
        app = AppRecord.find(params[:id])
        authorize app
        client = Dokku::Client.new(app.server)
        Dokku::Processes.new(client).stop(app.name)
        app.update!(status: :stopped)
        render json: { message: "App stopped" }
      end

      def start
        app = AppRecord.find(params[:id])
        authorize app
        client = Dokku::Client.new(app.server)
        Dokku::Processes.new(client).start(app.name)
        app.update!(status: :running)
        render json: { message: "App started" }
      end
    end
  end
end
```

- [ ] **Step 4: Write tests**

```ruby
# test/controllers/api/v1/apps_controller_test.rb
require "test_helper"

class Api::V1::AppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app = AppRecord.create!(name: "my-app", server: @server, team: @team, creator: @user)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's apps" do
    get api_v1_apps_path, headers: auth_headers
    assert_response :success
    apps = JSON.parse(response.body)
    assert_equal 1, apps.length
  end

  test "show returns app details" do
    get api_v1_app_path(@app), headers: auth_headers
    assert_response :success
    assert_equal "my-app", JSON.parse(response.body)["name"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
```

- [ ] **Step 5: Run tests**

Run: `bin/rails test test/controllers/api/v1/apps_controller_test.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Apps API controller with Dokku integration"
```

---

### Task 16: Config (EnvVars) API Controller

**Files:**
- Create: `app/controllers/api/v1/config_controller.rb`
- Modify: `config/routes.rb`
- Create: test

- [ ] **Step 1: Add nested route**

```ruby
resources :apps, only: [:index, :show, :create, :update, :destroy] do
  # ... existing member routes
  resource :config, only: [:show, :update, :destroy], controller: "config"
end
```

- [ ] **Step 2: Create controller**

```ruby
# app/controllers/api/v1/config_controller.rb
module Api
  module V1
    class ConfigController < BaseController
      before_action :set_app

      def show
        authorize @app, :show?
        client = Dokku::Client.new(@app.server)
        vars = Dokku::Config.new(client).list(@app.name)
        render json: vars
      end

      def update
        authorize @app, :update?
        client = Dokku::Client.new(@app.server)
        Dokku::Config.new(client).set(@app.name, params[:vars].to_unsafe_h)

        # Sync to local DB
        params[:vars].each do |key, value|
          env_var = @app.env_vars.find_or_initialize_by(key: key)
          env_var.update!(encrypted_value: value)
        end

        render json: { message: "Config updated" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def destroy
        authorize @app, :update?
        keys = params[:keys] || []
        client = Dokku::Client.new(@app.server)
        Dokku::Config.new(client).unset(@app.name, *keys)
        @app.env_vars.where(key: keys).destroy_all
        render json: { message: "Config vars removed" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_app
        @app = AppRecord.find(params[:app_id])
      end
    end
  end
end
```

- [ ] **Step 3: Write test**

```ruby
require "test_helper"

class Api::V1::ConfigControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :member)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app = AppRecord.create!(name: "my-app", server: @server, team: @team, creator: @user)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "show returns config vars" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:run, "DATABASE_URL: postgres://...\nREDIS_URL: redis://...", ["config:show my-app"])

    Dokku::Client.stub(:new, mock_client) do
      get api_v1_app_config_path(@app), headers: auth_headers
      assert_response :success
    end
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
```

- [ ] **Step 4: Run tests and commit**

```bash
bin/rails test test/controllers/api/v1/config_controller_test.rb
git add -A
git commit -m "feat: add Config API controller for env var management"
```

---

### Task 17: Domains, Databases, Releases, PS, Logs, SSH Keys API Controllers

**Files:**
- Create: `app/controllers/api/v1/domains_controller.rb`
- Create: `app/controllers/api/v1/databases_controller.rb`
- Create: `app/controllers/api/v1/releases_controller.rb`
- Create: `app/controllers/api/v1/ps_controller.rb`
- Create: `app/controllers/api/v1/logs_controller.rb`
- Create: `app/controllers/api/v1/ssh_keys_controller.rb`
- Create: `app/controllers/api/v1/teams_controller.rb`
- Create: `app/controllers/api/v1/notifications_controller.rb`
- Modify: `config/routes.rb`
- Create: tests for each

These controllers all follow the same pattern established in Tasks 14-16:
1. Find resource, authorize via Pundit
2. Execute Dokku command via SSH if needed
3. Update local DB
4. Return JSON

- [ ] **Step 1: Add all remaining routes**

```ruby
# Inside api > v1 namespace
resources :apps do
  # ... existing
  resources :domains, only: [:index, :create, :destroy] do
    member { post :ssl }
  end
  resources :releases, only: [:index, :show], param: :version do
    member { post :rollback }
  end
  resource :ps, only: [:show, :update], controller: "ps"
  resources :logs, only: [:index] do
    collection { get :stream }
  end
end

resources :databases, only: [:index, :show, :create, :destroy] do
  member do
    post :link
    delete :link, action: :unlink
  end
end

resources :ssh_keys, only: [:index, :create, :destroy]

resources :teams, only: [:index, :create] do
  resources :members, only: [:index, :create, :destroy], controller: "team_members"
end

resources :notifications, only: [:index, :create, :destroy]
```

- [ ] **Step 2: Implement each controller**

Follow the exact same pattern as Apps and Config controllers. Each controller:
- Inherits from `Api::V1::BaseController`
- Uses Pundit `authorize` and `policy_scope`
- Calls the appropriate `Dokku::*` service for SSH commands
- Returns JSON

Key details per controller:

**DomainsController:** POST creates domain on Dokku then saves locally. DELETE removes from Dokku then destroys locally. POST ssl calls `letsencrypt:enable`.

**DatabasesController:** POST creates via `Dokku::Databases.new(client).create(type, name)`. POST link calls `.link()` and creates AppDatabase record. DELETE link calls `.unlink()`.

**ReleasesController:** Index returns `app.releases.order(version: :desc)`. Show returns release with associated deploy. POST rollback creates new Release pointing to old commit SHA and triggers a DeployJob.

**PsController:** Show returns `app.process_scales` merged with Dokku ps:report. Update calls `Dokku::Processes.new(client).scale()` and updates ProcessScale records.

**LogsController:** Index calls `Dokku::Logs.new(client).recent(app.name)` and returns text. Stream upgrades to Action Cable (handled in Task 20).

**SshKeysController:** Simple CRUD on current_user.ssh_public_keys. No Dokku interaction.

**TeamsController/TeamMembersController:** CRUD on teams and memberships. No Dokku interaction.

**NotificationsController:** CRUD on notifications scoped by team/app.

- [ ] **Step 3: Write tests for each controller**

One integration test per controller covering the happy path (index, create, destroy). Use mock Dokku client where SSH is needed.

- [ ] **Step 4: Run all tests**

Run: `bin/rails test`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add remaining API controllers (domains, databases, releases, ps, logs, ssh_keys, teams, notifications)"
```

---

## Chunk 4: Background Jobs & Real-time

### Task 18: Health Check Job

**Files:**
- Create: `app/jobs/health_check_job.rb`
- Create: `test/jobs/health_check_job_test.rb`

- [ ] **Step 1: Create job**

```ruby
# app/jobs/health_check_job.rb
class HealthCheckJob < ApplicationJob
  queue_as :default

  def perform(server_id)
    server = Server.find(server_id)
    client = Dokku::Client.new(server)

    if client.connected?
      server.update_column(:status, Server.statuses[:connected])
    else
      server.update_column(:status, Server.statuses[:unreachable])
    end
  rescue Dokku::Client::ConnectionError
    server.update_column(:status, Server.statuses[:unreachable])
  end
end
```

- [ ] **Step 2: Write test**

```ruby
require "test_helper"

class HealthCheckJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
  end

  test "marks server connected when SSH succeeds" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:connected?, true)

    Dokku::Client.stub(:new, mock_client) do
      HealthCheckJob.perform_now(@server.id)
    end

    assert_equal "connected", @server.reload.status
  end

  test "marks server unreachable when SSH fails" do
    Dokku::Client.stub(:new, ->(_) { raise Dokku::Client::ConnectionError, "fail" }) do
      HealthCheckJob.perform_now(@server.id)
    end

    assert_equal "unreachable", @server.reload.status
  end
end
```

- [ ] **Step 3: Run test and commit**

```bash
bin/rails test test/jobs/health_check_job_test.rb
git add -A
git commit -m "feat: add HealthCheckJob for server status monitoring"
```

---

### Task 19: Sync Server Job

**Files:**
- Create: `app/jobs/sync_server_job.rb`
- Create: `test/jobs/sync_server_job_test.rb`

- [ ] **Step 1: Create job**

```ruby
# app/jobs/sync_server_job.rb
class SyncServerJob < ApplicationJob
  queue_as :default

  def perform(server_id)
    server = Server.find(server_id)
    server.update_column(:status, Server.statuses[:syncing])

    client = Dokku::Client.new(server)
    dokku_apps = Dokku::Apps.new(client)

    # Sync apps list
    remote_app_names = dokku_apps.list
    local_app_names = server.app_records.pluck(:name)

    # Create locally missing apps (created directly on Dokku)
    (remote_app_names - local_app_names).each do |name|
      server.app_records.create!(
        name: name,
        team: server.team,
        creator: server.team.owner
      )
    end

    # Mark removed apps
    (local_app_names - remote_app_names).each do |name|
      server.app_records.find_by(name: name)&.destroy
    end

    # Update synced_at
    server.app_records.update_all(synced_at: Time.current)
    server.update_column(:status, Server.statuses[:connected])
  rescue Dokku::Client::ConnectionError
    server.update_column(:status, Server.statuses[:unreachable])
  end
end
```

- [ ] **Step 2: Write test, run, commit**

Similar to HealthCheckJob test pattern. Mock the client, verify sync behavior.

```bash
git add -A
git commit -m "feat: add SyncServerJob for Dokku data synchronization"
```

---

### Task 20: Deploy Job

**Files:**
- Create: `app/jobs/deploy_job.rb`
- Create: `app/channels/deploy_channel.rb`
- Create: `test/jobs/deploy_job_test.rb`

- [ ] **Step 1: Create Deploy channel**

```ruby
# app/channels/deploy_channel.rb
class DeployChannel < ApplicationCable::Channel
  def subscribed
    deploy = Deploy.find(params[:deploy_id])
    stream_for deploy
  end
end
```

- [ ] **Step 2: Create Deploy job**

```ruby
# app/jobs/deploy_job.rb
class DeployJob < ApplicationJob
  queue_as :deploys

  def perform(deploy_id)
    deploy = Deploy.find(deploy_id)
    app = deploy.app_record
    server = app.server

    deploy.update!(status: :building, started_at: Time.current)
    app.update!(status: :deploying)

    client = Dokku::Client.new(server)
    log = ""

    client.run_streaming("logs #{app.name} --tail") do |data|
      log << data
      DeployChannel.broadcast_to(deploy, { type: "log", data: data })
    end

    deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
    app.update!(status: :running)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })

    fire_notifications(deploy, :deploy_success)
  rescue Dokku::Client::CommandError => e
    deploy.update!(status: :failed, log: log.to_s + "\n#{e.message}", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    fire_notifications(deploy, :deploy_failure)
  end

  private

  def fire_notifications(deploy, event)
    notifications = Notification.where(team: deploy.app_record.team)
      .or(Notification.where(app_record: deploy.app_record))
    notifications.each do |notification|
      NotifyJob.perform_later(notification.id, event.to_s, deploy.id)
    end
  end
end
```

- [ ] **Step 3: Write test, run, commit**

```bash
git add -A
git commit -m "feat: add DeployJob with Action Cable broadcasting"
```

---

### Task 21: Log Streaming Channel

**Files:**
- Create: `app/channels/log_channel.rb`

- [ ] **Step 1: Create channel**

```ruby
# app/channels/log_channel.rb
class LogChannel < ApplicationCable::Channel
  def subscribed
    @app = AppRecord.find(params[:app_id])
    stream_for @app

    # Start streaming in background
    LogStreamJob.perform_later(@app.id, subscription_identifier)
  end

  def unsubscribed
    # Cleanup handled by job timeout
  end
end
```

- [ ] **Step 2: Create LogStreamJob**

```ruby
# app/jobs/log_stream_job.rb
class LogStreamJob < ApplicationJob
  queue_as :logs

  def perform(app_id, channel_id)
    app = AppRecord.find(app_id)
    client = Dokku::Client.new(app.server)

    client.run_streaming("logs #{app.name} --tail") do |data|
      LogChannel.broadcast_to(app, { type: "log", data: data })
    end
  rescue Dokku::Client::ConnectionError => e
    LogChannel.broadcast_to(app, { type: "error", data: e.message })
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add log streaming via Action Cable"
```

---

### Task 22: Metrics Poll Job

**Files:**
- Create: `app/jobs/metrics_poll_job.rb`
- Create: `app/models/metric.rb`, migration

- [ ] **Step 1: Generate Metric model**

```bash
bin/rails generate model Metric \
  app_record:references \
  cpu_percent:float \
  memory_usage:bigint \
  memory_limit:bigint \
  recorded_at:datetime
```

Add index on `[:app_record_id, :recorded_at]`.

- [ ] **Step 2: Create job**

```ruby
# app/jobs/metrics_poll_job.rb
class MetricsPollJob < ApplicationJob
  queue_as :metrics

  def perform(server_id)
    server = Server.find(server_id)
    client = Dokku::Client.new(server)

    output = client.run('-- docker stats --no-stream --format \'{{json .}}\'')
    output.each_line do |line|
      data = JSON.parse(line)
      container_name = data["Name"]

      # Dokku containers are named like: <app>.web.1
      app_name = container_name.split(".").first
      app = server.app_records.find_by(name: app_name)
      next unless app

      app.metrics.create!(
        cpu_percent: data["CPUPerc"].to_f,
        memory_usage: parse_bytes(data["MemUsage"].split("/").first.strip),
        memory_limit: parse_bytes(data["MemUsage"].split("/").last.strip),
        recorded_at: Time.current
      )
    end
  rescue Dokku::Client::ConnectionError, JSON::ParserError => e
    Rails.logger.warn("MetricsPollJob failed for server #{server_id}: #{e.message}")
  end

  private

  def parse_bytes(str)
    num = str.to_f
    case str
    when /GiB/i then (num * 1024 * 1024 * 1024).to_i
    when /MiB/i then (num * 1024 * 1024).to_i
    when /KiB/i then (num * 1024).to_i
    else num.to_i
    end
  end
end
```

- [ ] **Step 3: Add has_many to AppRecord**

In `app/models/app_record.rb` add: `has_many :metrics, dependent: :destroy`

- [ ] **Step 4: Run migration, write test, commit**

```bash
bin/rails db:migrate
git add -A
git commit -m "feat: add MetricsPollJob and Metric model for container stats"
```

---

### Task 23: Notification Job

**Files:**
- Create: `app/jobs/notify_job.rb`

- [ ] **Step 1: Create job**

```ruby
# app/jobs/notify_job.rb
class NotifyJob < ApplicationJob
  queue_as :notifications

  def perform(notification_id, event, deploy_id)
    notification = Notification.find(notification_id)
    deploy = Deploy.find(deploy_id)

    return unless notification.events.include?(event)

    case notification.channel
    when "email"
      NotificationMailer.deploy_notification(notification, deploy, event).deliver_later
    when "slack"
      send_slack(notification, deploy, event)
    when "webhook"
      send_webhook(notification, deploy, event)
    end
  end

  private

  def send_slack(notification, deploy, event)
    url = notification.config["url"]
    payload = {
      text: "[#{deploy.app_record.name}] Deploy #{event}: #{deploy.commit_sha&.first(7)} (v#{deploy.release&.version})"
    }
    Net::HTTP.post(URI(url), payload.to_json, "Content-Type" => "application/json")
  end

  def send_webhook(notification, deploy, event)
    url = notification.config["url"]
    payload = {
      event: event,
      app: deploy.app_record.name,
      deploy_id: deploy.id,
      status: deploy.status,
      commit_sha: deploy.commit_sha
    }
    Net::HTTP.post(URI(url), payload.to_json, "Content-Type" => "application/json")
  end
end
```

- [ ] **Step 2: Create mailer**

```bash
bin/rails generate mailer NotificationMailer deploy_notification
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add NotifyJob for email, Slack, and webhook notifications"
```

---

### Task 24: Recurring Job Schedule

**Files:**
- Create: `config/recurring.yml` (Solid Queue recurring tasks)

- [ ] **Step 1: Configure recurring jobs**

```yaml
# config/recurring.yml
health_checks:
  class: HealthCheckSchedulerJob
  schedule: every 5 minutes
  queue: default

sync_servers:
  class: SyncServerSchedulerJob
  schedule: every 10 minutes
  queue: default

metrics_poll:
  class: MetricsPollSchedulerJob
  schedule: every 1 minute
  queue: metrics
```

- [ ] **Step 2: Create scheduler jobs**

These fan out to per-server jobs:

```ruby
# app/jobs/health_check_scheduler_job.rb
class HealthCheckSchedulerJob < ApplicationJob
  def perform
    Server.find_each { |s| HealthCheckJob.perform_later(s.id) }
  end
end

# app/jobs/sync_server_scheduler_job.rb
class SyncServerSchedulerJob < ApplicationJob
  def perform
    Server.find_each { |s| SyncServerJob.perform_later(s.id) }
  end
end

# app/jobs/metrics_poll_scheduler_job.rb
class MetricsPollSchedulerJob < ApplicationJob
  def perform
    Server.find_each { |s| MetricsPollJob.perform_later(s.id) }
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add recurring job schedule for health checks, sync, and metrics"
```

---

## Chunk 5: Dashboard (Hotwire/Turbo)

### Task 25: Dashboard Layout & Navigation

**Files:**
- Create: `app/controllers/dashboard/base_controller.rb`
- Create: `app/views/layouts/dashboard.html.erb`
- Create: `app/views/dashboard/shared/_navbar.html.erb`
- Create: `app/views/dashboard/shared/_sidebar.html.erb`

- [ ] **Step 1: Create dashboard base controller**

```ruby
# app/controllers/dashboard/base_controller.rb
module Dashboard
  class BaseController < ApplicationController
    before_action :authenticate_user!
    layout "dashboard"
  end
end
```

- [ ] **Step 2: Create dashboard layout**

Build a Heroku-inspired layout with:
- Top navbar (logo, user menu, team selector)
- Left sidebar (Apps, Databases, Servers, Settings)
- Main content area with Turbo Frame

Use Tailwind CSS classes. Dark sidebar, light content area.

- [ ] **Step 3: Add dashboard routes**

```ruby
# config/routes.rb
namespace :dashboard do
  resources :apps do
    resources :config, only: [:index]
    resources :domains, only: [:index]
    resources :releases, only: [:index]
    resource :logs, only: [:show]
    resource :metrics, only: [:show]
    resource :settings, only: [:show]
  end
  resources :servers
  resources :databases
  resource :profile, only: [:show, :edit, :update]
  resources :teams
end
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add dashboard layout with Tailwind navigation"
```

---

### Task 26: Dashboard Apps Controller & Views

**Files:**
- Create: `app/controllers/dashboard/apps_controller.rb`
- Create: `app/views/dashboard/apps/index.html.erb`
- Create: `app/views/dashboard/apps/show.html.erb`
- Create: `app/views/dashboard/apps/new.html.erb`

- [ ] **Step 1: Create controller**

```ruby
module Dashboard
  class AppsController < Dashboard::BaseController
    def index
      @apps = policy_scope(AppRecord).includes(:server).order(created_at: :desc)
    end

    def show
      @app = AppRecord.find(params[:id])
      authorize @app
      @recent_deploys = @app.deploys.recent.limit(5)
      @process_scales = @app.process_scales
    end

    def new
      @servers = policy_scope(Server)
    end

    def create
      server = Server.find(params[:server_id])
      @app = server.team.app_records.build(
        name: params[:name], server: server, creator: current_user
      )
      authorize @app

      client = Dokku::Client.new(server)
      Dokku::Apps.new(client).create(params[:name])
      @app.save!

      redirect_to dashboard_app_path(@app), notice: "App created!"
    rescue Dokku::Client::CommandError => e
      flash.now[:alert] = e.message
      @servers = policy_scope(Server)
      render :new, status: :unprocessable_entity
    end

    def destroy
      @app = AppRecord.find(params[:id])
      authorize @app

      client = Dokku::Client.new(@app.server)
      Dokku::Apps.new(client).destroy(@app.name)
      @app.destroy!

      redirect_to dashboard_apps_path, notice: "App destroyed"
    end
  end
end
```

- [ ] **Step 2: Create views**

Index: Grid/list of apps with status badges, server name, last deploy time. Each app card links to show page. "New App" button.

Show: App overview with tabs (using Turbo Frames):
- Overview (status, git remote, last deploy)
- Resources (process scaling)
- Recent activity (last 5 deploys)

Use Turbo Frames for tab content to load lazily.

- [ ] **Step 3: Create remaining dashboard controllers**

Follow same pattern for:
- `Dashboard::ServersController`
- `Dashboard::DatabasesController`
- `Dashboard::ConfigController` (nested under apps)
- `Dashboard::DomainsController` (nested under apps)
- `Dashboard::ReleasesController` (nested under apps)
- `Dashboard::LogsController` (nested under apps — with Stimulus for Action Cable)
- `Dashboard::MetricsController` (nested under apps — with Chartkick)
- `Dashboard::TeamsController`

Each controller loads data, authorizes, renders Turbo-compatible views.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add dashboard controllers and views for all features"
```

---

### Task 27: Stimulus Controllers for Real-time Features

**Files:**
- Create: `app/javascript/controllers/log_stream_controller.js`
- Create: `app/javascript/controllers/deploy_controller.js`
- Create: `app/javascript/controllers/metrics_chart_controller.js`

- [ ] **Step 1: Log stream controller**

```javascript
// app/javascript/controllers/log_stream_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = { appId: Number }
  static targets = ["output"]

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "LogChannel", app_id: this.appIdValue },
      {
        received: (data) => {
          if (data.type === "log") {
            this.outputTarget.textContent += data.data
            this.outputTarget.scrollTop = this.outputTarget.scrollHeight
          }
        }
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }
}
```

- [ ] **Step 2: Deploy progress controller**

Similar pattern — subscribes to DeployChannel, updates deploy log and status badge.

- [ ] **Step 3: Metrics chart controller**

Uses Chartkick to render CPU/memory charts. Polls `/dashboard/apps/:id/metrics.json` every 30 seconds to refresh.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Stimulus controllers for log streaming, deploys, and metrics"
```

---

## Chunk 6: Git SSH Server

### Task 28: Git SSH Server

**Files:**
- Create: `app/services/git/server.rb`
- Create: `app/services/git/deploy_forwarder.rb`
- Create: `lib/tasks/git_server.rake`

This is the most complex component. It runs a lightweight SSH server that accepts git pushes.

- [ ] **Step 1: Create Git SSH server**

```ruby
# app/services/git/server.rb
module Git
  class Server
    def initialize(host: "0.0.0.0", port: 2222)
      @host = host
      @port = port
    end

    def start
      require "socket"

      server = TCPServer.new(@host, @port)
      Rails.logger.info("Git SSH server listening on #{@host}:#{@port}")

      loop do
        Thread.start(server.accept) do |client|
          handle_connection(client)
        end
      end
    end

    private

    def handle_connection(client)
      transport = Net::SSH::Transport::Session.new(client)
      auth = authenticate(transport)
      return unless auth

      user, command, app_name = auth
      DeployForwarder.new(user, app_name).forward(transport)
    rescue StandardError => e
      Rails.logger.error("Git server error: #{e.message}")
    ensure
      client&.close
    end

    def authenticate(transport)
      # Match SSH public key fingerprint to SshPublicKey record
      # Extract git-receive-pack command and app name
      # Return [user, command, app_name] or nil
    end
  end
end
```

Note: The full SSH server implementation requires `net-ssh` server-side capabilities. In practice, a simpler approach is to use `sshd` with a custom `AuthorizedKeysCommand` and `ForceCommand` that delegates to a Rails runner script. This avoids implementing SSH protocol from scratch.

**Alternative (recommended) approach:**

Run system `sshd` on port 2222 with:
- `AuthorizedKeysCommand` pointing to a script that queries Herodokku DB for SSH keys
- `ForceCommand` pointing to a script that handles `git-receive-pack`

```bash
# bin/git-auth-keys — called by sshd AuthorizedKeysCommand
#!/usr/bin/env ruby
require_relative "../config/environment"
fingerprint = ARGV[0]
key = SshPublicKey.find_by(fingerprint: fingerprint)
puts key&.public_key
```

```bash
# bin/git-receive — called as ForceCommand
#!/usr/bin/env ruby
require_relative "../config/environment"
# Parse SSH_ORIGINAL_COMMAND for git-receive-pack
# Look up app, check auth, forward to Dokku
```

- [ ] **Step 2: Create DeployForwarder**

```ruby
# app/services/git/deploy_forwarder.rb
module Git
  class DeployForwarder
    def initialize(user, app_name)
      @user = user
      @app_name = app_name
    end

    def forward
      app = AppRecord.find_by!(name: @app_name)
      policy = AppRecordPolicy.new(@user, app)
      raise Pundit::NotAuthorizedError unless policy.update?

      # Create release and deploy
      release = app.releases.create!(description: "Deploy via git push")
      deploy = app.deploys.create!(release: release, status: :pending)

      # Forward git push to Dokku server
      client = Dokku::Client.new(app.server)
      deploy.update!(status: :building, started_at: Time.current)

      log = ""
      # In reality: pipe git pack data to Dokku's git-receive-pack
      # For now: use Dokku's git:sync or trigger rebuild
      client.run_streaming("-- git-receive-pack '#{app.name}'") do |data|
        log << data
        DeployChannel.broadcast_to(deploy, { type: "log", data: data })
      end

      deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
      app.update!(status: :running)
    rescue StandardError => e
      deploy&.update(status: :failed, log: "#{log}\n#{e.message}", finished_at: Time.current)
      raise
    end
  end
end
```

- [ ] **Step 3: Create rake task**

```ruby
# lib/tasks/git_server.rake
namespace :git do
  desc "Start the Git SSH server"
  task server: :environment do
    Git::Server.new(
      host: ENV.fetch("GIT_HOST", "0.0.0.0"),
      port: ENV.fetch("GIT_PORT", 2222).to_i
    ).start
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Git SSH server and deploy forwarder"
```

---

## Chunk 7: CLI Gem

### Task 29: CLI Gem Scaffold

**Files:**
- Create: `cli/` directory structure

- [ ] **Step 1: Create gem structure**

```bash
mkdir -p cli/{lib/herodokku/commands,mcp/tools,exe,spec}
```

- [ ] **Step 2: Create gemspec**

```ruby
# cli/herodokku-cli.gemspec
Gem::Specification.new do |spec|
  spec.name          = "herodokku-cli"
  spec.version       = "0.1.0"
  spec.authors       = ["Johannes Dwicahyo"]
  spec.summary       = "CLI for Herodokku - Heroku-like PaaS on Dokku"
  spec.homepage      = "https://github.com/johannesdwicahyo/herodokku"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*", "exe/*", "mcp/**/*"]
  spec.bindir        = "exe"
  spec.executables   = ["herodokku"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "pastel", "~> 0.8"
end
```

- [ ] **Step 3: Create Gemfile**

```ruby
# cli/Gemfile
source "https://rubygems.org"
gemspec
```

- [ ] **Step 4: Create entrypoint**

```ruby
# cli/exe/herodokku
#!/usr/bin/env ruby
require "herodokku"
Herodokku::CLI.start(ARGV)
```

```bash
chmod +x cli/exe/herodokku
```

- [ ] **Step 5: Create main module**

```ruby
# cli/lib/herodokku.rb
require "herodokku/version"
require "herodokku/config_store"
require "herodokku/api_client"
require "herodokku/cli"

module Herodokku
  class Error < StandardError; end
end
```

```ruby
# cli/lib/herodokku/version.rb
module Herodokku
  VERSION = "0.1.0"
end
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold CLI gem structure"
```

---

### Task 30: CLI Config Store & API Client

**Files:**
- Create: `cli/lib/herodokku/config_store.rb`
- Create: `cli/lib/herodokku/api_client.rb`

- [ ] **Step 1: Create config store**

```ruby
# cli/lib/herodokku/config_store.rb
require "json"
require "fileutils"

module Herodokku
  class ConfigStore
    CONFIG_DIR = File.expand_path("~/.herodokku")
    CONFIG_FILE = File.join(CONFIG_DIR, "config")

    def self.load
      return {} unless File.exist?(CONFIG_FILE)
      JSON.parse(File.read(CONFIG_FILE))
    rescue JSON::ParserError
      {}
    end

    def self.save(data)
      FileUtils.mkdir_p(CONFIG_DIR)
      File.write(CONFIG_FILE, JSON.pretty_generate(data))
      File.chmod(0600, CONFIG_FILE)
    end

    def self.get(key)
      load[key.to_s]
    end

    def self.set(key, value)
      config = load
      config[key.to_s] = value
      save(config)
    end

    def self.clear
      File.delete(CONFIG_FILE) if File.exist?(CONFIG_FILE)
    end

    def self.api_url
      get("api_url") || ENV["HERODOKKU_API_URL"]
    end

    def self.token
      get("token") || ENV["HERODOKKU_TOKEN"]
    end
  end
end
```

- [ ] **Step 2: Create API client**

```ruby
# cli/lib/herodokku/api_client.rb
require "faraday"
require "json"

module Herodokku
  class ApiClient
    class ApiError < StandardError
      attr_reader :status
      def initialize(message, status:)
        @status = status
        super(message)
      end
    end

    def initialize
      @url = ConfigStore.api_url
      @token = ConfigStore.token

      raise Error, "Not logged in. Run: herodokku login" unless @url && @token

      @conn = Faraday.new(url: @url) do |f|
        f.request :json
        f.response :json
        f.headers["Authorization"] = "Bearer #{@token}"
      end
    end

    def get(path, params = {})
      response = @conn.get("/api/v1/#{path}", params)
      handle_response(response)
    end

    def post(path, body = {})
      response = @conn.post("/api/v1/#{path}", body)
      handle_response(response)
    end

    def patch(path, body = {})
      response = @conn.patch("/api/v1/#{path}", body)
      handle_response(response)
    end

    def delete(path, body = {})
      response = @conn.delete("/api/v1/#{path}") { |req| req.body = body.to_json }
      handle_response(response)
    end

    private

    def handle_response(response)
      case response.status
      when 200..299
        response.body
      when 401
        raise ApiError.new("Unauthorized. Run: herodokku login", status: 401)
      when 404
        raise ApiError.new("Not found", status: 404)
      else
        error_msg = response.body.is_a?(Hash) ? response.body["error"] : response.body.to_s
        raise ApiError.new(error_msg || "Request failed (#{response.status})", status: response.status)
      end
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add CLI config store and API client"
```

---

### Task 31: CLI Commands

**Files:**
- Create: `cli/lib/herodokku/cli.rb`
- Create: all command files in `cli/lib/herodokku/commands/`

- [ ] **Step 1: Create main CLI with Thor**

```ruby
# cli/lib/herodokku/cli.rb
require "thor"

module Herodokku
  class CLI < Thor
    desc "login", "Log in to Herodokku"
    def login
      require "herodokku/commands/auth"
      Commands::Auth.new.login
    end

    desc "logout", "Log out"
    def logout
      require "herodokku/commands/auth"
      Commands::Auth.new.logout
    end

    desc "whoami", "Show current user"
    def whoami
      require "herodokku/commands/auth"
      Commands::Auth.new.whoami
    end

    desc "apps", "List apps"
    def apps
      require "herodokku/commands/apps"
      Commands::Apps.new.list
    end

    desc "apps:create NAME", "Create an app"
    def apps_create(name)
      require "herodokku/commands/apps"
      Commands::Apps.new.create(name, options)
    end

    desc "apps:destroy NAME", "Destroy an app"
    def apps_destroy(name)
      require "herodokku/commands/apps"
      Commands::Apps.new.destroy(name)
    end

    desc "apps:info", "Show app info"
    method_option :app, aliases: "-a", required: true
    def apps_info
      require "herodokku/commands/apps"
      Commands::Apps.new.info(options[:app])
    end

    desc "config", "Show config vars"
    method_option :app, aliases: "-a", required: true
    def config
      require "herodokku/commands/config"
      Commands::Config.new.list(options[:app])
    end

    desc "config:set", "Set config vars"
    method_option :app, aliases: "-a", required: true
    def config_set(*pairs)
      require "herodokku/commands/config"
      Commands::Config.new.set(options[:app], pairs)
    end

    desc "config:unset", "Unset config vars"
    method_option :app, aliases: "-a", required: true
    def config_unset(*keys)
      require "herodokku/commands/config"
      Commands::Config.new.unset(options[:app], keys)
    end

    desc "logs", "Show app logs"
    method_option :app, aliases: "-a", required: true
    method_option :tail, type: :boolean, default: false
    def logs
      require "herodokku/commands/logs"
      Commands::Logs.new.show(options[:app], tail: options[:tail])
    end

    desc "ps", "Show process list"
    method_option :app, aliases: "-a", required: true
    def ps
      require "herodokku/commands/ps"
      Commands::Ps.new.list(options[:app])
    end

    desc "ps:scale", "Scale processes"
    method_option :app, aliases: "-a", required: true
    def ps_scale(*pairs)
      require "herodokku/commands/ps"
      Commands::Ps.new.scale(options[:app], pairs)
    end

    desc "ps:restart", "Restart app"
    method_option :app, aliases: "-a", required: true
    def ps_restart
      require "herodokku/commands/ps"
      Commands::Ps.new.restart(options[:app])
    end

    desc "domains", "List domains"
    method_option :app, aliases: "-a", required: true
    def domains
      require "herodokku/commands/domains"
      Commands::Domains.new.list(options[:app])
    end

    desc "domains:add DOMAIN", "Add domain"
    method_option :app, aliases: "-a", required: true
    def domains_add(domain)
      require "herodokku/commands/domains"
      Commands::Domains.new.add(options[:app], domain)
    end

    desc "domains:remove DOMAIN", "Remove domain"
    method_option :app, aliases: "-a", required: true
    def domains_remove(domain)
      require "herodokku/commands/domains"
      Commands::Domains.new.remove(options[:app], domain)
    end

    desc "addons", "List addons"
    method_option :app, aliases: "-a", required: true
    def addons
      require "herodokku/commands/addons"
      Commands::Addons.new.list(options[:app])
    end

    desc "addons:create TYPE", "Create addon"
    def addons_create(type)
      require "herodokku/commands/addons"
      Commands::Addons.new.create(type, options)
    end

    desc "releases", "Show release history"
    method_option :app, aliases: "-a", required: true
    def releases
      require "herodokku/commands/releases"
      Commands::Releases.new.list(options[:app])
    end

    desc "servers", "List servers"
    def servers
      require "herodokku/commands/servers"
      Commands::Servers.new.list
    end

    desc "servers:add NAME", "Add server"
    method_option :host, required: true
    method_option :key, desc: "Path to SSH private key"
    method_option :port, type: :numeric, default: 22
    def servers_add(name)
      require "herodokku/commands/servers"
      Commands::Servers.new.add(name, options)
    end

    desc "git:remote", "Add git remote"
    method_option :app, aliases: "-a", required: true
    def git_remote
      require "herodokku/commands/git"
      Commands::Git.new.add_remote(options[:app])
    end

    desc "mcp:start", "Start MCP server"
    def mcp_start
      require "herodokku/mcp/server"
      Herodokku::MCP::Server.new.start
    end
  end
end
```

- [ ] **Step 2: Create Auth command**

```ruby
# cli/lib/herodokku/commands/auth.rb
require "tty-prompt"

module Herodokku
  module Commands
    class Auth
      def login
        prompt = TTY::Prompt.new

        url = prompt.ask("Herodokku API URL:", default: "http://localhost:3000")
        email = prompt.ask("Email:")
        password = prompt.mask("Password:")

        conn = Faraday.new(url: url) do |f|
          f.request :json
          f.response :json
        end

        response = conn.post("/api/v1/auth/login", { email: email, password: password })

        if response.status == 201
          data = response.body
          ConfigStore.set("api_url", url)
          ConfigStore.set("token", data["token"])
          puts "Logged in as #{data['user']['email']}"
        else
          puts "Login failed: #{response.body['error']}"
          exit 1
        end
      end

      def logout
        client = ApiClient.new
        client.delete("auth/logout")
        ConfigStore.clear
        puts "Logged out"
      rescue ApiClient::ApiError => e
        puts "Error: #{e.message}"
      end

      def whoami
        client = ApiClient.new
        data = client.get("auth/whoami")
        puts "#{data['email']} (#{data['role']})"
      end
    end
  end
end
```

- [ ] **Step 3: Create Apps command**

```ruby
# cli/lib/herodokku/commands/apps.rb
require "tty-table"
require "pastel"

module Herodokku
  module Commands
    class Apps
      def list
        client = ApiClient.new
        apps = client.get("apps")

        if apps.empty?
          puts "No apps. Create one with: herodokku apps:create <name>"
          return
        end

        pastel = Pastel.new
        table = TTY::Table.new(
          header: ["Name", "Status", "Server", "Created"],
          rows: apps.map { |a|
            status = case a["status"]
            when "running" then pastel.green(a["status"])
            when "stopped" then pastel.yellow(a["status"])
            else pastel.red(a["status"])
            end
            [a["name"], status, a["server_id"], a["created_at"]]
          }
        )
        puts table.render(:unicode)
      end

      def create(name, options)
        client = ApiClient.new
        app = client.post("apps", { name: name, server_id: options[:server] })
        puts "Created app #{app['name']}"
      end

      def destroy(name)
        prompt = TTY::Prompt.new
        return unless prompt.yes?("Are you sure you want to destroy #{name}?")

        client = ApiClient.new
        # Find app by name first
        apps = client.get("apps")
        app = apps.find { |a| a["name"] == name }
        raise Error, "App not found: #{name}" unless app

        client.delete("apps/#{app['id']}")
        puts "Destroyed #{name}"
      end

      def info(app_name)
        client = ApiClient.new
        apps = client.get("apps")
        app = apps.find { |a| a["name"] == app_name }
        raise Error, "App not found: #{app_name}" unless app

        data = client.get("apps/#{app['id']}")
        data.each { |k, v| puts "#{k}: #{v}" }
      end
    end
  end
end
```

- [ ] **Step 4: Create remaining command files**

Follow same pattern for: `config.rb`, `domains.rb`, `addons.rb`, `ps.rb`, `logs.rb`, `releases.rb`, `servers.rb`, `git.rb`, `teams.rb`, `notifications.rb`.

Each command file:
1. Instantiates `ApiClient`
2. Makes the appropriate API call
3. Formats output with `tty-table` and `pastel`

- [ ] **Step 5: Bundle install in cli directory**

```bash
cd cli && bundle install && cd ..
```

- [ ] **Step 6: Test CLI locally**

```bash
cd cli && bundle exec ruby exe/herodokku help && cd ..
```

Expected: Thor help output showing all commands.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add CLI commands (auth, apps, config, domains, ps, logs, servers, etc.)"
```

---

## Chunk 8: MCP Server

### Task 32: MCP Server

**Files:**
- Create: `cli/mcp/server.rb`
- Create: `cli/mcp/tools/*.rb`

- [ ] **Step 1: Create MCP server**

```ruby
# cli/mcp/server.rb
require "json"

module Herodokku
  module MCP
    class Server
      TOOLS = {}

      def self.register_tool(name, description:, input_schema:, &handler)
        TOOLS[name] = { description: description, input_schema: input_schema, handler: handler }
      end

      def start
        # Load all tools
        Dir[File.join(__dir__, "tools", "*.rb")].each { |f| require f }

        $stderr.puts "Herodokku MCP server started"

        loop do
          line = $stdin.gets
          break unless line

          request = JSON.parse(line)
          response = handle_request(request)
          $stdout.puts(JSON.generate(response))
          $stdout.flush
        end
      end

      private

      def handle_request(request)
        case request["method"]
        when "initialize"
          {
            jsonrpc: "2.0",
            id: request["id"],
            result: {
              protocolVersion: "2024-11-05",
              capabilities: { tools: {} },
              serverInfo: { name: "herodokku", version: Herodokku::VERSION }
            }
          }
        when "tools/list"
          {
            jsonrpc: "2.0",
            id: request["id"],
            result: {
              tools: TOOLS.map { |name, tool|
                { name: name, description: tool[:description], inputSchema: tool[:input_schema] }
              }
            }
          }
        when "tools/call"
          tool_name = request.dig("params", "name")
          arguments = request.dig("params", "arguments") || {}
          tool = TOOLS[tool_name]

          unless tool
            return error_response(request["id"], "Unknown tool: #{tool_name}")
          end

          begin
            result = tool[:handler].call(arguments)
            {
              jsonrpc: "2.0",
              id: request["id"],
              result: { content: [{ type: "text", text: result.to_s }] }
            }
          rescue StandardError => e
            {
              jsonrpc: "2.0",
              id: request["id"],
              result: { content: [{ type: "text", text: "Error: #{e.message}" }], isError: true }
            }
          end
        else
          error_response(request["id"], "Unknown method: #{request['method']}")
        end
      end

      def error_response(id, message)
        { jsonrpc: "2.0", id: id, error: { code: -32601, message: message } }
      end
    end
  end
end
```

- [ ] **Step 2: Create tool definitions**

```ruby
# cli/mcp/tools/apps.rb
require "herodokku/api_client"

Herodokku::MCP::Server.register_tool(
  "apps_list",
  description: "List all apps",
  input_schema: {
    type: "object",
    properties: { server: { type: "string", description: "Filter by server name" } }
  }
) do |args|
  client = Herodokku::ApiClient.new
  apps = client.get("apps")
  apps.map { |a| "#{a['name']} (#{a['status']})" }.join("\n")
end

Herodokku::MCP::Server.register_tool(
  "app_create",
  description: "Create a new app on Dokku",
  input_schema: {
    type: "object",
    properties: {
      name: { type: "string", description: "App name" },
      server_id: { type: "integer", description: "Server ID to create app on" }
    },
    required: ["name", "server_id"]
  }
) do |args|
  client = Herodokku::ApiClient.new
  result = client.post("apps", args)
  "Created app: #{result['name']}"
end

Herodokku::MCP::Server.register_tool(
  "app_info",
  description: "Get detailed info about an app",
  input_schema: {
    type: "object",
    properties: { app: { type: "string", description: "App name or ID" } },
    required: ["app"]
  }
) do |args|
  client = Herodokku::ApiClient.new
  result = client.get("apps/#{args['app']}")
  JSON.pretty_generate(result)
end

Herodokku::MCP::Server.register_tool(
  "app_restart",
  description: "Restart an app",
  input_schema: {
    type: "object",
    properties: { app: { type: "string", description: "App ID" } },
    required: ["app"]
  }
) do |args|
  client = Herodokku::ApiClient.new
  client.post("apps/#{args['app']}/restart")
  "App restarted"
end
```

- [ ] **Step 3: Create remaining tool files**

Create `cli/mcp/tools/config.rb`, `domains.rb`, `databases.rb`, `ps.rb`, `logs.rb`, `deploys.rb`, `servers.rb`, `teams.rb`, `notifications.rb`.

Each file registers tools using the same `register_tool` pattern — calls `ApiClient` methods and returns formatted text.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add MCP server with tool definitions for all features"
```

---

## Chunk 9: Deployment & Polish

### Task 33: Docker & Deployment Files

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `Procfile`
- Create: `.env.example`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
FROM ruby:3.3-slim

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs git openssh-client

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY . .

RUN bundle exec rails assets:precompile

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
```

- [ ] **Step 2: Create docker-compose.yml**

```yaml
services:
  web:
    build: .
    ports: ["3000:3000"]
    depends_on: [db, redis]
    env_file: .env
    command: bin/rails server -b 0.0.0.0

  worker:
    build: .
    depends_on: [db, redis]
    env_file: .env
    command: bin/jobs

  git:
    build: .
    depends_on: [db]
    env_file: .env
    command: bin/rails git:server
    ports: ["2222:2222"]

  db:
    image: postgres:16
    volumes: ["postgres_data:/var/lib/postgresql/data"]
    environment:
      POSTGRES_PASSWORD: herodokku

  redis:
    image: redis:7
    volumes: ["redis_data:/data"]

volumes:
  postgres_data:
  redis_data:
```

- [ ] **Step 3: Create Procfile**

```
web: bin/rails server -b 0.0.0.0 -p $PORT
worker: bin/jobs
git: bin/rails git:server
```

- [ ] **Step 4: Create .env.example**

```
DATABASE_URL=postgres://postgres:herodokku@db:5432/herodokku
REDIS_URL=redis://redis:6379/0
SECRET_KEY_BASE=generate-with-rails-secret
GIT_HOST=0.0.0.0
GIT_PORT=2222
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Docker, docker-compose, and Procfile for deployment"
```

---

### Task 34: CORS & API Configuration

**Files:**
- Create: `config/initializers/cors.rb`
- Modify: `config/cable.yml`

- [ ] **Step 1: Configure CORS**

```ruby
# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "/api/*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
```

- [ ] **Step 2: Configure Action Cable for Redis**

```yaml
# config/cable.yml
development:
  adapter: redis
  url: redis://localhost:6379/1

test:
  adapter: test

production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: configure CORS and Action Cable with Redis"
```

---

### Task 35: Seeds & Final Verification

**Files:**
- Modify: `db/seeds.rb`

- [ ] **Step 1: Create seed data**

```ruby
# db/seeds.rb
admin = User.create!(email: "admin@herodokku.local", password: "password123456", role: :admin)
team = Team.create!(name: "Default", owner: admin)
TeamMembership.create!(user: admin, team: team, role: :admin)

puts "Created admin user: admin@herodokku.local / password123456"
puts "Created default team: Default"
```

- [ ] **Step 2: Run full test suite**

```bash
bin/rails db:migrate
bin/rails db:seed
bin/rails test
```

Expected: All tests pass.

- [ ] **Step 3: Verify Rails server starts**

```bash
bin/rails server
```

Visit `http://localhost:3000` — should see Devise login page.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: add seeds and finalize v1 setup"
```

---

## Summary

| Chunk | Tasks | What it delivers |
|-------|-------|-----------------|
| 1: Foundation | 1-7 | Rails app, Devise auth, API tokens, Pundit, SshPublicKey |
| 2: Core Models & SSH | 8-13 | All 16 models, Dokku SSH client, service modules |
| 3: API Controllers | 14-17 | Full REST API for all features |
| 4: Background Jobs | 18-24 | Health checks, sync, deploys, metrics, notifications, scheduling |
| 5: Dashboard | 25-27 | Hotwire/Turbo dashboard with Stimulus for real-time |
| 6: Git SSH Server | 28 | Git push to Herodokku with deploy forwarding |
| 7: CLI Gem | 29-31 | Thor-based CLI with all commands |
| 8: MCP Server | 32 | MCP server with tool definitions |
| 9: Deployment | 33-35 | Docker, docker-compose, Procfile, seeds |
