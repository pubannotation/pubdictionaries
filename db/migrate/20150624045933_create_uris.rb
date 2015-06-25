class CreateUris < ActiveRecord::Migration
  def change
    create_table :uris do |t|
      t.string :resource, unique: true

      t.timestamps
    end
  end
end
