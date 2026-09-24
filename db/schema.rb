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

ActiveRecord::Schema[8.1].define(version: 2026_09_24_170000) do
  create_table "feeds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "etag"
    t.string "feed_url"
    t.integer "fetch_failures_count", default: 0, null: false
    t.integer "folder_id"
    t.string "last_fetch_detail"
    t.datetime "last_fetch_error_at"
    t.string "last_fetch_status"
    t.datetime "last_fetched_at"
    t.string "last_modified"
    t.string "link"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["folder_id"], name: "index_feeds_on_folder_id"
    t.index ["user_id"], name: "index_feeds_on_user_id"
  end

  create_table "fetch_events", force: :cascade do |t|
    t.integer "bytes"
    t.datetime "created_at", null: false
    t.string "detail"
    t.integer "duration_ms"
    t.integer "feed_id", null: false
    t.integer "new_items_count", default: 0, null: false
    t.string "status", null: false
    t.index ["created_at"], name: "index_fetch_events_on_created_at"
    t.index ["feed_id", "created_at"], name: "index_fetch_events_on_feed_id_and_created_at"
    t.index ["feed_id"], name: "index_fetch_events_on_feed_id"
  end

  create_table "folders", force: :cascade do |t|
    t.boolean "collapsed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "name"], name: "index_folders_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_folders_on_user_id"
  end

  create_table "items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "feed_id", null: false
    t.string "guid"
    t.string "link"
    t.boolean "marked", default: false, null: false
    t.datetime "published_at"
    t.boolean "read", default: false, null: false
    t.string "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["feed_id", "guid"], name: "index_items_on_feed_id_and_guid", unique: true
    t.index ["feed_id"], name: "index_items_on_feed_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "theme", default: "system", null: false
    t.boolean "unread_only", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "feeds", "folders", on_delete: :nullify
  add_foreign_key "feeds", "users"
  add_foreign_key "fetch_events", "feeds"
  add_foreign_key "folders", "users"
  add_foreign_key "items", "feeds"
  add_foreign_key "sessions", "users"
end
