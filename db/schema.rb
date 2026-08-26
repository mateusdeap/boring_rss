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

ActiveRecord::Schema[8.1].define(version: 2026_08_24_180702) do
  create_table "feeds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "feed_url"
    t.string "link"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "feed_id", null: false
    t.string "guid"
    t.string "link"
    t.datetime "published_at"
    t.boolean "read", default: false, null: false
    t.string "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["feed_id", "guid"], name: "index_items_on_feed_id_and_guid", unique: true
    t.index ["feed_id"], name: "index_items_on_feed_id"
  end

  add_foreign_key "items", "feeds"
end
