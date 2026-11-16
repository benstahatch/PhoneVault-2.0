class RemoveBackupSubdirectoryFromBackupRuns < ActiveRecord::Migration[8.1]
  def change
    # every run records its folder in storage_root; a blank storage_root means the default root
    remove_column :backup_runs, :backup_subdirectory, :string, null: false, default: ""
  end
end
