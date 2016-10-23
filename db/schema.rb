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

ActiveRecord::Schema.define(:version => 20161022113556) do

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
    t.string   "name"
    t.text     "description"
    t.integer  "user_id"
    t.string   "language"
    t.boolean  "active",      :default => true
    t.datetime "created_at",                    :null => false
    t.datetime "updated_at",                    :null => false
    t.integer  "entries_num", :default => 0
  end

  create_table "entries", :force => true do |t|
    t.string   "label"
    t.string   "norm1"
    t.string   "norm2"
    t.integer  "label_length"
    t.string   "identifier"
    t.boolean  "flag",             :default => false
    t.datetime "created_at",                          :null => false
    t.datetime "updated_at",                          :null => false
    t.integer  "dictionaries_num", :default => 0
  end

  add_index "entries", ["flag"], :name => "index_entries_on_flag"
  add_index "entries", ["identifier"], :name => "index_entries_on_identifier"
  add_index "entries", ["label"], :name => "index_entries_on_label"
  add_index "entries", ["label_length"], :name => "index_entries_on_label_length"

  create_table "jobs", :force => true do |t|
    t.string   "name"
    t.integer  "dictionary_id"
    t.integer  "delayed_job_id"
    t.text     "message"
    t.integer  "num_items"
    t.integer  "num_dones"
    t.datetime "begun_at"
    t.datetime "ended_at"
    t.datetime "registered_at"
  end

  add_index "jobs", ["delayed_job_id"], :name => "index_jobs_on_delayed_job_id"
  add_index "jobs", ["dictionary_id"], :name => "index_jobs_on_dictionary_id"

  create_table "memberships", :force => true do |t|
    t.integer  "dictionary_id"
    t.integer  "entry_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
  end

  add_index "memberships", ["dictionary_id"], :name => "index_memberships_on_dictionary_id"
  add_index "memberships", ["entry_id"], :name => "index_memberships_on_entry_id"

  create_table "users", :force => true do |t|
    t.text     "username",               :default => "", :null => false
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
  add_index "users", ["username"], :name => "index_users_on_username", :unique => true

end
