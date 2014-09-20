class AddErrorMsgViewFieldsToDictionaries < ActiveRecord::Migration
  def change
    add_column :dictionaries, :created_by_delayed_job, :boolean, :default => false
    add_column :dictionaries, :confirmed_error_messages, :boolean, :default => false
    add_column :dictionaries, :error_messages, :text, :default => ""
  end
end
