class Pattern < ApplicationRecord
	belongs_to :dictionary

	scope :simple_paginate, -> (page = 1, per = 15) {
		offset = (page - 1) * per
		offset(offset).limit(per)
	}

	scope :active, -> {where(active: true)}

	def to_s
		"('#{expression}', '#{identifier}')"
	end

	def self.as_tsv
		CSV.generate(col_sep: "\t") do |tsv|
			tsv << ['#label', :id]
			all.each do |pattern|
				tsv << [pattern.expression, pattern.identifier]
			end
		end
	end

	def toggle!
		update_attribute(:active, !active)
	end
end
