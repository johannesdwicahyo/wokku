# Close the second-admin race: the single-admin rule was enforced only by
# an application validation, so two concurrent POSTs to /setup could both
# pass the check and create two admins. A partial unique index makes the
# database the referee. if_not_exists: fresh OSS installs load it via the
# baseline structure dump before this migration runs.
class SingleAdminUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :users, :role, unique: true, where: "role = 1",
              name: "index_users_single_admin", if_not_exists: true
  end
end
