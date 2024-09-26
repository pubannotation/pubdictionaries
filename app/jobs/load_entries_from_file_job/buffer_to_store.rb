class LoadEntriesFromFileJob::BufferToStore
  BUFFER_SIZE = 10000

  def initialize(dictionary)
    @dictionary = dictionary
    @entries = []
    @analyzer = BatchAnalyzer.new
  end

  def add_entry(label, identifier, tags)
    @entries << [label, identifier, tags]
    flush_entries if @entries.length >= BUFFER_SIZE
  end

  def finalize
    flush_entries unless @entries.empty?
    @analyzer.shutdown
  end

  private

  def flush_entries
    labels = @entries.map(&:first)
    norm1list, norm2list = @analyzer.normalize(labels,
                                               @dictionary.normalizer1,
                                               @dictionary.normalizer2)
    @dictionary.add_entries(@entries, norm1list, norm2list)
    @entries.clear
  rescue => e
    raise ArgumentError, "Entries are rejected: #{e.message} #{e.backtrace.join("\n")}."
  end
end
