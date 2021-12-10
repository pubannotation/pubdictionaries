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

	def toggle!
		update_attribute(:active, !active)
	end
end
