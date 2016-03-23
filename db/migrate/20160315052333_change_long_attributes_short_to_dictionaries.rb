class ChangeLongAttributesShortToDictionaries < ActiveRecord::Migration
  def change
  	change_table :dictionaries do |t|
  		t.rename :created_by_delayed_job, :uploaded
  		t.rename :confirmed_error_messages, :confirmed
  		t.rename :error_messages, :issues
  	end
  end
end
