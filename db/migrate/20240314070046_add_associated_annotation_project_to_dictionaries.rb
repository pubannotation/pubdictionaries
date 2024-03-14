class AddAssociatedAnnotationProjectToDictionaries < ActiveRecord::Migration[7.0]
  def change
    add_column :dictionaries, :associated_annotation_project, :string
  end
end
