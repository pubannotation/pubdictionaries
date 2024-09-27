class LoadEntriesFromFileJob::FloodGate
  CAPACITY = 10000

  def initialize(dictionary)
    @entries = []
    @analyzer = BatchAnalyzer.new(dictionary)
  end

  def add_entry(label, identifier, tags)
    @entries << [label, identifier, tags]

    if @entries.length >= CAPACITY
      flush_entries
       true
    else
      false
    end
  end

  def flush
    entries_count = @entries.size
    flush_entries unless @entries.empty?

    entries_count
  end

  def close
    @analyzer.shutdown
  end

  private

  def flush_entries
    @analyzer.add_entries(@entries)
    @entries.clear
  rescue => e
    raise ArgumentError, "Entries are rejected: #{e.message} #{e.backtrace.join("\n")}."
  end
end
