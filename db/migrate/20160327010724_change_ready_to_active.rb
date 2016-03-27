class ChangeReadyToActive < ActiveRecord::Migration
  def change
  	change_table :dictionaries do |t|
  		t.rename :ready, :active
  	end
  end
end
