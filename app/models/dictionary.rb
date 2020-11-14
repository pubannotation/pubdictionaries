require 'simstring'

class Dictionary < ApplicationRecord
	include StringManipulator

	belongs_to :user
	has_many :associations
	has_many :associated_managers, through: :associations, source: :user
	has_many :entries, :dependent => :destroy
	has_many :jobs, :dependent => :destroy

	validates :name, presence:true, uniqueness: true
	validates :user_id, presence: true 
	validates :description, presence: true
	validates :license_url, url: {allow_blank: true}
	validates :name, length: {minimum: 3}
	validates_format_of :name,                              # because of to_param overriding.
											:with => /\A[a-zA-Z_][a-zA-Z0-9_\- ()]*\z/,
											:message => "should begin with an alphabet or underscore, and only contain alphanumeric letters, underscore, hyphen, space, or round brackets!"

	SIM_STRING_DB_DIR = "db/simstring/"

	# The terms which will never be included in terms
	NO_TERM_WORDS = %w(are am be was were do did does had has have what which when where who how if whether an the this that these those is it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought each every many much very more most than such several some both even and or but neither nor not never also much as well many e.g)

	# terms will never begin or end with these words, mostly prepositions
	NO_BEGIN_WORDS = %w(a am an and are as about above across after against along amid among around at been before behind below beneath beside besides between beyond by concerning considering despite do except excepting excluding for from had has have i in inside into if is it like my me of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during what which when where who how whether)

	NO_END_WORDS = %w(a am an and are as about above across after against along amid among around at been before behind below beneath beside besides between beyond by concerning considering despite do except excepting excluding for from had has have i in inside into if is it like my me of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during what which when where who how whether)


	scope :mine, -> (user) {
		if user.nil?
			none
		else
			includes(:associations)
				.where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
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

			dictionaries = dic_names.split(/[,|]/).collect{|d| [d.strip, Dictionary.find_by_name(d.strip)]}
			unknown = dictionaries.select{|d| d[1].nil?}.collect{|d| d[0]}
			raise ArgumentError, "unknown dictionary: #{unknown.join(', ')}." unless unknown.empty?

			dictionaries.collect{|d| d[1]}
		end

		def find_ids_by_labels(labels, dictionaries = [], threshold = nil, superfluous = false, verbose = false)
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
				h[label] = search_method.call(dictionaries, sim_string_dbs, threshold, label)
				h[label].map!{|entry| entry[:identifier]} unless verbose
				h
			end

			sim_string_dbs.each{|name, db| db.close if db}

			r
		end

		def find_labels_by_ids(ids, dictionaries = [], verbose = false)
			entries = if dictionaries.present?
				Entry.where(identifier: ids, dictionary_id: dictionaries)
			else
				Entry.where(identifier: ids)
			end

			entries.inject({}) do |h, entry|
				h[entry.identifier] = [] unless h.has_key? entry.identifier
				h[entry.identifier] << {label: entry.label, dictionary: entry.dictionary.name}
				h
			end
		end
	end

	# Override the original to_param so that it returns name, not ID, for constructing URLs.
	# Use Model#find_by_name() instead of Model.find() in controllers.
	def to_param
		name
	end

	def editable?(user)
		user && (user.admin? || user_id == user.id || associated_managers.include?(user))
	end

	def administrable?(user)
		user && (user.admin? || user_id == user.id)
	end

	def create_addition(label, id)
		increment!(:entries_num) if create_additional_entry(id, label)
		update_tmp_sim_string_db
	end

	def create_deletion(entry)
		entry.be_deletion!
		decrement!(:entries_num)
	end

	def undo_entry(entry)
		if entry.addition?
			entry.delete
			decrement!(:entries_num)
		elsif entry.deletion?
			entry.be_normal!
			increment!(:entries_num)
		end

		update_tmp_sim_string_db
	end

	def num_addition
		entries.where(mode:Entry::MODE_ADDITION).count
	end

	def num_deletion
		entries.where(mode:Entry::MODE_DELETION).count
	end

	def add_entries(pairs, normalizer = nil)
		transaction do
			new_entries = pairs.map {|label, identifier| new_entry_params(id, label, identifier, normalizer)}

			r = Entry.ar_import new_entries, validate: false
			raise "Import error" unless r.failed_instances.empty?

			increment!(:entries_num, new_entries.length)
		end
	end

	def new_entry_params(dictionary_id, label, id, normalizer)
		norm1 = normalize1(label, normalizer)
		norm2 = normalize2(label, normalizer)
		Entry.new(label: label, identifier: id, norm1: norm1, norm2: norm2, label_length: label.length, dictionary_id: dictionary_id)
	rescue => e
		raise ArgumentError, "The entry, [#{label}, #{id}], is rejected: #{e.message} #{e.backtrace.join("\n")}."
	end

	def empty_entries
		transaction do
			# Generate to one delete SQL statement for performance
			entries.delete_all
			update_attribute(:entries_num, 0)
		end
	end

	def sim_string_db_path
		Rails.root.join(sim_string_db_dir, "simstring.db").to_s
	end

	def tmp_sim_string_db_path
		Rails.root.join(sim_string_db_dir, "tmp_entries.db").to_s
	end

	def compilable?
		num_addition > 0 || num_deletion > 0
	end

	def compile
		FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)

		ngram_order = case language
		when 'kor'
			2
		when 'jpn'
			1
		else
			3
		end

		db = Simstring::Writer.new sim_string_db_path, ngram_order, false, true

		entries
			.where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION])
			.pluck(:norm2)
			.uniq
			.each{|norm2| db.insert norm2}

		# Generate to one delete SQL statement for performance
		Entry.delete(Entry.where(dictionary_id: self.id, mode:Entry::MODE_DELETION).pluck(:id))
		entries.where(mode:Entry::MODE_ADDITION).update_all(mode: Entry::MODE_NORMAL)
		db.close

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

	def narrow_entries_by_label(str, page = 0, per = nil)
		norm1 = normalize1(str)
		if per.nil?
			entries.where("norm1 LIKE ?", "%#{norm1}%").order(:label_length).page(page)
		else
			entries.where("norm1 LIKE ?", "%#{norm1}%").order(:label_length).page(page).per(per)
		end
	end

	def narrow_entries_by_label_prefix(str, page = 0, per = nil)
		norm1 = normalize1(str)
		if per.nil?
			entries.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page)
		else
			entries.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page).per(per)
		end
	end

	def narrow_entries_by_label_prefix_and_substring(str, page = 0, per = nil)
		norm1 = normalize1(str)
		if per.nil?
			entries.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page) +
			entries.where("norm1 LIKE ?", "_%#{norm1}%").order(:label_length).page(page)
		else
			entries.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page).per(per) +
			entries.where("norm1 LIKE ?", "_%#{norm1}%").order(:label_length).page(page).per(per)
		end
	end

	def narrow_entries_by_identifier(str, page = 0)
		entries.where("identifier ILIKE ?", "%#{str}%").page(page)
	end

	def self.narrow_entries_by_identifier(str, page = 0)
		Entry.where("identifier ILIKE ?", "%#{str}%").page(page)
	end

	def self.narrow_entries_by_label(str, page = 0)
		norm1 = normalize1(str)
		Entry.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page)
	end

	def self.narrow_entries_by_label_prefix(str, page = 0)
		norm1 = normalize1(str)
		Entry.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page)
	end

	def self.search_term_order(dictionaries, ssdbs, threshold, term, norm1 = nil, norm2 = nil)
		return [] if term.empty?

		entries = dictionaries.inject([]) do |sum, dic|
			sum + dic.search_term(ssdbs[dic.name], term, norm1, norm2, threshold)
		end

		entries.sort_by{|e| e[:score]}.reverse
	end

	def self.search_term_top(dictionaries, ssdbs, threshold, term, norm1 = nil, norm2 = nil)
		return [] if term.empty?

		entries = dictionaries.inject([]) do |sum, dic|
			sum + dic.search_term(ssdbs[dic.name], term, norm1, norm2, threshold)
		end

		return [] if entries.empty?

		max_score = entries.max{|a, b| a[:score] <=> b[:score]}[:score]
		entries.delete_if{|e| e[:score] < max_score}
	end

	def additional_entries
		@additional_entries ||= ActiveRecord::Base.connection.exec_query("SELECT label, norm1, norm2, identifier FROM entries WHERE dictionary_id=$1 AND mode=1", 'SQL', [[nil, id]], prepare:true).to_a.each{|r| r.symbolize_keys!}
	end

	def search_term(ssdb, term, norm1 = nil, norm2 = nil, threshold = nil)
		return [] if term.empty?
		raise "no ssdb for the dictionry #{name}." unless ssdb.present?

		norm1 ||= normalize1(term)
		norm2 ||= normalize2(term)
		threshold ||= self.threshold

		results = additional_entries.collect{|e| e.dup}

		norm2s = ssdb.retrieve(norm2)

		norm2s.each do |n2|
			results += ActiveRecord::Base.connection.exec_query("SELECT label, norm1, norm2, identifier FROM entries WHERE dictionary_id=$1 AND norm2=$2 AND mode=0", 'SQL', [[nil, id], [nil, n2]], prepare:true).to_a.each{|r| r.symbolize_keys!}
		end

		results.uniq!
		results.each{|e| e.merge!(score: str_sim.call(term, e[:label], norm1, e[:norm1], norm2, e[:norm2]))}
		results.delete_if{|e| e[:score] < threshold}
	end

	def sim_string_db_dir
		Dictionary::SIM_STRING_DB_DIR + self.name
	end

	private

	def create_additional_entry(id, label)
		e = entries.find_by_label_and_identifier(label, id)
		return unless e.nil?

		norm1 = normalize1(label)
		norm2 = normalize2(label)
		entries.create({label: label, identifier: id, norm1: norm1, norm2: norm2, label_length: label.length, mode: Entry::MODE_ADDITION})
		true
	end

	def update_tmp_sim_string_db
		FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
		db = Simstring::Writer.new tmp_sim_string_db_path, 3, false, true
		self.entries.where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION]).pluck(:norm2).uniq.each{|norm2| db.insert norm2}
		db.close
	end

	# Get typographic normalization of an input text using an analyzer of ElasticSearch.
	#
	# * (string) text  - Input text.
	#
	def normalize1(text, analyzer = nil)
		Entry.normalize(text, normalizer1, analyzer)
	end

	def self.normalize1(text, analyzer = nil)
		Entry.normalize(text, 'normalizer1', analyzer)
	end

	# Get typographic and morphosyntactic normalization of an input text using an analyzer of ElasticSearch.
	#
	# * (string) text  - Input text.
	#
	def normalize2(text, analyzer = nil)
		Entry.normalize(text, normalizer2, analyzer)
	end

	def self.normalize2(text, analyzer = nil)
		Entry.normalize(text, 'normalizer2', analyzer)
	end

	def normalizer1
		@normalizer1 ||= 'normalizer1' + language_suffix
	end

	def normalizer2
		@normalizer2 ||= 'normalizer2' + language_suffix
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
end
