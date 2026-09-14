class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :security_events do |t|
      t.references :user, null: true, foreign_key: true
      t.string :event_type, null: false, limit: 50
      t.string :ip_address, limit: 45
      t.datetime :created_at, null: false
    end

    add_index :security_events, :event_type
    add_index :security_events, :created_at
  end
end
