require 'fileutils'
require 'rubygems'
require 'zip'
require 'simstring'
using HashToResultHash

class Dictionary < ApplicationRecord
  include StringManipulator

  belongs_to :user
  has_many :associations
  has_many :associated_managers, through: :associations, source: :user
  has_many :entries, :dependent => :destroy
  has_many :patterns, :dependent => :destroy
  has_many :jobs, :dependent => :destroy
  has_many :tags, :dependent => :destroy

  validates :name, presence:true, uniqueness: true
  validates :user_id, presence: true
  validates :description, presence: true
  validates :license_url, url: {allow_blank: true}
  validates :name, length: {minimum: 3}
  validates_format_of :name,                              # because of to_param overriding.
                      :with => /\A[a-zA-Z_][a-zA-Z0-9_\- ()]*\z/,
                      :message => "should begin with an alphabet or underscore, and only contain alphanumeric letters, underscore, hyphen, space, or round brackets!"
  # validates :associated_annotation_project, length: { minimum: 5, maximum: 40 }
  # validates_format_of :associated_annotation_project, :with => /\A[a-z0-9\-_]+\z/i

  before_save :update_context_embedding, if: :context_changed?
  before_destroy :ensure_entries_empty, prepend: true

  DOWNLOADABLES_DIR = 'db/downloadables/'

  SIM_STRING_DB_DIR = "db/simstring/"

  # The terms which will never be included in terms
  NO_TERM_WORDS = %w(are am be was were do did does had has have what which when where who how if whether an the this that these those is it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought each every many much very more most than such several some both even and or but neither nor not never also much as well many e.g)

  # terms will never begin or end with these words, mostly prepositions
  NO_BEGIN_WORDS = %w(a am an and are as about above across after against along amid among around at been before behind below beneath beside besides between beyond by concerning considering despite do except excepting excluding for from had has have i in inside into if is it like my me of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during what which when where who how whether)

  NO_END_WORDS = %w(a am an and are as about above across after against along amid among around at been before behind below beneath beside besides between beyond by concerning considering despite do except excepting excluding for from had has have i in inside into if is it like my me of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during what which when where who how whether)

  def filename
    @filename ||= name.gsub(/\s+/, '_')
  end

  scope :mine, -> (user) {
    if user.nil?
      none
    else
      includes(:associations)
        .where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
        .references(:associations)
    end
  }

  scope :visible, -> (user) {
    if user.nil?
      where(public: true)
    elsif user.admin?
    else
      includes(:associations)
        .where('public = true OR dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
        .references(:associations)
    end
  }

  scope :editable, -> (user) {
    if user.nil?
      none
    elsif user.admin?
    else
      includes(:associations)
        .where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
        .references(:associations)
    end
  }

  scope :administrable, -> (user) {
    if user.nil?
      none
    elsif user.admin?
    else
      where('user_id = ?', user.id)
    end
  }

  scope :index_dictionaries, -> { where(public: true).order(created_at: :desc) }

  class << self
    def find_dictionaries_from_params(params)
      dic_names = if params.has_key?(:dictionaries)
                    params[:dictionaries]
                  elsif params.has_key?(:dictionary)
                    params[:dictionary]
                  elsif params.has_key?(:id)
                    params[:id]
                  end
      return [] unless dic_names.present?

      dictionaries = dic_names.split(/[,|]/).collect{|d| [d.strip, Dictionary.find_by(name: d.strip)]}
      unknown = dictionaries.select{|d| d[1].nil?}.collect{|d| d[0]}
      raise ArgumentError, "unknown dictionary: #{unknown.join(', ')}." unless unknown.empty?

      dictionaries.collect{|d| d[1]}
    end

    def find_dictionaries(dic_names)
      dic_names.collect do |dic_name|
        begin
          Dictionary.find_by!(name: dic_name)
        rescue => e
          raise ArgumentError, "unknown dictionary: #{dic_name}."
        end
      end
    end

    def find_ids_by_labels(labels, dictionaries = [], options = {})
      threshold = options[:threshold]
      superfluous = options[:superfluous]
      verbose = options[:verbose]
      use_ngram_similarity = options[:use_ngram_similarity]
      semantic_threshold = options[:semantic_threshold] # 'nil' indicates not to use semantic similarity
      tags = options[:tags]

      # search based on surface similarity
      sim_string_dbs = dictionaries.inject({}) do |h, dic|
        h[dic.name] = begin
          Simstring::Reader.new(dic.sim_string_db_path)
        rescue
          nil
        end
        if h[dic.name]
          h[dic.name].measure = Simstring::Jaccard
          h[dic.name].threshold = threshold || dic.threshold
        end
        h
      end

      search_method = superfluous ? Dictionary.method(:search_term_order) : Dictionary.method(:search_term_top)

      r = labels.inject({}) do |h, label|
        h[label] = search_method.call(dictionaries, sim_string_dbs, threshold, use_ngram_similarity, semantic_threshold, label, tags)
        h[label].map!{|entry| entry[:identifier]} unless verbose
        h
      end

      sim_string_dbs.each{|name, db| db.close if db}

      r
    end

    def find_labels_by_ids(ids, dictionaries = [])
      entries = if dictionaries.present?
        Entry.where(identifier: ids, dictionary_id: dictionaries)
      else
        Entry.where(identifier: ids)
      end

      entries.each_with_object({}) do |entry, h|
        h[entry.identifier] = [] unless h.has_key? entry.identifier
        h[entry.identifier] << {label: entry.label, dictionary: entry.dictionary.name}
      end
    end
  end

  # Override the original to_param so that it returns name, not ID, for constructing URLs.
  # Use Model#find_by_name() instead of Model.find() in controllers.
  def to_param
    name
  end

  def empty?
    entries_num == 0
  end

  def editable?(user)
    user && (user.admin? || user_id == user.id || associated_managers.include?(user))
  end

  def administrable?(user)
    user && (user.admin? || user_id == user.id)
  end

  def stable?
    (jobs.count == 0) || (jobs.count == 1 && jobs.first.finished?)
  end

  def uploadable?
    entries.empty?
  end

  def locked?
    jobs.size > 0 && jobs.first.running?
  end

  def use_tags?
    !tags.empty?
  end

  def embeddings_populated?
    entries.exists? && !entries.where(embedding: nil).exists?
  end

  def undo_entry(entry)
    if entry.is_white?
      entry.destroy
    elsif entry.is_black?
      transaction do
        entry.be_gray!
        update_entries_num
      end
    end
  end

  def confirm_entries(entry_ids)
    transaction do
      entries = Entry.where(id: entry_ids)
      entries.each{ |entry| entry.be_white! }
      update_entries_num
    end
  end

  def update_entries_num
    non_black_num = entries.where.not(mode: EntryMode::BLACK).count
    update(entries_num: non_black_num)
  end

  def num_gray = entries.gray.count

  def num_white = entries.white.count

  def num_black = entries.black.count

  def num_auto_expanded = entries.auto_expanded.count

  # turn a gray entry to white
  def turn_to_white(entry)
    raise "Only a gray entry can be turned to white" unless entry.mode == EntryMode::GRAY
    entry.be_white!
  end

  # turn a gray entry to black
  def turn_to_black(entry)
    raise "Only a gray entry can be turned to black" unless entry.mode == EntryMode::GRAY
    transaction do
      entry.be_black!
      update_entries_num
    end
  end

  # cancel a black entry to gray
  def cancel_black(entry)
    raise "Ony a black entry can be canceled to gray" unless entry.mode == EntryMode::BLACK
    transaction do
      entry.be_gray!
      update_entries_num
    end
  end

  def add_patterns(patterns)
    transaction do
      columns = [:expression, :identifier, :dictionary_id]
      r = Pattern.bulk_import columns, patterns.map{|p| p << id}, validate: false
      raise "Import error" unless r.failed_instances.empty?

      increment!(:patterns_num, patterns.length)
    end
  end

  def add_entries(raw_entries, norm1list, norm2list)
    # black_count = raw_entries.count{|e| e[2] == EntryMode::BLACK}

    transaction do
      tag_set = raw_entries.map{|(_, _, tags)| tags}.flatten.uniq
      new_tags = tag_set - tags.where(value: tag_set).pluck(:value)

      # import tags, entries, entry_tag associations
      import_tags!(new_tags) if new_tags.present?
      entries_result = import_entries!(raw_entries, norm1list, norm2list)
      import_entry_tags!(tag_set, entries_result, raw_entries)

      update_entries_num
    end
  end

  def new_entry(label, identifier)
    analyzer = Analyzer.new
    norm1 = normalize1(label, analyzer)
    norm2 = normalize2(label, analyzer)
    entries.build(label: label,
                  identifier: identifier,
                  norm1: norm1,
                  norm2: norm2,
                  label_length: label.length,
                  mode: EntryMode::WHITE,
                  dirty: true)
  rescue => e
    raise ArgumentError, "The entry, [#{label}, #{identifier}], is rejected: #{e.message} #{e.backtrace.join("\n")}."
  end

  def create_entry!(label, identifier, tag_ids = [])
    entry = new_entry(label, identifier)
    entry.tag_ids = tag_ids
    entry.save!

    entry
  end

  def empty_entries(mode = nil)
    transaction do
      case mode
      when nil
        # Use subquery to avoid loading all IDs into memory
        EntryTag.where("entry_id IN (SELECT id FROM entries WHERE dictionary_id = ?)", id).delete_all
        entries.delete_all
        update_entries_num
        clean_sim_string_db
      when EntryMode::GRAY
        # Use ActiveRecord method for security and consistency
        entries.gray.delete_all
        update_entries_num
      when EntryMode::WHITE
        # Use delete_all for bulk deletion without callbacks
        entries.white.delete_all
        update_entries_num
      when EntryMode::BLACK
        # Use single UPDATE instead of iterating through each entry
        entries.black.update_all(mode: EntryMode::GRAY)
        update_entries_num
      when EntryMode::AUTO_EXPANDED
        # Use delete_all for bulk deletion without callbacks
        entries.auto_expanded.delete_all
        update_entries_num
      else
        raise ArgumentError, "Unexpected mode: #{mode}"
      end
    end
  end

  def clear_tags
    tags.destroy_all
  end

  def new_pattern(expression, identifier)
    Pattern.new(expression:expression, identifier:identifier, dictionary_id: self.id)
    rescue => e
      raise ArgumentError, "The pattern, [#{expression}, #{identifier}], is rejected: #{e.message} #{e.backtrace.join("\n")}."
  end

  def empty_patterns
    transaction do
      patterns.delete_all
      update_attribute(:patterns_num, 0)
    end
  end

  def sim_string_db_path
    Rails.root.join(sim_string_db_dir, "simstring.db").to_s
  end

  def tmp_sim_string_db_path
    Rails.root.join(sim_string_db_dir, "tmp_entries.db").to_s
  end

  def sim_string_db_exist?
    File.exist?(sim_string_db_path)
  end

  def additional_entries_exists?
    @additional_entries_exists
  end

  def additional_entries_existency_update
    @additional_entries_exists = entries.additional_entries.exists?
  end

  def tags_exists?
    @tag_exists
  end

  def tags_existency_update
    @tag_exists = use_tags?
  end

  def compilable?
    entries.exists? && (entries.where(dirty:true).exists? || !sim_string_db_exist?)
  end

  def compile!
    # Update sim string db to remove black entries and to add (dirty) white entries.
    # which is sufficient to speed up the search
    update_sim_string_db

    # commented: do NOT delete black entries
    # Entry.delete(Entry.where(dictionary_id: self.id, mode:EntryMode::BLACK).pluck(:id))

    # commented: do NOT change white entries to gray ones
    # entries.where(mode:EntryMode::WHITE).update_all(mode: EntryMode::GRAY)

    update_stop_words
  end

  def update_stop_words
    mlabels = entries.pluck(:label).map{|l| l.downcase.split}
    count_no_term_words = mlabels.map{|ml| ml & NO_TERM_WORDS}.select{|i| i.present?}.reduce([], :+).uniq
    count_no_begin_words = mlabels.map{|ml| ml[0, 1] & NO_BEGIN_WORDS}.select{|i| i.present?}.reduce([], :+).uniq
    count_no_end_words = mlabels.map{|ml| ml[-1, 1] & NO_END_WORDS}.select{|i| i.present?}.reduce([], :+).uniq
    self.no_term_words = NO_TERM_WORDS - count_no_term_words
    self.no_begin_words = NO_BEGIN_WORDS - count_no_begin_words
    self.no_end_words = NO_END_WORDS - count_no_end_words
    self.save!
  end

  def simstring_method
    @simstring_method ||= case language
    when 'kor'
      Simstring::Cosine
    when 'jpn'
      Simstring::Cosine
    else
      Simstring::Jaccard
    end
  end

  def self.search_term_order(dictionaries, ssdbs, threshold, ngram, semantic_threshold, term, tags, norm1 = nil, norm2 = nil)
    return [] if term.empty?

    entries = dictionaries.inject([]) do |sum, dic|
      sum + dic.search_term(ssdbs[dic.name], term, norm1, norm2, tags, threshold, ngram, semantic_threshold)
    end

    entries.sort_by{|e| e[:score]}.reverse
  end

  def self.search_term_top(dictionaries, ssdbs, threshold, ngram, semantic_threshold, term, tags, norm1 = nil, norm2 = nil)
    return [] if term.empty?

    entries = dictionaries.inject([]) do |sum, dic|
      sum + dic.search_term(ssdbs[dic.name], term, norm1, norm2, tags, threshold, ngram, semantic_threshold)
    end

    return [] if entries.empty?

    max_score = entries.max{|a, b| a[:score] <=> b[:score]}[:score]
    entries.delete_if{|e| e[:score] < max_score}
  end

  def self.search_term_semantic(dictionaries, term, sem_threshold, tags)
    return [] if term.empty?

    entries = dictionaries.inject([]) do |sum, dic|
      sum + dic.search_term_semantic(term, sem_threshold, tags)
    end

    entries.sort_by{|e| e[:score]}.reverse
  end

  def search_term_semantic(term, threshold, tags)
    return [] if term.empty?


    embedding = EmbeddingServer.fetch_embedding(term)
    return [] unless embedding.present?

    # Convert embedding to safe pg_vector format
    embedding_vector = "[#{embedding.map(&:to_f).join(',')}]"

    distance_threshold = 1.0 - threshold

    query = build_semantic_query(embedding_vector, distance_threshold, tags)

    # Execute and transform results in one pass
    query.map do |result|
      {
        label: result['label'],
        identifier: result['identifier'],
        score: 1.0 - result['distance'].to_f,  # Convert distance back to similarity
        dictionary: name,
        search_type: 'Semantic'
      }
    end
  end

  def build_semantic_query(embedding_vector, distance_threshold, tags)
    sql = <<~SQL
      SELECT
        e.id,
        e.label,
        e.identifier,
        e.embedding,
        e.embedding <=> $1 AS distance
      FROM entries e
      WHERE e.dictionary_id = $2
        AND e.embedding <=> $1 <= $3
    SQL

    params = [embedding_vector, id, distance_threshold]
    param_count = 3

    # Add tag filtering if present
    if tags.present?
      tag_placeholders = tags.map { |_| "$#{param_count += 1}" }.join(',')
      sql += <<~SQL
        AND EXISTS (
          SELECT 1 FROM entry_tags et
          JOIN tags t ON t.id = et.tag_id
          WHERE et.entry_id = e.id
            AND t.value IN (#{tag_placeholders})
        )
      SQL
      params.concat(tags)
    end

    sql += <<~SQL
      ORDER BY e.embedding <=> $1
      LIMIT 5
    SQL

    ActiveRecord::Base.connection.exec_query(sql, "semantic_search", params)
  end

  def search_term(ssdb, term, norm1, norm2, tags, threshold, ngram, semantic_threshold)
    return [] if term.empty? || entries_num == 0

    threshold ||= self.threshold

    # It needs for a proper sensitivity over additional entities
    # results = additional_entries tags

    if threshold < 1
      norm1 ||= normalize1(term)
      norm2 ||= normalize2(term)
      norm2s = ssdb.retrieve(norm2) if ngram && ssdb.present?
      norm2s = [norm2] unless norm2s.present?

      results = []

      if additional_entries_exists?
        additional_results = norm2s.flat_map { |n2| additional_entries_for_norm2(n2, tags) }
        results.concat(additional_results)
      end

      entry_results = self.entries
                       .left_outer_joins(:tags)
                       .without_black
                       .where(norm2: norm2s)

      entry_results = entry_results.where(tags: { value: tags }) if tags.present?
      results.concat(entry_results)

      hash_method = tags_exists? ? :to_result_hash_with_tags : :to_result_hash
      results = results.map(&hash_method)
                      .uniq
                      .map { |e|
                        e.merge!(score: str_sim.call(term, e[:label], norm1, e[:norm1], norm2, e[:norm2]), dictionary: name)
                        e[:score] >= threshold ? e :nil
                      }
                      .compact
    else
      entry_results = self.entries
                         .left_outer_joins(:tags)
                         .without_black
                         .where(label: term)

      entry_results = entry_results.where(tags: { value: tags }) if tags.present?
      results.concat(entry_results.map(&:to_result_hash))
      results.each{|e| e.merge!(score: 1, dictionary: name)}
    end

    # Add semantic search results
    if semantic_threshold.present? && semantic_threshold > 0
      semantic_results = search_term_semantic(term, semantic_threshold, tags)
      results.concat(semantic_results)
      results.uniq! { |r| r[:identifier] } # Remove duplicates by identifier
    end

    results
  end

  def sim_string_db_dir
    Dictionary::SIM_STRING_DB_DIR + self.name
  end

  def update_db_location(db_loc_old)
    db_loc_new = self.sim_string_db_dir
    if Dir.exist?(db_loc_old)
      FileUtils.mv db_loc_old, db_loc_new unless db_loc_new == db_loc_old
    else
      FileUtils.mkdir_p(db_loc_new)
    end
  end

  def downloadable_zip_path
    @downloadable_path ||= DOWNLOADABLES_DIR + filename + '.zip'
  end

  def large?
    entries_num > 10000
  end

  def creating_downloadable?
    jobs.any?{|job| job.name == 'Create downloadable'}
  end

  def downloadable_updatable?
    if File.exist?(downloadable_zip_path)
      updated_at > File.mtime(downloadable_zip_path)
    else
      true
    end
  end

  def create_downloadable!
    FileUtils.mkdir_p(DOWNLOADABLES_DIR) unless Dir.exist?(DOWNLOADABLES_DIR)

    buffer = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry(self.name + '.csv')
      out.write entries.as_tsv
    end

    File.open(downloadable_zip_path, 'wb') do |f|
      f.write(buffer.string)
    end
  end

  def save_tags(tag_list)
    tag_list.each do |tag|
      self.tags.create!(value: tag)
    end
  end

  def update_tags(tag_list)
    current_tags = self.tags.to_a

    tags_to_add = tag_list.reject { |tag_value| current_tags.any? { |t| t.value == tag_value } }
    tags_to_remove = current_tags.reject { |tag| tag_list.include?(tag.value) }

    tags_to_add.each do |tag|
      self.tags.create!(value: tag)
    end

    tags_in_use = []
    tags_to_remove.each do |tag|
      if tag.used_in_entries?
        tags_in_use << tag.value
      else
        tag.destroy
      end
    end

    if tags_in_use.any?
      errors.add(:base, "The following tags #{tags_in_use.to_sentence} #{tags_in_use.length > 1 ? 'are' : 'is'} used. Please edit the entry before deleting.")
      return false
    end

    true
  end

  def expand_synonym
    start_time = Time.current
    batch_size = 1000
    processed_identifiers = Set.new

    identifiers_count =  entries.active.select(:identifier).distinct.count
    batch_count = identifiers_count / batch_size

    0.upto(batch_count) do |i|
      current_batch = entries.active
                              .select(:identifier)
                              .distinct
                              .order(:identifier)
                              .simple_paginate(i + 1, batch_size)
                              .pluck(:identifier)
      break if current_batch.empty?

      new_identifiers = current_batch.reject { |identifier| processed_identifiers.include?(identifier) }
      new_identifiers.each do |identifier|
        synonyms = entries.active
                          .where(identifier: identifier)
                          .where("created_at < ?", start_time)
                          .pluck(:label)
        expanded_synonyms = synonym_expansion(synonyms)
        append_expanded_synonym_entries(identifier, expanded_synonyms)
        processed_identifiers.add(identifier)
      end
    end
  end

  def synonym_expansion(synonyms)
    synonyms.map.with_index do |label, i|
      expanded_label = "#{label}--dummy-synonym-#{i + 1}"
      score = rand
      { label: expanded_label, score: }
    end
  end

  def normalizer1
    @normalizer1 ||= 'normalizer1' + language_suffix
  end

  def normalizer2
    @normalizer2 ||= 'normalizer2' + language_suffix
  end

  private

  def ngram_order
    case language
    when 'kor'
      2
    when 'jpn'
      1
    else
      3
    end
  end

  def clean_sim_string_db
    FileUtils.rm_rf Dir.glob("#{sim_string_db_dir}/*")
  end

  def update_sim_string_db
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    clean_sim_string_db

    db = Simstring::Writer.new sim_string_db_path, ngram_order, false, true

    entries
      .active
      .pluck(:norm2)
      .uniq
      .compact # to avoid error
      .each{|norm2| db.insert norm2}

    db.close

    entries.white.update_all(dirty: false)
  end

  def update_tmp_sim_string_db
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    db = Simstring::Writer.new tmp_sim_string_db_path, 3, false, true
    self.entries.where(mode: [EntryMode::GRAY, EntryMode::WHITE]).pluck(:norm2).uniq.each{|norm2| db.insert norm2}
    db.close
  end

  # Get typographic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def normalize1(text, analyzer = Analyzer.new)
    analyzer.normalize(text, normalizer1)
  end

  def self.normalize1(text, analyzer = Analyzer.new)
    analyzer.normalize(text, 'normalizer1')
  end

  # Get typographic and morphosyntactic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def normalize2(text, analyzer = Analyzer.new)
    analyzer.normalize(text, normalizer2)
  end

  def language_suffix
    @language_suffix ||= if language.present?
      case language
      when 'kor'
        '_ko'
      when 'jpn'
        '_ja'
      else
        ''
      end
    else
      ''
    end
  end

  def str_sim
    @str_sim ||= case language
    when 'kor'
      Entry.method(:str_sim_jaccard_2gram)
    when 'jpn'
      Entry.method(:str_sim_jp)
    else
      Entry.method(:str_sim_jaccard_3gram)
    end
  end

  def append_expanded_synonym_entries(identifier, expanded_synonyms)
    transaction do
      expanded_synonyms.each do |expanded_synonym|
        entries.create!(
          label: expanded_synonym[:label],
          identifier: identifier,
          score: expanded_synonym[:score],
          mode: EntryMode::AUTO_EXPANDED
        )
      end
    end
  end

  def maintainer
    self.user.username
  end

  def additional_entries(tags)
    self.entries
        .left_outer_joins(:tags)
        .additional_entries
        .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
        .map(&:to_result_hash)
  end

  def additional_entries_for_norm2(norm2, tags)
    self.entries
        .left_outer_joins(:tags)
        .additional_entries
        .where(norm2: norm2)
        .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
  end

  def additional_entries_for_label(label, tags)
    self.entries
        .left_outer_joins(:tags)
        .additional_entries
        .where(label: label)
        .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
        .map(&:to_result_hash)
  end

  def import_tags!(new_tags)
    columns = [:value, :dictionary_id]
    values = new_tags.map{|tag| [tag, self.id]}
    result = Tag.bulk_import columns, values, validate: false
    raise "Error during import of tags" unless result.failed_instances.empty?
  end

  def import_entries!(raw_entries, norm1list, norm2list)
    entries = raw_entries.map.with_index do |(label, identifier, _), i|
      [label, identifier, norm1list[i], norm2list[i], label.length, EntryMode::GRAY, false, self.id]
    end

    columns = [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id]
    values = entries
    result = Entry.bulk_import columns, values, validate: false
    raise "Error during import of entries" unless result.failed_instances.empty?

    result
  end

  def import_entry_tags!(tag_set, entries_result, raw_entries)
    tag_map = tags.where(value: tag_set).pluck(:value, :id).to_h
    entry_tags = raw_entries.map.with_index do |(_, _, tags), i|
      tags.map{|tag| [entries_result.ids[i], tag_map[tag]]}
    end

    columns = [:entry_id, :tag_id]
    values = entry_tags.flatten(1)
    result = EntryTag.bulk_import columns, values, validate: false
    raise "Error during import of entry_tags" unless result.failed_instances.empty?
  end

  def update_context_embedding
    return if context.blank?

    embedding = EmbeddingServer.fetch_embedding(context)
    return unless embedding.present?

    self.context_embedding = "[#{embedding.map(&:to_f).join(',')}]"
  end

  def ensure_entries_empty
    if entries.exists?
      errors.add(:base, "Cannot destroy dictionary with entries. " \
                        "Please empty all entries first using empty_entries(nil). " \
                        "Current entries count: #{entries_num}")
      throw :abort
    end
  end
end
