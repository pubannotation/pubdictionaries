module DictionariesHelper
  def is_nil_or_empty?(value)
  	if value.nil? or value == ""
  	  return true
  	else
  	  return false
  	end
  end

  # Check if an entry is marked as disabled or not.
  def disabled?(user_dictionary, entry)
  	# Rails.logger.debug entry.inspect
  	if user_dictionary
	  disabled_entries = user_dictionary.removed_entries
      if disabled_entries and disabled_entries.where(entry_id: entry.id).first 
        return true
      end
    end
    return false
  end

end
