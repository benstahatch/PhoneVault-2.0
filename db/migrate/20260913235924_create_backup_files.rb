class CreateBackupFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_files do |t|
      t.references :backup_run, null: false, foreign_key: true
      t.string :original_filename, null: false 
      t.string :storage_path, null: false 
      t.bigint :size_bytes, null: false 
      t.string :sha256, null: false, limit: 64


      t.timestamps
    end
     
    add_index :backup_files, :sha256
  end
end
