require "test_helper"

class Dokku::SharedPostgresTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls, :stdin_calls

    def initialize(list_output: "")
      @list_output = list_output
      @calls = []
      @stdin_calls = []
    end

    def run(cmd, timeout: 30, stdin: nil)
      @calls << cmd
      @stdin_calls << stdin if stdin
      case cmd
      when "postgres:list"
        @list_output
      else
        "" # default: empty response
      end
    end
  end

  def service(list: "")
    Dokku::SharedPostgres.new(FakeClient.new(list_output: list))
  end

  # --- Host container bootstrap ---

  test "ensure_host! creates host container when absent" do
    c = FakeClient.new(list_output: "=====> postgres services\nother-db\n")
    Dokku::SharedPostgres.new(c).ensure_host!
    assert_includes c.calls, "postgres:create wokku-shared-free"
  end

  test "ensure_host! is idempotent when host already exists" do
    c = FakeClient.new(list_output: "=====> postgres services\nwokku-shared-free\n")
    Dokku::SharedPostgres.new(c).ensure_host!
    refute c.calls.any? { |cmd| cmd.include?("postgres:create") },
      "should not re-create existing host"
  end

  # --- Provisioning shape ---

  test "provision_tenant! returns role, db, password, host" do
    c = FakeClient.new(list_output: "wokku-shared-free\n")
    result = Dokku::SharedPostgres.new(c).provision_tenant!(slug: "myapp")

    assert_match(/\Au_myapp_[a-f0-9]{8}\z/, result[:role_name])
    assert_match(/\Adb_myapp_[a-f0-9]{8}\z/, result[:db_name])
    assert result[:password].length >= 24
    assert_equal 5, result[:connection_limit]
    assert_equal "wokku-shared-free", result[:host_container]
  end

  # --- Security-critical SQL ---

  test "provisioning SQL creates role with no superuser / no createdb / no createrole" do
    c = FakeClient.new(list_output: "wokku-shared-free\n")
    Dokku::SharedPostgres.new(c).provision_tenant!(slug: "secapp")
    sql = c.stdin_calls.last

    assert_match(/CREATE ROLE /, sql)
    assert_match(/NOSUPERUSER/, sql)
    assert_match(/NOCREATEDB/, sql)
    assert_match(/NOCREATEROLE/, sql)
    assert_match(/NOINHERIT/, sql)
  end

  test "provisioning SQL sets statement_timeout, temp_file_limit, connection limit" do
    c = FakeClient.new(list_output: "wokku-shared-free\n")
    Dokku::SharedPostgres.new(c).provision_tenant!(slug: "sec2", connection_limit: 3)
    sql = c.stdin_calls.last

    assert_match(/CONNECTION LIMIT 3/, sql)
    assert_match(/statement_timeout = '30s'/, sql)
    assert_match(/idle_in_transaction_session_timeout = '60s'/, sql)
    assert_match(/temp_file_limit = '100MB'/, sql)
  end

  test "provisioning SQL revokes PUBLIC access and CREATE from tenant role" do
    c = FakeClient.new(list_output: "wokku-shared-free\n")
    Dokku::SharedPostgres.new(c).provision_tenant!(slug: "sec3")
    sql = c.stdin_calls.last

    assert_match(/REVOKE ALL ON DATABASE .+ FROM PUBLIC/, sql)
    assert_match(/REVOKE CREATE ON DATABASE .+ FROM /, sql)
    assert_match(/GRANT CONNECT, TEMPORARY ON DATABASE/, sql)
  end

  # --- Identifier safety ---

  test "destroy_tenant! refuses invalid identifiers (SQL injection guard)" do
    c = FakeClient.new(list_output: "wokku-shared-free\n")
    svc = Dokku::SharedPostgres.new(c)

    svc.destroy_tenant!(role_name: "u_ok_12345678", db_name: "db; DROP TABLE users;--")

    # Should not have executed any SQL for the bad identifier
    assert_empty c.stdin_calls, "must not run SQL with invalid identifier"
  end

  test "dump_command rejects invalid db names" do
    svc = service
    assert_raises(Dokku::SharedPostgres::Error) do
      svc.dump_command("bad; DROP DATABASE postgres")
    end
  end

  test "dump_command emits per-db pg_dump (never pg_dumpall)" do
    cmd = service.dump_command("db_ok_12345678")
    assert_match(/pg_dump -d db_ok_12345678/, cmd)
    refute_match(/pg_dumpall/, cmd)
  end

  # --- Connection string ---

  test "connection_string includes role, password, db, host" do
    url = service.connection_string(role_name: "u_x_12345678", db_name: "db_x_12345678", password: "secret")
    assert_equal "postgres://u_x_12345678:secret@dokku-postgres-wokku-shared-free:5432/db_x_12345678", url
  end

  # --- Write revocation (quota enforcement soft-suspend) ---

  test "revoke_writes! disables INSERT/UPDATE/DELETE but leaves SELECT intact" do
    c = FakeClient.new(list_output: "wokku-shared-free\n")
    Dokku::SharedPostgres.new(c).revoke_writes!(role_name: "u_ok_12345678", db_name: "db_ok_12345678")
    sql = c.stdin_calls.last

    assert_match(/REVOKE INSERT, UPDATE, DELETE/, sql)
    refute_match(/REVOKE SELECT/, sql)
  end

  # --- Tenant destroy ---

  test "destroy_tenant! terminates active sessions and drops DB + role" do
    c = FakeClient.new(list_output: "wokku-shared-free\n")
    Dokku::SharedPostgres.new(c).destroy_tenant!(role_name: "u_ok_12345678", db_name: "db_ok_12345678")
    sql = c.stdin_calls.last

    assert_match(/pg_terminate_backend/, sql)
    assert_match(/DROP DATABASE IF EXISTS/, sql)
    assert_match(/DROP ROLE IF EXISTS/, sql)
  end
end
