class DropLengthFields < ActiveRecord::Migration
  def up
    change_table :entries do |t|
  		t.remove :norm1_length, :norm2_length
    end
  end

  def down
    change_table :entries do |t|
      t.integer :norm1_length
      t.integer :norm2_length
    end
  end
end
