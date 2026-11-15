class AddDeletedAtToBackupFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :backup_files, :deleted_at, :datetime
    add_index :backup_files, [ :backup_run_id, :deleted_at ]
  end
end
