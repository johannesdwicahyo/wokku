class AddCreatorAndLastErrorToDatabaseServices < ActiveRecord::Migration[8.1]
  def change
    add_reference :database_services, :creator, foreign_key: { to_table: :users }, type: :uuid, null: true
    add_column    :database_services, :last_error, :text
  end
end
