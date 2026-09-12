class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username,	null: false, limit: 50
      t.string :display_name,	null: false, limit: 100
      t.string :password_digest, null: false

      t.timestamps

      t.index :username, unique: true
    end
  end
end
