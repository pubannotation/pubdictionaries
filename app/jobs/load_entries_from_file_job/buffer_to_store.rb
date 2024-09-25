class LoadEntriesFromFileJob::BufferToStore
  BUFFER_SIZE = 10000

  def initialize(dictionary)
    @dictionary = dictionary

    @entries = []
    @patterns = []

    @analyzer = BatchAnalyzer.new

    @num_skipped_entries = 0
    @num_skipped_patterns = 0
  end

  def add_entry(label, identifier, tags)
    # case mode
    # when EntryMode::PATTERN
    #   buffer_pattern(label, identifier)
    # else
    #   buffer_entry(label, identifier, mode)
    # end
    buffer_entry(label, identifier, tags)
  end

  def finalize
    flush_entries unless @entries.empty?
    flush_patterns unless @patterns.empty?
    @analyzer&.shutdown
  end

  def result
    [@num_skipped_entries, @num_skipped_patterns]
  end

  private

  def buffer_entry(label, identifier, tags)
    @entries << [label, identifier, tags]
    flush_entries if @entries.length >= BUFFER_SIZE
  end

  def buffer_pattern(expression, identifier)
    matched = patterns_any? && @dictionary.patterns.where(expression:expression, identifier:identifier)&.first
    if matched
      @num_skipped_patterns += 1
    else
      @patterns << [expression, identifier]
    end
    flush_patterns if @patterns.length >= BUFFER_SIZE
  end

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

  def flush_patterns
    @dictionary.add_patterns(@patterns)
    @patterns.clear
  end

  # It is supposed to memorize whether the patterns of the dictionary are empty when the class is initialized.
  def patterns_any?
    @patterns_any_p ||= !@dictionary.patterns.empty?
  end
end
