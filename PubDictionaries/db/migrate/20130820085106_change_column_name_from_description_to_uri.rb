class ChangeColumnNameFromDescriptionToUri < ActiveRecord::Migration
  def up
  	change_table :entries do |t|
  	  t.rename :description, :uri
  	end
  end

  def down
  	change_table :entries do |t|
  	  t.rename :uri, :description
  	end
  end
end
