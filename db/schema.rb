# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_14_000729) do
  create_table "backup_files", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "backup_run_id", null: false
    t.datetime "created_at", null: false
    t.string "original_filename", null: false
    t.string "sha256", limit: 64, null: false
    t.bigint "size_bytes", null: false
    t.string "storage_path", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_run_id"], name: "index_backup_files_on_backup_run_id"
    t.index ["sha256"], name: "index_backup_files_on_sha256"
  end

  create_table "backup_runs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "device_id", null: false
    t.datetime "started_at"
    t.string "status", limit: 20, null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_backup_runs_on_device_id"
    t.index ["status"], name: "index_backup_runs_on_status"
  end

  create_table "devices", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_type", limit: 20, null: false
    t.string "name", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "index_devices_on_user_id_and_name", unique: true
  end

  create_table "security_events", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", limit: 50, null: false
    t.string "ip_address", limit: 45
    t.bigint "user_id"
    t.index ["created_at"], name: "index_security_events_on_created_at"
    t.index ["event_type"], name: "index_security_events_on_event_type"
    t.index ["user_id"], name: "index_security_events_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", limit: 100, null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", limit: 50, null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "backup_files", "backup_runs"
  add_foreign_key "backup_runs", "devices"
  add_foreign_key "devices", "users"
  add_foreign_key "security_events", "users"
end
