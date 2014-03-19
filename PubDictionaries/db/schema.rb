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

ActiveRecord::Schema.define(:version => 20140319055143) do

  create_table "delayed_jobs", :force => true do |t|
    t.integer  "priority",   :default => 0, :null => false
    t.integer  "attempts",   :default => 0, :null => false
    t.text     "handler",                   :null => false
    t.text     "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by"
    t.string   "queue"
    t.datetime "created_at",                :null => false
    t.datetime "updated_at",                :null => false
  end

  add_index "delayed_jobs", ["priority", "run_at"], :name => "delayed_jobs_priority"

  create_table "dictionaries", :force => true do |t|
    t.string   "title"
    t.string   "creator"
    t.text     "description"
    t.datetime "created_at",                        :null => false
    t.datetime "updated_at",                        :null => false
    t.boolean  "lowercased"
    t.boolean  "stemmed"
    t.boolean  "hyphen_replaced"
    t.integer  "user_id"
    t.boolean  "public",          :default => true
  end

  add_index "dictionaries", ["creator"], :name => "index_dictionaries_on_creator"
  add_index "dictionaries", ["title"], :name => "index_dictionaries_on_title"

  create_table "entries", :force => true do |t|
    t.string   "view_title"
    t.string   "uri"
    t.integer  "dictionary_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
    t.string   "label"
    t.string   "search_title"
  end

  add_index "entries", ["dictionary_id"], :name => "index_entries_on_dictionary_id"
  add_index "entries", ["label"], :name => "index_entries_on_label"
  add_index "entries", ["search_title"], :name => "index_entries_on_search_title"
  add_index "entries", ["uri"], :name => "index_entries_on_uri"
  add_index "entries", ["view_title"], :name => "index_entries_on_view_title"
  add_index "entries", ["view_title"], :name => "index_entries_title"

  create_table "new_entries", :force => true do |t|
    t.string   "view_title"
    t.string   "label"
    t.string   "uri"
    t.integer  "user_dictionary_id"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
    t.string   "search_title"
  end

  add_index "new_entries", ["label"], :name => "index_new_entries_on_label"
  add_index "new_entries", ["search_title"], :name => "index_new_entries_on_search_title"
  add_index "new_entries", ["search_title"], :name => "index_new_entries_search_title"
  add_index "new_entries", ["uri"], :name => "index_new_entries_on_uri"
  add_index "new_entries", ["user_dictionary_id"], :name => "index_new_entries_on_user_dictionary_id"
  add_index "new_entries", ["view_title"], :name => "index_new_entries_on_view_title"

  create_table "removed_entries", :force => true do |t|
    t.integer  "user_dictionary_id"
    t.integer  "entry_id"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
  end

  add_index "removed_entries", ["entry_id"], :name => "index_removed_entries_on_entry_id"
  add_index "removed_entries", ["user_dictionary_id"], :name => "index_removed_entries_on_user_dictionary_id"

  create_table "test_trgm", :id => false, :force => true do |t|
    t.text "t"
  end

  create_table "user_dictionaries", :force => true do |t|
    t.integer  "user_id"
    t.integer  "dictionary_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
  end

  add_index "user_dictionaries", ["dictionary_id"], :name => "index_user_dictionaries_on_dictionary_id"
  add_index "user_dictionaries", ["user_id"], :name => "index_user_dictionaries_on_user_id"

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
    t.string   "authentication_token"
  end

  add_index "users", ["authentication_token"], :name => "index_users_on_authentication_token", :unique => true
  add_index "users", ["email"], :name => "index_users_on_email", :unique => true
  add_index "users", ["reset_password_token"], :name => "index_users_on_reset_password_token", :unique => true

end
