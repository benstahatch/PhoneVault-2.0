class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :name,      null: false, limit: 100
      t.string :device_type, null: false, limit: 20

      t.timestamps

      t.index [ :user_id, :name ], unique: true
    end
  end
end
