class AddBackupSubdirectoryToBackupRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :backup_runs, :backup_subdirectory, :string, null: false, default: ""
  end
end
