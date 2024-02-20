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

ActiveRecord::Schema[7.0].define(version: 2024_02_20_075112) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "associations", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "dictionary_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["dictionary_id"], name: "index_associations_on_dictionary_id"
    t.index ["user_id"], name: "index_associations_on_user_id"
  end

  create_table "dictionaries", force: :cascade do |t|
    t.string "name"
    t.text "description", default: ""
    t.bigint "user_id"
    t.integer "entries_num", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "public", default: false
    t.string "license"
    t.string "license_url"
    t.text "no_term_words", default: [], array: true
    t.text "no_begin_words", default: [], array: true
    t.text "no_end_words", default: [], array: true
    t.integer "tokens_len_min", default: 1
    t.integer "tokens_len_max", default: 6
    t.float "threshold", default: 0.85
    t.string "language"
    t.integer "patterns_num", default: 0
    t.index ["user_id"], name: "index_dictionaries_on_user_id"
  end

  create_table "entries", force: :cascade do |t|
    t.integer "mode", default: 0
    t.string "label"
    t.string "norm1"
    t.string "norm2"
    t.integer "label_length"
    t.string "identifier"
    t.bigint "dictionary_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "dirty", default: false
    t.index ["dictionary_id", "label", "identifier"], name: "index_entries_on_dictionary_id_and_label_and_identifier"
    t.index ["dictionary_id"], name: "index_entries_on_dictionary_id"
    t.index ["dirty"], name: "index_entries_on_dirty"
    t.index ["identifier"], name: "index_entries_on_identifier"
    t.index ["label"], name: "index_entries_on_label"
    t.index ["label_length"], name: "index_entries_on_label_length"
    t.index ["mode"], name: "index_entries_on_mode"
    t.index ["norm1"], name: "index_entries_on_norm1"
    t.index ["norm2"], name: "index_entries_on_norm2"
  end

  create_table "jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.bigint "dictionary_id"
    t.text "message"
    t.integer "num_items"
    t.integer "num_dones"
    t.datetime "begun_at", precision: nil
    t.datetime "ended_at", precision: nil
    t.datetime "registered_at", precision: nil
    t.integer "time"
    t.string "active_job_id"
    t.string "queue_name"
    t.boolean "suspend_flag", default: false
    t.index ["dictionary_id"], name: "index_jobs_on_dictionary_id"
  end

  create_table "patterns", force: :cascade do |t|
    t.string "expression"
    t.string "identifier"
    t.boolean "active", default: true
    t.bigint "dictionary_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dictionary_id"], name: "index_patterns_on_dictionary_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.text "username", default: "", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "admin", default: false
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "patterns", "dictionaries"
end
