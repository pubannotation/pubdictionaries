# encoding: UTF-8
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
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20131010084348) do

  create_table "dictionaries", :force => true do |t|
    t.string   "title"
    t.string   "creator"
    t.text     "description"
    t.datetime "created_at",      :null => false
    t.datetime "updated_at",      :null => false
    t.boolean  "lowercased"
    t.boolean  "stemmed"
    t.boolean  "hyphen_replaced"
    t.integer  "user_id"
  end

  create_table "entries", :force => true do |t|
    t.string   "view_title"
    t.text     "uri"
    t.integer  "dictionary_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
    t.string   "label"
    t.string   "search_title"
  end

  add_index "entries", ["search_title"], :name => "index_entries_on_search_title"

  create_table "new_entries", :force => true do |t|
    t.string   "view_title"
    t.string   "label"
    t.string   "uri"
    t.integer  "user_dictionary_id"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
    t.string   "search_title"
  end

  add_index "new_entries", ["search_title"], :name => "index_new_entries_on_search_title"

  create_table "removed_entries", :force => true do |t|
    t.integer  "user_dictionary_id"
    t.integer  "entry_id"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
  end

  create_table "user_dictionaries", :force => true do |t|
    t.integer  "user_id"
    t.integer  "dictionary_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
  end

  create_table "users", :force => true do |t|
    t.string   "email",                  :default => "", :null => false
    t.string   "encrypted_password",     :default => "", :null => false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          :default => 0
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.datetime "created_at",                             :null => false
    t.datetime "updated_at",                             :null => false
  end

  add_index "users", ["email"], :name => "index_users_on_email", :unique => true
  add_index "users", ["reset_password_token"], :name => "index_users_on_reset_password_token", :unique => true

end
