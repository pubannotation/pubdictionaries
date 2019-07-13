# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2018_05_12_083926) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "associations", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "dictionary_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dictionary_id"], name: "index_associations_on_dictionary_id"
    t.index ["user_id"], name: "index_associations_on_user_id"
  end

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer "priority", default: 0, null: false
    t.integer "attempts", default: 0, null: false
    t.text "handler", null: false
    t.text "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

  create_table "dictionaries", force: :cascade do |t|
    t.string "name"
    t.text "description", default: ""
    t.bigint "user_id"
    t.integer "entries_num", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "public", default: false
    t.string "license"
    t.string "license_url"
    t.index ["user_id"], name: "index_dictionaries_on_user_id"
  end

  create_table "dl_associations", force: :cascade do |t|
    t.bigint "dictionary_id"
    t.bigint "language_id"
    t.index ["dictionary_id"], name: "index_dl_associations_on_dictionary_id"
    t.index ["language_id"], name: "index_dl_associations_on_language_id"
  end

  create_table "entries", force: :cascade do |t|
    t.integer "mode", default: 0
    t.string "label"
    t.string "norm1"
    t.string "norm2"
    t.integer "label_length"
    t.string "identifier"
    t.bigint "dictionary_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dictionary_id"], name: "index_entries_on_dictionary_id"
    t.index ["identifier"], name: "index_entries_on_identifier"
    t.index ["label"], name: "index_entries_on_label"
    t.index ["label_length"], name: "index_entries_on_label_length"
    t.index ["mode"], name: "index_entries_on_mode"
    t.index ["norm1"], name: "index_entries_on_norm1"
    t.index ["norm2"], name: "index_entries_on_norm2"
  end

  create_table "jobs", force: :cascade do |t|
    t.string "name"
    t.bigint "dictionary_id"
    t.bigint "delayed_job_id"
    t.text "message"
    t.integer "num_items"
    t.integer "num_dones"
    t.datetime "begun_at"
    t.datetime "ended_at"
    t.datetime "registered_at"
    t.integer "time"
    t.index ["delayed_job_id"], name: "index_jobs_on_delayed_job_id"
    t.index ["dictionary_id"], name: "index_jobs_on_dictionary_id"
  end

  create_table "languages", force: :cascade do |t|
    t.string "name"
    t.string "abbreviation"
  end

  create_table "users", force: :cascade do |t|
    t.text "username", default: "", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

end
