class AddParamsToDictionary < ActiveRecord::Migration[5.2]
  def change
		add_column :dictionaries, :no_term_words, :text, array:true, default: []
		add_column :dictionaries, :no_begin_words, :text, array:true, default: []
		add_column :dictionaries, :no_end_words, :text, array:true, default: []
		add_column :dictionaries, :tokens_len_min, :integer, default: 1
		add_column :dictionaries, :tokens_len_max, :integer, default: 6
		add_column :dictionaries, :threshold, :float, default: 0.85
  end
end
