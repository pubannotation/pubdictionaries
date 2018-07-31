class AddLicenseToDictionary < ActiveRecord::Migration
  def change
    add_column :dictionaries, :license, :string
    add_column :dictionaries, :license_url, :string
  end
end
