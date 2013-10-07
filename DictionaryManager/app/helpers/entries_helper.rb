module EntriesHelper

  # Check if an entry is marked as moved or not.
  def removed?(entry)
    if @user_dictionary.nil?
      return false
  	end

  	removed_entry = @user_dictionary.removed_entries.where(entry_id: entry.id).first
	  if not removed_entry.nil?
    	return true
	  else
	    return false
  	end
  end  
end
