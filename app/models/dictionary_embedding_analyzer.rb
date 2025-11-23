# Model for analyzing dictionary entries with embeddings
# Provides statistical analyses and cleaning operations for dictionary embeddings
#
# Usage:
#   analyzer = DictionaryEmbeddingAnalyzer.new('mondo')
#   analyzer.embedding_coverage
#   analyzer.clean_by_origin_proximity(dry_run: false)
#
class DictionaryEmbeddingAnalyzer
  attr_reader :dictionary

  def initialize(dictionary_name)
    @dictionary = Dictionary.find_by(name: dictionary_name)
    raise ArgumentError, "Dictionary '#{dictionary_name}' not found" unless @dictionary
  end

  # Check if the dictionary has embeddings (via semantic table)
  def has_embeddings?
    @dictionary.embeddings_populated?
  end

  # Get statistics about embedding coverage
  # Returns hash with total entries, entries with embeddings, and coverage percentage
  def embedding_coverage
    total = @dictionary.entries.count

    with_embeddings = if @dictionary.has_semantic_table?
      ActiveRecord::Base.connection.exec_query(
        "SELECT COUNT(*) as cnt FROM #{@dictionary.semantic_table_name}"
      ).first['cnt']
    else
      0
    end

    {
      total_entries: total,
      entries_with_embeddings: with_embeddings,
      entries_without_embeddings: total - with_embeddings,
      coverage_percentage: total > 0 ? (with_embeddings.to_f / total * 100).round(2) : 0
    }
  end

  # Find entries most similar to a given entry based on embedding similarity
  #
  # @param entry_id [Integer] The entry ID to find similar entries for
  # @param limit [Integer] Number of similar entries to return (default: 10)
  # @param exclude_same_identifier [Boolean] Whether to exclude entries with same identifier (default: true)
  #
  # Returns array of similar entries with their similarity scores
  def find_similar_entries(entry_id:, limit: 10, exclude_same_identifier: true)
    return { error: "No semantic table" } unless @dictionary.has_semantic_table?

    # Get the entry's embedding from semantic table
    entry = @dictionary.entries.find(entry_id)
    semantic_entry = ActiveRecord::Base.connection.exec_query(
      "SELECT embedding FROM #{@dictionary.semantic_table_name} WHERE id = #{entry_id}"
    ).first

    return { error: "Entry not in semantic table" } unless semantic_entry

    embedding_vector = semantic_entry['embedding']

    base_sql = <<~SQL
      SELECT
        s.id,
        s.label,
        s.identifier,
        1.0 - (s.embedding <=> '#{embedding_vector}') AS similarity,
        s.embedding <=> '#{embedding_vector}' AS distance
      FROM #{@dictionary.semantic_table_name} s
      WHERE s.id != $1 AND s.searchable = true
    SQL

    if exclude_same_identifier
      base_sql += " AND s.identifier != $2\n"
      base_sql += "ORDER BY s.embedding <=> '#{embedding_vector}'\nLIMIT $3;"
      params = [entry_id, entry.identifier, limit]
    else
      base_sql += "ORDER BY s.embedding <=> '#{embedding_vector}'\nLIMIT $2;"
      params = [entry_id, limit]
    end

    results = ActiveRecord::Base.connection.exec_query(base_sql, "find_similar_entries", params)

    results.map do |row|
      {
        id: row["id"],
        label: row["label"],
        identifier: row["identifier"],
        similarity: row["similarity"].to_f.round(4),
        distance: row["distance"].to_f.round(4)
      }
    end
  end

  # Clean dictionary using two-stage outlier detection
  # Stage 1: Remove global outliers (entries close to PubMedBERT origin)
  # Stage 2: Remove local outliers (entries distant from their identifier cluster)
  #
  # @param origin_terms [Array<String>] Terms for global outlier detection (default: ['DNA', 'protein'])
  # @param global_distance_threshold [Float] Distance threshold for global outliers (default: 0.75)
  # @param local_z_threshold [Float] Z-score threshold for local outliers (default: 2.0)
  # @param min_cluster_size [Integer] Minimum cluster size for local detection (default: 3)
  # @param dry_run [Boolean] If true, only report what would be changed (default: true)
  #
  # Returns hash with detailed statistics
  def clean_dictionary_two_stage(
    origin_terms: ['DNA', 'protein'],
    global_distance_threshold: 0.75,
    local_z_threshold: 2.0,
    min_cluster_size: 3,
    dry_run: true
  )
    return { error: "No semantic table" } unless @dictionary.has_semantic_table?

    # Calculate distance stats and validation BEFORE cleaning
    centroid_stats_before = dictionary_centroid_stats
    local_stats_before = local_distance_stats(min_cluster_size: min_cluster_size)
    validation_before = leave_one_out_validation(sample_size: 1000, min_cluster_size: min_cluster_size)

    results = {
      stage1_global: {},
      stage2_local: {},
      total_outliers: 0,
      dry_run: dry_run,
      distance_stats: {
        before: {
          centroid: centroid_stats_before,
          local: local_stats_before
        }
      },
      validation: {
        before: validation_before
      }
    }

    table = @dictionary.semantic_table_name

    # STAGE 1: Global outlier detection (origin-proximity)
    puts "Stage 1: Detecting global outliers (close to PubMedBERT origin)..." if dry_run

    global_outliers = detect_origin_proximity_outliers(
      origin_terms: origin_terms,
      distance_threshold: global_distance_threshold,
      limit: nil
    )

    return { error: global_outliers[:error] } if global_outliers[:error]

    global_outlier_ids = global_outliers[:outliers].map { |o| o[:id] }

    results[:stage1_global] = {
      outliers_found: global_outlier_ids.length,
      distribution: global_outliers[:distribution],
      sample_outliers: global_outliers[:outliers].first(10).map do |o|
        {
          id: o[:id],
          identifier: o[:identifier],
          label: o[:label],
          closest_origin: o[:closest_origin],
          distance: o[:min_distance]
        }
      end
    }

    puts "  Found #{global_outlier_ids.length} global outliers" if dry_run

    # STAGE 2: Local (cluster-based) outlier detection
    puts "\nStage 2: Detecting local outliers within identifier clusters..." if dry_run

    exclusion_clause = if global_outlier_ids.any?
      "AND s.id NOT IN (#{global_outlier_ids.join(',')})"
    else
      ""
    end

    sql_local = <<~SQL
      WITH cluster_entries AS (
        SELECT s.id, s.identifier, s.label, s.embedding
        FROM #{table} s
        WHERE s.searchable = true #{exclusion_clause}
      ),
      cluster_sizes AS (
        SELECT identifier, COUNT(*) as size
        FROM cluster_entries
        GROUP BY identifier
        HAVING COUNT(*) >= #{min_cluster_size}
      ),
      cluster_centroids AS (
        SELECT
          ce.identifier,
          AVG(ce.embedding) AS centroid_embedding
        FROM cluster_entries ce
        INNER JOIN cluster_sizes cs ON ce.identifier = cs.identifier
        GROUP BY ce.identifier
      ),
      distances AS (
        SELECT
          ce.id,
          ce.identifier,
          ce.label,
          ce.embedding <=> cc.centroid_embedding AS distance
        FROM cluster_entries ce
        INNER JOIN cluster_centroids cc ON ce.identifier = cc.identifier
      ),
      cluster_stats AS (
        SELECT
          identifier,
          AVG(distance) AS mean_distance,
          STDDEV(distance) AS stddev_distance
        FROM distances
        GROUP BY identifier
      )
      SELECT
        d.id,
        d.identifier,
        d.label,
        d.distance,
        cs.mean_distance,
        cs.stddev_distance,
        (d.distance - cs.mean_distance) / NULLIF(cs.stddev_distance, 0) AS z_score
      FROM distances d
      INNER JOIN cluster_stats cs ON d.identifier = cs.identifier
      WHERE (d.distance - cs.mean_distance) / NULLIF(cs.stddev_distance, 0) > #{local_z_threshold}
      ORDER BY z_score DESC;
    SQL

    local_outliers = ActiveRecord::Base.connection.exec_query(sql_local)
    local_outlier_ids = local_outliers.map { |r| r['id'] }

    results[:stage2_local] = {
      outliers_found: local_outlier_ids.length,
      min_cluster_size: min_cluster_size,
      z_threshold: local_z_threshold,
      sample_outliers: local_outliers.first(10).map do |row|
        {
          id: row['id'],
          identifier: row['identifier'],
          label: row['label'],
          distance: row['distance'].to_f.round(4),
          z_score: row['z_score'].to_f.round(2)
        }
      end
    }

    puts "  Found #{local_outlier_ids.length} local outliers" if dry_run

    # Combine all outlier IDs
    all_outlier_ids = (global_outlier_ids + local_outlier_ids).uniq
    results[:total_outliers] = all_outlier_ids.length

    # Execute or report
    if dry_run
      # Query searchable status from semantic table
      currently_searchable = ActiveRecord::Base.connection.exec_query(
        "SELECT COUNT(*) as cnt FROM #{table} WHERE id IN (#{all_outlier_ids.join(',')}) AND searchable = true"
      ).first['cnt']
      currently_unsearchable = all_outlier_ids.length - currently_searchable

      results[:would_mark_unsearchable] = currently_searchable
      results[:already_unsearchable] = currently_unsearchable

      puts "\nDRY RUN - No changes made"
      puts "Total outliers: #{results[:total_outliers]}"
      puts "  Stage 1 (global): #{global_outlier_ids.length}"
      puts "  Stage 2 (local): #{local_outlier_ids.length}"
      puts "  Would mark as non-searchable: #{currently_searchable}"
    else
      # Mark as non-searchable in semantic table only
      if all_outlier_ids.any?
        result = ActiveRecord::Base.connection.execute(
          "UPDATE #{table} SET searchable = false WHERE id IN (#{all_outlier_ids.join(',')}) AND searchable = true"
        )
        updated = result.cmd_tuples
        already_unsearchable = all_outlier_ids.length - updated
      else
        updated = 0
        already_unsearchable = 0
      end

      results[:marked_unsearchable] = updated
      results[:already_unsearchable] = already_unsearchable
      results[:remaining_searchable] = ActiveRecord::Base.connection.exec_query(
        "SELECT COUNT(*) as cnt FROM #{table} WHERE searchable = true"
      ).first['cnt']

      # Calculate distance stats and validation AFTER cleaning
      centroid_stats_after = dictionary_centroid_stats
      local_stats_after = local_distance_stats(min_cluster_size: min_cluster_size)
      validation_after = leave_one_out_validation(sample_size: 1000, min_cluster_size: min_cluster_size)
      results[:distance_stats][:after] = {
        centroid: centroid_stats_after,
        local: local_stats_after
      }
      results[:validation][:after] = validation_after
    end

    results
  end

  # Clean dictionary by marking origin-proximity outliers as non-searchable
  # This removes problematic entries (acronyms, DNA/protein terms) from semantic search
  #
  # @param origin_terms [Array<String>] Terms representing PubMedBERT origin (default: ['DNA', 'protein'])
  # @param distance_threshold [Float] Maximum distance from origin to consider outlier (default: 0.75)
  # @param dry_run [Boolean] If true, only report what would be changed (default: true)
  #
  # Returns hash with statistics about cleaning operation
  def clean_by_origin_proximity(origin_terms: ['DNA', 'protein'], distance_threshold: 0.75, dry_run: true)
    return { error: "No semantic table" } unless @dictionary.has_semantic_table?

    # Calculate distance stats and validation BEFORE cleaning
    centroid_stats_before = dictionary_centroid_stats
    validation_before = leave_one_out_validation(sample_size: 1000)

    # First detect outliers
    outliers = detect_origin_proximity_outliers(
      origin_terms: origin_terms,
      distance_threshold: distance_threshold,
      limit: nil
    )

    return { error: outliers[:error] } if outliers[:error]

    outlier_ids = outliers[:outliers].map { |o| o[:id] }
    table = @dictionary.semantic_table_name

    stats = {
      total_entries: @dictionary.entries_num,
      outliers_found: outlier_ids.length,
      distribution: outliers[:distribution],
      dry_run: dry_run,
      distance_stats: {
        before: { centroid: centroid_stats_before }
      },
      validation: {
        before: validation_before
      }
    }

    if dry_run
      # Query searchable status from semantic table
      if outlier_ids.any?
        currently_searchable = ActiveRecord::Base.connection.exec_query(
          "SELECT COUNT(*) as cnt FROM #{table} WHERE id IN (#{outlier_ids.join(',')}) AND searchable = true"
        ).first['cnt']
      else
        currently_searchable = 0
      end
      currently_unsearchable = outlier_ids.length - currently_searchable

      stats[:would_mark_unsearchable] = currently_searchable
      stats[:already_unsearchable] = currently_unsearchable
      stats[:sample_outliers] = outliers[:outliers].first(20).map do |o|
        {
          label: o[:label],
          identifier: o[:identifier],
          closest_origin: o[:closest_origin],
          min_distance: o[:min_distance]
        }
      end
    else
      # Mark as non-searchable in semantic table only
      if outlier_ids.any?
        result = ActiveRecord::Base.connection.execute(
          "UPDATE #{table} SET searchable = false WHERE id IN (#{outlier_ids.join(',')}) AND searchable = true"
        )
        updated = result.cmd_tuples
        already_unsearchable = outlier_ids.length - updated
      else
        updated = 0
        already_unsearchable = 0
      end

      stats[:marked_unsearchable] = updated
      stats[:already_unsearchable] = already_unsearchable
      stats[:remaining_searchable] = ActiveRecord::Base.connection.exec_query(
        "SELECT COUNT(*) as cnt FROM #{table} WHERE searchable = true"
      ).first['cnt']

      # Calculate distance stats and validation AFTER cleaning
      centroid_stats_after = dictionary_centroid_stats
      validation_after = leave_one_out_validation(sample_size: 1000)
      stats[:distance_stats][:after] = { centroid: centroid_stats_after }
      stats[:validation][:after] = validation_after
    end

    stats
  end

  # Calculate dictionary centroid distance statistics
  # Returns avg/max distance from the overall dictionary centroid for all searchable entries
  # This shows how "tight" or "spread out" the dictionary is as a whole
  def dictionary_centroid_stats
    return nil unless @dictionary.has_semantic_table?

    table = @dictionary.semantic_table_name

    sql = <<~SQL
      WITH centroid AS (
        SELECT AVG(embedding) AS centroid_embedding
        FROM #{table}
        WHERE searchable = true
      ),
      distances AS (
        SELECT s.embedding <=> c.centroid_embedding AS distance
        FROM #{table} s, centroid c
        WHERE s.searchable = true
      )
      SELECT
        AVG(distance) AS avg_distance,
        MAX(distance) AS max_distance
      FROM distances
    SQL

    result = ActiveRecord::Base.connection.exec_query(sql, "dictionary_centroid_stats").first

    {
      avg: result['avg_distance']&.to_f&.round(4),
      max: result['max_distance']&.to_f&.round(4)
    }
  rescue => e
    Rails.logger.error "Error calculating dictionary centroid stats: #{e.message}"
    nil
  end

  # Calculate origin proximity statistics (distance to origin terms like DNA, protein)
  # Returns avg/max distance to the closest origin term for all searchable entries
  # Used to detect entries too close to PubMedBERT's semantic origin
  def origin_proximity_stats(origin_terms: ['DNA', 'protein'])
    return nil unless @dictionary.has_semantic_table?

    table = @dictionary.semantic_table_name

    # Fetch embeddings for origin terms
    origin_embeddings = origin_terms.map do |term|
      embedding = EmbeddingServer.fetch_embedding(term)
      next unless embedding
      { term: term, vector: "[#{embedding.map(&:to_f).join(',')}]" }
    end.compact

    return nil if origin_embeddings.empty?

    vector_conditions = origin_embeddings.map.with_index do |emb, idx|
      "s.embedding <=> $#{idx + 1}"
    end.join(', ')

    sql = <<~SQL
      SELECT
        AVG(LEAST(#{vector_conditions})) AS avg_distance,
        MAX(LEAST(#{vector_conditions})) AS max_distance
      FROM #{table} s
      WHERE s.searchable = true
    SQL

    params = origin_embeddings.map { |emb| emb[:vector] }
    result = ActiveRecord::Base.connection.exec_query(sql, "global_distance_stats", params).first

    {
      avg: result['avg_distance']&.to_f&.round(4),
      max: result['max_distance']&.to_f&.round(4)
    }
  rescue => e
    Rails.logger.error "Error calculating global distance stats: #{e.message}"
    nil
  end

  # Calculate local distance statistics (distance from cluster centroid)
  # Returns avg/max distance from centroid across all clusters
  def local_distance_stats(min_cluster_size: 3)
    return nil unless @dictionary.has_semantic_table?

    table = @dictionary.semantic_table_name

    sql = <<~SQL
      WITH cluster_entries AS (
        SELECT s.id, s.identifier, s.embedding
        FROM #{table} s
        WHERE s.searchable = true
      ),
      cluster_sizes AS (
        SELECT identifier, COUNT(*) as size
        FROM cluster_entries
        GROUP BY identifier
        HAVING COUNT(*) >= $1
      ),
      cluster_centroids AS (
        SELECT
          ce.identifier,
          AVG(ce.embedding) AS centroid_embedding
        FROM cluster_entries ce
        INNER JOIN cluster_sizes cs ON ce.identifier = cs.identifier
        GROUP BY ce.identifier
      ),
      distances AS (
        SELECT
          ce.id,
          ce.embedding <=> cc.centroid_embedding AS distance
        FROM cluster_entries ce
        INNER JOIN cluster_centroids cc ON ce.identifier = cc.identifier
      )
      SELECT
        AVG(distance) AS avg_distance,
        MAX(distance) AS max_distance
      FROM distances
    SQL

    result = ActiveRecord::Base.connection.exec_query(sql, "local_distance_stats", [min_cluster_size]).first

    {
      avg: result['avg_distance']&.to_f&.round(4),
      max: result['max_distance']&.to_f&.round(4)
    }
  rescue => e
    Rails.logger.error "Error calculating local distance stats: #{e.message}"
    nil
  end

  # Detect global outliers based on proximity to PubMedBERT semantic origin
  # Identifies entries semantically too close to fundamental biology terms (DNA, protein)
  #
  # @param origin_terms [Array<String>] Terms representing PubMedBERT origin (default: ['DNA', 'protein'])
  # @param distance_threshold [Float] Maximum distance from origin to consider outlier (default: 0.75)
  # @param limit [Integer] Maximum outliers to return (default: nil = all)
  #
  # Returns hash with outlier entries and distances
  def detect_origin_proximity_outliers(origin_terms: ['DNA', 'protein'], distance_threshold: 0.75, limit: nil)
    return { error: "No semantic table" } unless @dictionary.has_semantic_table?

    table = @dictionary.semantic_table_name

    # Fetch embeddings for origin terms
    origin_embeddings = origin_terms.map do |term|
      embedding = EmbeddingServer.fetch_embedding(term)
      next unless embedding
      { term: term, vector: "[#{embedding.map(&:to_f).join(',')}]" }
    end.compact

    return { error: "Could not fetch origin embeddings" } if origin_embeddings.empty?

    # Build SQL to find entries close to ANY origin term
    vector_conditions = origin_embeddings.map.with_index do |emb, idx|
      "s.embedding <=> $#{idx + 1}"
    end.join(', ')

    # Build column names for each origin term
    distance_columns = origin_embeddings.map.with_index do |emb, idx|
      term_safe = emb[:term].gsub(/[^a-zA-Z0-9]/, '_')
      "s.embedding <=> $#{idx + 1} AS #{term_safe}_distance"
    end.join(",\n          ")

    distance_column_names = origin_embeddings.map do |emb|
      term_safe = emb[:term].gsub(/[^a-zA-Z0-9]/, '_')
      "#{term_safe}_distance"
    end.join(', ')

    case_conditions = origin_embeddings.map do |emb|
      term_safe = emb[:term].gsub(/[^a-zA-Z0-9]/, '_')
      "WHEN min_distance = #{term_safe}_distance THEN '#{emb[:term]}'"
    end.join("\n          ")

    sql = <<~SQL
      WITH distances AS (
        SELECT
          s.id,
          s.identifier,
          s.label,
          #{distance_columns},
          LEAST(#{vector_conditions}) AS min_distance
        FROM #{table} s
        WHERE s.searchable = true
      )
      SELECT
        id,
        identifier,
        label,
        #{distance_column_names},
        min_distance,
        CASE
          #{case_conditions}
        END as closest_origin
      FROM distances
      WHERE min_distance < $#{origin_embeddings.length + 1}
      ORDER BY min_distance
      #{limit ? "LIMIT #{limit}" : ''}
    SQL

    params = origin_embeddings.map { |emb| emb[:vector] } + [distance_threshold]
    results = ActiveRecord::Base.connection.exec_query(sql, "origin_proximity_outliers", params)

    outliers = results.map do |row|
      distances = {}
      origin_embeddings.each do |emb|
        term_safe = emb[:term].gsub(/[^a-zA-Z0-9]/, '_')
        distances[emb[:term]] = row["#{term_safe}_distance"].to_f.round(4)
      end

      {
        id: row['id'],
        identifier: row['identifier'],
        label: row['label'],
        min_distance: row['min_distance'].to_f.round(4),
        closest_origin: row['closest_origin'],
        distances: distances
      }
    end

    {
      total_outliers: outliers.length,
      outliers: outliers,
      distribution: outliers.group_by { |o| o[:closest_origin] }.transform_values(&:count)
    }
  end

  # Perform leave-one-out cross-validation on searchable entries
  # For each entry, finds nearest neighbors excluding itself and checks if correct identifier is found
  #
  # @param sample_size [Integer] Number of entries to sample (default: 1000, nil for all)
  # @param min_cluster_size [Integer] Only test entries from clusters with at least this many entries (default: 2)
  #
  # Returns hash with validation metrics
  def leave_one_out_validation(sample_size: 1000, min_cluster_size: 2)
    return nil unless @dictionary.has_semantic_table?

    table = @dictionary.semantic_table_name

    # Get entries from clusters with multiple entries (need at least 2 to do leave-one-out)
    sql_entries = <<~SQL
      WITH cluster_sizes AS (
        SELECT identifier, COUNT(*) as size
        FROM #{table}
        WHERE searchable = true
        GROUP BY identifier
        HAVING COUNT(*) >= $1
      )
      SELECT s.id, s.identifier, s.embedding
      FROM #{table} s
      INNER JOIN cluster_sizes cs ON s.identifier = cs.identifier
      WHERE s.searchable = true
    SQL

    entries = ActiveRecord::Base.connection.exec_query(sql_entries, "loo_entries", [min_cluster_size])

    return { error: "No entries with cluster size >= #{min_cluster_size}" } if entries.empty?

    # Sample if needed
    test_entries = entries.to_a
    if sample_size && test_entries.length > sample_size
      test_entries = test_entries.sample(sample_size)
    end

    total_tests = 0
    correct_rank1 = 0
    correct_top5 = 0
    rank_reciprocal_sum = 0.0

    test_entries.each do |entry|
      total_tests += 1
      entry_id = entry['id']
      entry_identifier = entry['identifier']
      entry_embedding = entry['embedding']

      # Find nearest neighbors excluding this entry
      sql_neighbors = <<~SQL
        SELECT identifier
        FROM #{table}
        WHERE searchable = true AND id != $1
        ORDER BY embedding <=> $2
        LIMIT 5
      SQL

      neighbors = ActiveRecord::Base.connection.exec_query(
        sql_neighbors,
        "loo_neighbors",
        [entry_id, entry_embedding]
      )

      # Find rank of correct identifier
      correct_rank = nil
      neighbors.each_with_index do |neighbor, idx|
        if neighbor['identifier'] == entry_identifier
          correct_rank = idx + 1
          break
        end
      end

      if correct_rank
        rank_reciprocal_sum += 1.0 / correct_rank
        correct_rank1 += 1 if correct_rank == 1
        correct_top5 += 1 if correct_rank <= 5
      end
    end

    {
      total_tested: total_tests,
      total_searchable: entries.length,
      rank1_accuracy: total_tests > 0 ? (correct_rank1.to_f / total_tests * 100).round(2) : 0,
      top5_accuracy: total_tests > 0 ? (correct_top5.to_f / total_tests * 100).round(2) : 0,
      mrr: total_tests > 0 ? (rank_reciprocal_sum / total_tests).round(4) : 0
    }
  rescue => e
    Rails.logger.error "Error in leave-one-out validation: #{e.message}"
    nil
  end
end
