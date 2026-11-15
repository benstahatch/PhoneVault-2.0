class AddTrashRetentionDaysToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :trash_retention_days, :integer
    add_index :users, :trash_retention_days
  end
end
