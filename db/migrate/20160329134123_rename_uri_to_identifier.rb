class RenameUriToIdentifier < ActiveRecord::Migration
  def change
    rename_table :uris, :identifiers
  	change_table :entries do |t|
  		t.rename :uri_id, :identifier_id
  	end
  end
end
