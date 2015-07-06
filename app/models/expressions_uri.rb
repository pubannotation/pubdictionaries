require 'elasticsearch/model'

class ExpressionsUri < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  attr_accessible :expression_id, :uri_id

  belongs_to :dictionary
  belongs_to :expression
  belongs_to :uri

  validates_uniqueness_of :expression_id, scope: [:uri_id, :dictionary_id]
  validates :expression_id, presence: true
  validates :uri_id, presence: true
  validates :dictionary_id, presence: true


  after_save :increment_dictionaries_count
  after_destroy :decrement_dictionaries_count

  def increment_dictionaries_count
    Expression.increment_counter(:dictionaries_count, expression_id)
    Uri.increment_counter(:dictionaries_count, uri_id)
  end

  def decrement_dictionaries_count
    Expression.decrement_counter(:dictionaries_count, expression_id)
    Uri.decrement_counter(:dictionaries_count, uri_id)
  end
end
