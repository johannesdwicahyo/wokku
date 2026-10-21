# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 team members", type: :request do
  let(:user) { users(:one) }
  let(:team) { teams(:one) }
  let(:foreign_team) do
    owner = User.create!(email: "foreign-owner@example.com", password: "password123456")
    Team.create!(name: "foreign-team", owner: owner).tap { |t| TeamMembership.create!(user: owner, team: t, role: :admin) }
  end
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  path "/api/v1/teams/{team_id}/members" do
    parameter name: :team_id, in: :path, schema: { type: :string, format: :uuid }

    get "List team members" do
      operationId "team_members.list"
      tags "team_members"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "members" do
        let(:team_id) { team.id }
        schema type: :array, items: { "$ref" => "#/components/schemas/TeamMember" }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:team_id) { team.id }
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "404", "team the caller does not belong to" do
        let(:team_id) { foreign_team.id }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Add an existing user to the team (team admin only)" do
      operationId "team_members.create"
      tags "team_members"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[email],
        properties: { email: { type: :string }, role: { type: :string, enum: %w[viewer member admin], default: "member" } }
      }
      let(:team_id) { team.id }

      response "201", "member added" do
        let(:payload) do
          { email: User.create!(email: "new-member@example.com", password: "password123456").email, role: "member" }
        end
        schema "$ref" => "#/components/schemas/TeamMember"
        run_test!
      end

      response "404", "no user with that email" do
        let(:payload) { { email: "nobody@example.com" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "422", "already a member" do
        let(:payload) { { email: user.email } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/teams/{team_id}/members/{id}" do
    parameter name: :team_id, in: :path, schema: { type: :string, format: :uuid }
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Remove a team member (membership id)" do
      operationId "team_members.delete"
      tags "team_members"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:team_id) { team.id }

      response "200", "removed" do
        let(:id) do
          TeamMembership.create!(user: User.create!(email: "drop@example.com", password: "password123456"),
                                 team: team, role: :member).id
        end
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "404", "membership of a team the caller does not belong to" do
        let(:team_id) { foreign_team.id }
        let(:id) { foreign_team.team_memberships.first.id }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end
