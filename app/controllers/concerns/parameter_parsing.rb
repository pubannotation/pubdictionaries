module ParameterParsing
  extend ActiveSupport::Concern

  private

  def to_boolean(value)
    value == 'true' || value == '1'
  end

  def to_integer(value)
    return nil if value.blank?
    begin
      Integer(value)
    rescue ArgumentError
      nil
    end
  end

  def to_float(value)
    return nil if value.blank?
    begin
      Float(value)
    rescue ArgumentError
      nil
    end
  end

  def to_array(value)
    value&.split(/[\n\t\r|,]+/)&.map(&:strip) || []
  end

  def parse_dictionaries!(permitted)
    permitted[:dictionaries] ||= permitted[:dictionary]
    permitted.delete(:dictionary)
    permitted[:dictionaries] = to_array(permitted[:dictionaries])
  end

  def parse_labels!(permitted)
    permitted[:labels] ||= permitted[:label]
    permitted.delete(:label)
    permitted[:labels] = to_array(permitted[:labels])
  end

  def parse_labels_in_csv!(permitted)
    permitted[:labels] ||= permitted[:label]
    permitted.delete(:label)
    permitted[:labels] = permitted[:labels]&.parse_csv || []
  end

  def parse_identifiers!(permitted)
    permitted[:identifiers] ||= permitted[:identifier]
    permitted.delete(:identifier)
    permitted[:identifiers] = to_array(permitted[:identifiers])
  end


end
