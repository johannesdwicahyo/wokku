class AddDockerStatusToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :docker_status, :string
    add_column :servers, :docker_status_checked_at, :datetime
  end
end
