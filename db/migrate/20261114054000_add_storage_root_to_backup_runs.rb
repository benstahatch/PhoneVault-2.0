class AddStorageRootToBackupRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :backup_runs, :storage_root, :text
  end
end
