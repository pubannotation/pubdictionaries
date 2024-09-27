class LoadEntriesFromFileJob::BufferToStore
  BUFFER_SIZE = 10000

  def initialize(dictionary)
    @entries = []
    @analyzer = BatchAnalyzer.new(dictionary)
  end

  def add_entry(label, identifier, tags)
    @entries << [label, identifier, tags]
    flush_entries if @entries.length >= BUFFER_SIZE
  end

  def flush
    flush_entries unless @entries.empty?
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
