class AddTermsLengthToLabels < ActiveRecord::Migration
  def change
  	change_table :labels do |t|
  		t.string :terms
  		t.integer :terms_length
  	end
  end
end
