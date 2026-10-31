# Swarm ports only ever move forward. max(swarm_port)+1 handed a deleted
# app's port to the next new app, and when that app's service had outlived
# its row (failed teardown) the new deploy failed "port already in use".
class CreateSwarmPortSeq < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE SEQUENCE swarm_port_seq MINVALUE 20000 MAXVALUE 29999"
    execute "SELECT setval('swarm_port_seq', GREATEST((SELECT MAX(swarm_port) FROM app_records), 20000))"
  end

  def down
    execute "DROP SEQUENCE swarm_port_seq"
  end
end
