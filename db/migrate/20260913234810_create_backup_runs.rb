class CreateBackupRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_runs do |t|
      t.references :device, null: false, foreign_key: true 
      t.string :status, null: false, limit: 20 
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :backup_runs, :status
  end
end
