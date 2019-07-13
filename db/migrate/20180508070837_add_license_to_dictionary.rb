class AddLicenseToDictionary < ActiveRecord::Migration[5.2]
  def change
    add_column :dictionaries, :license, :string
    add_column :dictionaries, :license_url, :string
  end
end
