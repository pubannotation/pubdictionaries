class Tag < ApplicationRecord
  belongs_to :dictionary
  has_many :entry_tags
  has_many :entries, through: :entry_tags

  validates :value, length: {minimum: 3}, uniqueness: { scope: :dictionary_id }
  validates_format_of :value, # because of to_param overriding.
                      :with => /\A[a-zA-Z_][a-zA-Z0-9_\- ()]*\z/,
                      :message => "should begin with an alphabet or underscore, and only contain alphanumeric letters, underscore, hyphen, space, or round brackets!"
end
