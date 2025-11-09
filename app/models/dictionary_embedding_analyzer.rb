# Model for analyzing dictionary entries with embeddings
# Provides various statistical and semantic analyses for dictionary embeddings
#
# Usage:
#   analyzer = DictionaryEmbeddingAnalyzer.new('mondo')
#   analyzer.semantic_distance_from_labels
#   analyzer.embedding_coverage
#   analyzer.outlier_detection
#
class DictionaryEmbeddingAnalyzer
  attr_reader :dictionary

  def initialize(dictionary_name)
    @dictionary = Dictionary.find_by(name: dictionary_name)
    raise ArgumentError, "Dictionary '#{dictionary_name}' not found" unless @dictionary
  end

  # Check if the dictionary has embeddings
  def has_embeddings?
    @dictionary.entries.exists? && @dictionary.entries.where.not(embedding: nil).exists?
  end

  # Get statistics about embedding coverage
  # Returns hash with total entries, entries with embeddings, and coverage percentage
  def embedding_coverage
    total = @dictionary.entries.count
    with_embeddings = @dictionary.entries.where.not(embedding: nil).count

    {
      total_entries: total,
      entries_with_embeddings: with_embeddings,
      entries_without_embeddings: total - with_embeddings,
      coverage_percentage: total > 0 ? (with_embeddings.to_f / total * 100).round(2) : 0
    }
  end

  # Analyze semantic distance of synonyms from their corresponding labels
  # Groups results by tag type (ExactSynonym, RelatedSynonym, BroadSynonym)
  #
  # Returns array of hashes with statistics for each tag type
  def semantic_distance_from_labels(tag_types: ['ExactSynonym', 'RelatedSynonym', 'BroadSynonym'])
    sql = <<~SQL
      WITH synonym_entries AS (
        SELECT
          e.id,
          e.identifier,
          e.label,
          e.embedding,
          t.value AS tag_type
        FROM entries e
        INNER JOIN entry_tags et ON et.entry_id = e.id
        INNER JOIN tags t ON t.id = et.tag_id
        WHERE e.dictionary_id = ?
          AND e.embedding IS NOT NULL
          AND t.value IN (?)
      ),
      label_entries AS (
        SELECT
          e.identifier,
          e.embedding AS label_embedding
        FROM entries e
        INNER JOIN entry_tags et ON et.entry_id = e.id
        INNER JOIN tags t ON t.id = et.tag_id
        WHERE e.dictionary_id = ?
          AND e.embedding IS NOT NULL
          AND t.value = 'Label'
      )
      SELECT
        se.tag_type,
        COUNT(*) AS entry_count,
        AVG(se.embedding <=> le.label_embedding) AS avg_distance,
        STDDEV_POP(se.embedding <=> le.label_embedding) AS stddev_distance,
        MIN(se.embedding <=> le.label_embedding) AS min_distance,
        MAX(se.embedding <=> le.label_embedding) AS max_distance,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY se.embedding <=> le.label_embedding) AS q1_distance,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY se.embedding <=> le.label_embedding) AS median_distance,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY se.embedding <=> le.label_embedding) AS q3_distance
      FROM synonym_entries se
      INNER JOIN label_entries le ON se.identifier = le.identifier
      GROUP BY se.tag_type
      ORDER BY se.tag_type;
    SQL

    results = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, @dictionary.id, tag_types, @dictionary.id]),
      "semantic_distance_from_labels"
    )

    results.map do |row|
      avg_dist = row["avg_distance"].to_f
      stddev_dist = row["stddev_distance"].to_f

      {
        tag_type: row["tag_type"],
        entry_count: row["entry_count"],
        avg_distance: avg_dist.round(4),
        stddev_distance: stddev_dist.round(4),
        coefficient_of_variation: avg_dist > 0 ? (stddev_dist / avg_dist * 100).round(2) : nil,
        min_distance: row["min_distance"].to_f.round(4),
        max_distance: row["max_distance"].to_f.round(4),
        q1_distance: row["q1_distance"].to_f.round(4),
        median_distance: row["median_distance"].to_f.round(4),
        q3_distance: row["q3_distance"].to_f.round(4)
      }
    end
  end

  # Calculate average semantic distance from centroid for each tag type
  # The centroid is the mean embedding vector of all entries with that tag
  #
  # Returns array of hashes with statistics for each tag type
  def semantic_distance_from_centroid(tag_types: nil)
    tag_types ||= @dictionary.tags.pluck(:value).uniq

    results = tag_types.map do |tag_type|
      sql = <<~SQL
        WITH tag_entries AS (
          SELECT e.embedding
          FROM entries e
          INNER JOIN entry_tags et ON et.entry_id = e.id
          INNER JOIN tags t ON t.id = et.tag_id
          WHERE e.dictionary_id = ?
            AND t.value = ?
            AND e.embedding IS NOT NULL
        ),
        centroid AS (
          SELECT AVG(embedding) AS centroid_embedding
          FROM tag_entries
        )
        SELECT
          COUNT(*) AS entry_count,
          AVG(te.embedding <=> c.centroid_embedding) AS avg_distance,
          STDDEV_POP(te.embedding <=> c.centroid_embedding) AS stddev_distance,
          MIN(te.embedding <=> c.centroid_embedding) AS min_distance,
          MAX(te.embedding <=> c.centroid_embedding) AS max_distance,
          PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY te.embedding <=> c.centroid_embedding) AS median_distance
        FROM tag_entries te
        CROSS JOIN centroid c;
      SQL

      result = ActiveRecord::Base.connection.exec_query(
        ActiveRecord::Base.send(:sanitize_sql_array, [sql, @dictionary.id, tag_type]),
        "semantic_distance_from_centroid"
      ).first

      if result && result["entry_count"] > 0
        avg_dist = result["avg_distance"].to_f
        stddev_dist = result["stddev_distance"].to_f

        {
          tag_type: tag_type,
          entry_count: result["entry_count"],
          avg_distance: avg_dist.round(4),
          stddev_distance: stddev_dist.round(4),
          coefficient_of_variation: avg_dist > 0 ? (stddev_dist / avg_dist * 100).round(2) : nil,
          min_distance: result["min_distance"].to_f.round(4),
          max_distance: result["max_distance"].to_f.round(4),
          median_distance: result["median_distance"].to_f.round(4)
        }
      end
    end.compact

    results
  end

  # Detect outlier entries based on semantic distance from tag centroid
  # Returns entries that are significantly distant from their tag group
  #
  # @param tag_type [String] The tag type to analyze
  # @param threshold_multiplier [Float] Number of standard deviations to consider as outlier (default: 2.5)
  # @param limit [Integer] Maximum number of outliers to return (default: 100)
  #
  # Returns array of outlier entries with their distances
  def detect_outliers(tag_type:, threshold_multiplier: 2.5, limit: 100)
    sql = <<~SQL
      WITH tag_entries AS (
        SELECT
          e.id,
          e.label,
          e.identifier,
          e.embedding
        FROM entries e
        INNER JOIN entry_tags et ON et.entry_id = e.id
        INNER JOIN tags t ON t.id = et.tag_id
        WHERE e.dictionary_id = ?
          AND t.value = ?
          AND e.embedding IS NOT NULL
      ),
      centroid AS (
        SELECT AVG(embedding) AS centroid_embedding
        FROM tag_entries
      ),
      distances AS (
        SELECT
          te.id,
          te.label,
          te.identifier,
          te.embedding <=> c.centroid_embedding AS distance
        FROM tag_entries te
        CROSS JOIN centroid c
      ),
      stats AS (
        SELECT
          AVG(distance) AS mean_distance,
          STDDEV_POP(distance) AS stddev_distance
        FROM distances
      )
      SELECT
        d.id,
        d.label,
        d.identifier,
        d.distance,
        s.mean_distance,
        s.stddev_distance,
        (d.distance - s.mean_distance) / NULLIF(s.stddev_distance, 0) AS z_score
      FROM distances d
      CROSS JOIN stats s
      WHERE (d.distance - s.mean_distance) / NULLIF(s.stddev_distance, 0) > ?
      ORDER BY z_score DESC
      LIMIT ?;
    SQL

    results = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [
        sql,
        @dictionary.id,
        tag_type,
        threshold_multiplier,
        limit
      ]),
      "detect_outliers"
    )

    results.map do |row|
      {
        id: row["id"],
        label: row["label"],
        identifier: row["identifier"],
        distance: row["distance"].to_f.round(4),
        mean_distance: row["mean_distance"].to_f.round(4),
        stddev_distance: row["stddev_distance"].to_f.round(4),
        z_score: row["z_score"].to_f.round(2)
      }
    end
  end

  # Find entries most similar to a given entry based on embedding similarity
  #
  # @param entry_id [Integer] The entry ID to find similar entries for
  # @param limit [Integer] Number of similar entries to return (default: 10)
  # @param exclude_same_identifier [Boolean] Whether to exclude entries with same identifier (default: true)
  #
  # Returns array of similar entries with their similarity scores
  def find_similar_entries(entry_id:, limit: 10, exclude_same_identifier: true)
    entry = @dictionary.entries.find(entry_id)

    # Convert embedding array to PostgreSQL vector format
    embedding_vector = "[#{entry.embedding.join(',')}]"

    base_sql = <<~SQL
      SELECT
        e.id,
        e.label,
        e.identifier,
        1.0 - (e.embedding <=> $1) AS similarity,
        e.embedding <=> $1 AS distance
      FROM entries e
      WHERE e.dictionary_id = $2
        AND e.id != $3
        AND e.embedding IS NOT NULL
    SQL

    if exclude_same_identifier
      base_sql += " AND e.identifier != $4\n"
      base_sql += "ORDER BY e.embedding <=> $1\nLIMIT $5;"
      params = [embedding_vector, @dictionary.id, entry_id, entry.identifier, limit]
    else
      base_sql += "ORDER BY e.embedding <=> $1\nLIMIT $4;"
      params = [embedding_vector, @dictionary.id, entry_id, limit]
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

  # Get distribution of entries by tag type
  # Returns hash with tag types and their counts
  def entry_distribution_by_tag
    sql = <<~SQL
      SELECT
        t.value AS tag_type,
        COUNT(DISTINCT e.id) AS entry_count,
        COUNT(DISTINCT CASE WHEN e.embedding IS NOT NULL THEN e.id END) AS entries_with_embedding
      FROM entries e
      INNER JOIN entry_tags et ON et.entry_id = e.id
      INNER JOIN tags t ON t.id = et.tag_id
      WHERE e.dictionary_id = ?
      GROUP BY t.value
      ORDER BY entry_count DESC;
    SQL

    results = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, @dictionary.id]),
      "entry_distribution_by_tag"
    )

    results.map do |row|
      total = row["entry_count"]
      with_embedding = row["entries_with_embedding"]

      {
        tag_type: row["tag_type"],
        entry_count: total,
        entries_with_embedding: with_embedding,
        embedding_coverage: total > 0 ? (with_embedding.to_f / total * 100).round(2) : 0
      }
    end
  end

  # Calculate pairwise similarity matrix for a sample of entries
  # Useful for understanding overall embedding quality
  #
  # @param sample_size [Integer] Number of entries to sample (default: 100)
  # @param tag_type [String] Optional tag type to filter entries
  #
  # Returns hash with similarity statistics
  def pairwise_similarity_statistics(sample_size: 100, tag_type: nil)
    query = @dictionary.entries.where.not(embedding: nil)

    if tag_type
      query = query.joins(:tags).where(tags: { value: tag_type })
    end

    sample_entries = query.order("RANDOM()").limit(sample_size)

    if sample_entries.count < 2
      return { error: "Not enough entries with embeddings for analysis" }
    end

    # Calculate pairwise similarities using SQL for efficiency
    entry_ids = sample_entries.pluck(:id)

    sql = <<~SQL
      SELECT
        AVG(1.0 - (e1.embedding <=> e2.embedding)) AS avg_similarity,
        STDDEV_POP(1.0 - (e1.embedding <=> e2.embedding)) AS stddev_similarity,
        MIN(1.0 - (e1.embedding <=> e2.embedding)) AS min_similarity,
        MAX(1.0 - (e1.embedding <=> e2.embedding)) AS max_similarity,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY 1.0 - (e1.embedding <=> e2.embedding)) AS median_similarity
      FROM entries e1
      CROSS JOIN entries e2
      WHERE e1.id IN (?)
        AND e2.id IN (?)
        AND e1.id < e2.id
        AND e1.embedding IS NOT NULL
        AND e2.embedding IS NOT NULL;
    SQL

    result = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, entry_ids, entry_ids]),
      "pairwise_similarity_statistics"
    ).first

    if result
      {
        sample_size: sample_entries.count,
        tag_type: tag_type,
        avg_similarity: result["avg_similarity"].to_f.round(4),
        stddev_similarity: result["stddev_similarity"].to_f.round(4),
        min_similarity: result["min_similarity"].to_f.round(4),
        max_similarity: result["max_similarity"].to_f.round(4),
        median_similarity: result["median_similarity"].to_f.round(4)
      }
    else
      { error: "Could not calculate similarity statistics" }
    end
  end

  # Get summary statistics for the dictionary embeddings
  # Returns comprehensive overview of the dictionary's embedding state
  def summary
    {
      dictionary_name: @dictionary.name,
      dictionary_id: @dictionary.id,
      has_embeddings: has_embeddings?,
      coverage: embedding_coverage,
      tag_distribution: entry_distribution_by_tag,
      identifier_statistics: identifier_statistics,
      created_at: @dictionary.created_at,
      updated_at: @dictionary.updated_at
    }
  end

  # Calculate semantic cohesion within identifier clusters
  # Measures how similar entries are within the same identifier
  # Only analyzes clusters with 2+ entries
  #
  # @param min_entries [Integer] Minimum entries per cluster to analyze (default: 2)
  # @param limit [Integer] Maximum number of clusters to analyze (default: nil = all)
  #
  # Returns array of clusters with their cohesion metrics
  def cluster_cohesion(min_entries: 2, limit: nil)
    # Find identifiers with multiple entries
    multi_entry_ids = @dictionary.entries
      .where.not(embedding: nil)
      .group(:identifier)
      .having("COUNT(*) >= ?", min_entries)
      .count
      .keys

    multi_entry_ids = multi_entry_ids.first(limit) if limit

    results = multi_entry_ids.map do |identifier|
      entries = @dictionary.entries
        .where(identifier: identifier)
        .where.not(embedding: nil)

      next if entries.count < min_entries

      # Calculate centroid for this cluster
      embeddings = entries.pluck(:embedding)

      # Calculate pairwise distances within cluster
      sql = <<~SQL
        WITH cluster_entries AS (
          SELECT
            e.id,
            e.label,
            e.embedding,
            t.value as tag
          FROM entries e
          LEFT JOIN entry_tags et ON et.entry_id = e.id
          LEFT JOIN tags t ON t.id = et.tag_id
          WHERE e.identifier = ?
            AND e.dictionary_id = ?
            AND e.embedding IS NOT NULL
        ),
        cluster_centroid AS (
          SELECT AVG(embedding) AS centroid_embedding
          FROM cluster_entries
        ),
        distances AS (
          SELECT
            ce.id,
            ce.label,
            ce.tag,
            ce.embedding <=> cc.centroid_embedding AS distance_from_centroid
          FROM cluster_entries ce
          CROSS JOIN cluster_centroid cc
        )
        SELECT
          COUNT(*) AS entry_count,
          AVG(distance_from_centroid) AS avg_distance,
          STDDEV_POP(distance_from_centroid) AS stddev_distance,
          MIN(distance_from_centroid) AS min_distance,
          MAX(distance_from_centroid) AS max_distance
        FROM distances
      SQL

      result = ActiveRecord::Base.connection.exec_query(
        ActiveRecord::Base.send(:sanitize_sql_array, [sql, identifier, @dictionary.id]),
        "cluster_cohesion"
      ).first

      # Get entry details
      entry_details = entries.includes(:tags).map do |e|
        {
          label: e.label,
          tags: e.tags.pluck(:value)
        }
      end

      {
        identifier: identifier,
        entry_count: result["entry_count"],
        entries: entry_details,
        avg_distance_from_cluster_centroid: result["avg_distance"].to_f.round(4),
        stddev_distance: result["stddev_distance"].to_f.round(4),
        min_distance: result["min_distance"].to_f.round(4),
        max_distance: result["max_distance"].to_f.round(4),
        cohesion_score: (1.0 - result["avg_distance"].to_f).round(4) # Higher = more cohesive
      }
    end.compact

    results.sort_by { |r| r[:cohesion_score] }.reverse
  end

  # Find outlier entries within their own identifier clusters
  # Detects entries that are semantically distant from their cluster siblings
  #
  # @param threshold_multiplier [Float] Number of std deviations to consider outlier (default: 2.0)
  # @param min_cluster_size [Integer] Minimum entries in cluster to analyze (default: 3)
  # @param limit [Integer] Maximum number of outliers to return (default: 100)
  #
  # Returns array of outlier entries with their cluster context
  def detect_cluster_outliers(threshold_multiplier: 2.0, min_cluster_size: 3, limit: 100)
    sql = <<~SQL
      WITH cluster_entries AS (
        SELECT
          e.id,
          e.identifier,
          e.label,
          e.embedding,
          t.value as tag
        FROM entries e
        LEFT JOIN entry_tags et ON et.entry_id = e.id
        LEFT JOIN tags t ON t.id = et.tag_id
        WHERE e.dictionary_id = ?
          AND e.embedding IS NOT NULL
      ),
      cluster_sizes AS (
        SELECT identifier, COUNT(*) as size
        FROM cluster_entries
        GROUP BY identifier
        HAVING COUNT(*) >= ?
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
          ce.tag,
          ce.embedding <=> cc.centroid_embedding AS distance
        FROM cluster_entries ce
        INNER JOIN cluster_centroids cc ON ce.identifier = cc.identifier
      ),
      cluster_stats AS (
        SELECT
          identifier,
          AVG(distance) AS mean_distance,
          STDDEV_POP(distance) AS stddev_distance
        FROM distances
        GROUP BY identifier
      )
      SELECT
        d.id,
        d.identifier,
        d.label,
        d.tag,
        d.distance,
        cs.mean_distance,
        cs.stddev_distance,
        (d.distance - cs.mean_distance) / NULLIF(cs.stddev_distance, 0) AS z_score
      FROM distances d
      INNER JOIN cluster_stats cs ON d.identifier = cs.identifier
      WHERE (d.distance - cs.mean_distance) / NULLIF(cs.stddev_distance, 0) > ?
      ORDER BY z_score DESC
      LIMIT ?;
    SQL

    results = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [
        sql,
        @dictionary.id,
        min_cluster_size,
        threshold_multiplier,
        limit
      ]),
      "detect_cluster_outliers"
    )

    results.map do |row|
      # Get all entries in this cluster for context
      cluster_entries = @dictionary.entries
        .where(identifier: row["identifier"])
        .includes(:tags)
        .map { |e| { label: e.label, tags: e.tags.pluck(:value) } }

      {
        id: row["id"],
        identifier: row["identifier"],
        label: row["label"],
        tag: row["tag"],
        distance_from_cluster_centroid: row["distance"].to_f.round(4),
        cluster_mean_distance: row["mean_distance"].to_f.round(4),
        cluster_stddev_distance: row["stddev_distance"].to_f.round(4),
        z_score: row["z_score"].to_f.round(2),
        cluster_entries: cluster_entries,
        cluster_size: cluster_entries.length
      }
    end
  end

  # Find entries similar to a given entry within the same identifier cluster
  # Useful for checking synonym quality within a concept
  #
  # @param entry_id [Integer] The entry ID to compare within its cluster
  # @param limit [Integer] Number of similar entries to return (default: 10)
  #
  # Returns array of entries from same cluster with similarity scores
  def find_similar_entries_in_cluster(entry_id:, limit: 10)
    entry = @dictionary.entries.find(entry_id)

    # Get all other entries in the same cluster
    cluster_entries = @dictionary.entries
      .where(identifier: entry.identifier)
      .where.not(id: entry_id)
      .where.not(embedding: nil)

    if cluster_entries.empty?
      return {
        message: "This is a single-entry cluster",
        cluster_size: 1
      }
    end

    # Convert embedding array to PostgreSQL vector format
    embedding_vector = "[#{entry.embedding.join(',')}]"

    sql = <<~SQL
      SELECT
        e.id,
        e.label,
        t.value as tag,
        1.0 - (e.embedding <=> $1) AS similarity,
        e.embedding <=> $1 AS distance
      FROM entries e
      LEFT JOIN entry_tags et ON et.entry_id = e.id
      LEFT JOIN tags t ON t.id = et.tag_id
      WHERE e.identifier = $2
        AND e.dictionary_id = $3
        AND e.id != $4
        AND e.embedding IS NOT NULL
      ORDER BY e.embedding <=> $1
      LIMIT $5;
    SQL

    results = ActiveRecord::Base.connection.exec_query(
      sql,
      "find_similar_in_cluster",
      [embedding_vector, entry.identifier, @dictionary.id, entry_id, limit]
    )

    {
      query_entry: {
        label: entry.label,
        tag: entry.tags.first&.value
      },
      cluster_size: cluster_entries.count + 1,
      similar_entries: results.map do |row|
        {
          id: row["id"],
          label: row["label"],
          tag: row["tag"],
          similarity: row["similarity"].to_f.round(4),
          distance: row["distance"].to_f.round(4)
        }
      end
    }
  end

  # Test identifier recovery accuracy using semantic similarity
  # For each entry, find the most similar entry and check if they share the same identifier
  # This validates embedding quality: good embeddings should recover correct identifiers
  #
  # @param sample_size [Integer] Number of entries to test (default: 100, nil = all)
  # @param tag_type [String] Optional tag type to filter entries (e.g., 'ExactSynonym')
  # @param exclude_same_entry [Boolean] Exclude the query entry itself (default: true)
  # @param min_cluster_size [Integer] Only test entries from clusters with this many entries (default: 2)
  #
  # Returns hash with accuracy metrics and details
  def test_identifier_recovery(sample_size: 100, tag_type: nil, exclude_same_entry: true, min_cluster_size: 2)
    # Get entries to test
    query = @dictionary.entries.where.not(embedding: nil)

    # Filter by cluster size
    if min_cluster_size > 1
      multi_entry_ids = @dictionary.entries
        .where.not(embedding: nil)
        .group(:identifier)
        .having("COUNT(*) >= ?", min_cluster_size)
        .pluck(:identifier)

      query = query.where(identifier: multi_entry_ids)
    end

    # Filter by tag if specified
    if tag_type
      query = query.joins(:tags).where(tags: { value: tag_type })
    end

    # Sample entries
    test_entries = sample_size ? query.order("RANDOM()").limit(sample_size) : query

    results = []
    correct_count = 0

    test_entries.each do |entry|
      # Convert embedding to PostgreSQL vector format
      embedding_vector = "[#{entry.embedding.join(',')}]"

      # Find most similar entry
      sql = <<~SQL
        SELECT
          e.id,
          e.identifier,
          e.label,
          t.value as tag,
          1.0 - (e.embedding <=> $1) AS similarity,
          e.embedding <=> $1 AS distance
        FROM entries e
        LEFT JOIN entry_tags et ON et.entry_id = e.id
        LEFT JOIN tags t ON t.id = et.tag_id
        WHERE e.dictionary_id = $2
          AND e.embedding IS NOT NULL
      SQL

      if exclude_same_entry
        sql += " AND e.id != $3\n"
        sql += "ORDER BY e.embedding <=> $1\nLIMIT 1;"
        params = [embedding_vector, @dictionary.id, entry.id]
      else
        sql += "ORDER BY e.embedding <=> $1\nLIMIT 1;"
        params = [embedding_vector, @dictionary.id]
      end

      most_similar = ActiveRecord::Base.connection.exec_query(sql, "find_most_similar", params).first

      if most_similar
        predicted_identifier = most_similar["identifier"]
        correct = (predicted_identifier == entry.identifier)
        correct_count += 1 if correct

        results << {
          query_entry: {
            id: entry.id,
            label: entry.label,
            identifier: entry.identifier,
            tag: entry.tags.first&.value
          },
          predicted_entry: {
            id: most_similar["id"],
            label: most_similar["label"],
            identifier: most_similar["identifier"],
            tag: most_similar["tag"]
          },
          similarity: most_similar["similarity"].to_f.round(4),
          distance: most_similar["distance"].to_f.round(4),
          correct: correct
        }
      end
    end

    total_tested = results.length
    accuracy = total_tested > 0 ? (correct_count.to_f / total_tested * 100).round(2) : 0

    # Calculate accuracy by tag type
    by_tag = results.group_by { |r| r[:query_entry][:tag] }.transform_values do |entries|
      correct = entries.count { |e| e[:correct] }
      total = entries.length
      {
        total: total,
        correct: correct,
        accuracy: total > 0 ? (correct.to_f / total * 100).round(2) : 0
      }
    end

    # Find examples of failures
    failures = results.select { |r| !r[:correct] }

    # Calculate similarity distribution
    correct_similarities = results.select { |r| r[:correct] }.map { |r| r[:similarity] }
    incorrect_similarities = results.select { |r| !r[:correct] }.map { |r| r[:similarity] }

    {
      total_tested: total_tested,
      correct: correct_count,
      incorrect: total_tested - correct_count,
      accuracy: accuracy,
      accuracy_by_tag: by_tag,
      similarity_stats: {
        correct: {
          count: correct_similarities.length,
          mean: correct_similarities.length > 0 ? (correct_similarities.sum / correct_similarities.length).round(4) : 0,
          min: correct_similarities.min&.round(4),
          max: correct_similarities.max&.round(4)
        },
        incorrect: {
          count: incorrect_similarities.length,
          mean: incorrect_similarities.length > 0 ? (incorrect_similarities.sum / incorrect_similarities.length).round(4) : 0,
          min: incorrect_similarities.min&.round(4),
          max: incorrect_similarities.max&.round(4)
        }
      },
      sample_failures: failures.first(10).map do |f|
        {
          query: "#{f[:query_entry][:label]} [#{f[:query_entry][:tag]}]",
          true_identifier: f[:query_entry][:identifier],
          predicted: "#{f[:predicted_entry][:label]} [#{f[:predicted_entry][:tag]}]",
          predicted_identifier: f[:predicted_entry][:identifier],
          similarity: f[:similarity]
        }
      end,
      all_results: results
    }
  end

  # Get statistics about identifier clusters
  # Shows how many identifiers have single vs multiple entries
  # and which are analyzable by semantic_distance_from_labels
  def identifier_statistics
    total_identifiers = @dictionary.entries.select(:identifier).distinct.count

    single_entry_ids = @dictionary.entries
      .group(:identifier)
      .having('COUNT(*) = 1')
      .count
      .size

    multi_entry_ids = total_identifiers - single_entry_ids

    # Identifiers with Label tag
    ids_with_label = @dictionary.entries
      .joins(:tags)
      .where(tags: { value: 'Label' })
      .select(:identifier)
      .distinct
      .count

    # Identifiers with synonym tags
    ids_with_synonyms = @dictionary.entries
      .joins(:tags)
      .where(tags: { value: ['ExactSynonym', 'RelatedSynonym', 'BroadSynonym'] })
      .select(:identifier)
      .distinct
      .count

    # Identifiers analyzable by semantic_distance_from_labels
    # (must have both Label AND at least one synonym entry)
    analyzable_for_distance = @dictionary.entries
      .joins(:tags)
      .where(tags: { value: 'Label' })
      .select(:identifier)
      .distinct
      .where(
        identifier: @dictionary.entries
          .joins(:tags)
          .where(tags: { value: ['ExactSynonym', 'RelatedSynonym', 'BroadSynonym'] })
          .select(:identifier)
          .distinct
      )
      .count

    {
      total_identifiers: total_identifiers,
      single_entry_identifiers: single_entry_ids,
      multi_entry_identifiers: multi_entry_ids,
      identifiers_with_label: ids_with_label,
      identifiers_with_synonyms: ids_with_synonyms,
      analyzable_by_semantic_distance_from_labels: analyzable_for_distance,
      label_only_identifiers: ids_with_label - analyzable_for_distance
    }
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
    results = {
      stage1_global: {},
      stage2_local: {},
      total_outliers: 0,
      dry_run: dry_run
    }

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
    # Only analyze entries that survived stage 1
    puts "\nStage 2: Detecting local outliers within identifier clusters..." if dry_run

    exclusion_clause = if global_outlier_ids.any?
      "AND e.id NOT IN (#{global_outlier_ids.join(',')})"
    else
      ""
    end

    sql_local = <<~SQL
      WITH cluster_entries AS (
        SELECT e.id, e.identifier, e.label, e.embedding
        FROM entries e
        WHERE e.dictionary_id = #{@dictionary.id}
          AND e.embedding IS NOT NULL
          #{exclusion_clause}
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
      currently_searchable = Entry.where(id: all_outlier_ids, searchable: true).count
      currently_unsearchable = all_outlier_ids.length - currently_searchable

      results[:would_mark_unsearchable] = currently_searchable
      results[:already_unsearchable] = currently_unsearchable

      puts "\nDRY RUN - No changes made" if dry_run
      puts "Total outliers: #{results[:total_outliers]}" if dry_run
      puts "  Stage 1 (global): #{global_outlier_ids.length}" if dry_run
      puts "  Stage 2 (local): #{local_outlier_ids.length}" if dry_run
      puts "  Would mark as non-searchable: #{currently_searchable}" if dry_run
    else
      updated = Entry.where(id: all_outlier_ids, searchable: true).update_all(searchable: false)
      already_unsearchable = all_outlier_ids.length - updated

      results[:marked_unsearchable] = updated
      results[:already_unsearchable] = already_unsearchable
      results[:remaining_searchable] = @dictionary.entries.where(searchable: true).count

      puts "\nCleaning complete!" if dry_run
      puts "  Marked as non-searchable: #{updated}" if dry_run
      puts "  Already non-searchable: #{already_unsearchable}" if dry_run
    end

    results
  end

  # Clean dictionary by marking origin-proximity outliers as non-searchable
  # This removes problematic entries (acronyms, DNA/protein terms) from semantic search
  # while preserving them in the database for reference.
  #
  # @param origin_terms [Array<String>] Terms representing PubMedBERT origin (default: ['DNA', 'protein'])
  # @param distance_threshold [Float] Maximum distance from origin to consider outlier (default: 0.75)
  # @param dry_run [Boolean] If true, only report what would be changed without modifying (default: true)
  #
  # Returns hash with statistics about cleaning operation
  def clean_by_origin_proximity(origin_terms: ['DNA', 'protein'], distance_threshold: 0.75, dry_run: true)
    # First detect outliers
    outliers = detect_origin_proximity_outliers(
      origin_terms: origin_terms,
      distance_threshold: distance_threshold,
      limit: nil
    )

    return { error: outliers[:error] } if outliers[:error]

    outlier_ids = outliers[:outliers].map { |o| o[:id] }

    stats = {
      total_entries: @dictionary.entries_num,
      outliers_found: outlier_ids.length,
      distribution: outliers[:distribution],
      dry_run: dry_run
    }

    if dry_run
      # Report what would be changed
      currently_searchable = Entry.where(id: outlier_ids, searchable: true).count
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
      # Actually mark as non-searchable
      updated = Entry.where(id: outlier_ids, searchable: true).update_all(searchable: false)
      already_unsearchable = outlier_ids.length - updated

      stats[:marked_unsearchable] = updated
      stats[:already_unsearchable] = already_unsearchable
      stats[:remaining_searchable] = @dictionary.entries.where(searchable: true).count
    end

    stats
  end

  # Detect global outliers based on proximity to PubMedBERT semantic origin
  # Identifies entries that are semantically too close to fundamental biology terms (DNA, protein)
  # rather than disease concepts, suggesting they may be acronyms or misclassified entries.
  #
  # @param origin_terms [Array<String>] Terms representing PubMedBERT origin (default: ['DNA', 'protein'])
  # @param distance_threshold [Float] Maximum distance from origin to consider outlier (default: 0.75)
  # @param limit [Integer] Maximum outliers to return (default: nil = all)
  #
  # Returns array of outlier entries with distances
  def detect_origin_proximity_outliers(origin_terms: ['DNA', 'protein'], distance_threshold: 0.75, limit: nil)
    # Fetch embeddings for origin terms
    origin_embeddings = origin_terms.map do |term|
      embedding = EmbeddingServer.fetch_embedding(term)
      next unless embedding
      { term: term, vector: "[#{embedding.map(&:to_f).join(',')}]" }
    end.compact

    return { error: "Could not fetch origin embeddings" } if origin_embeddings.empty?

    # Build SQL to find entries close to ANY origin term
    vector_conditions = origin_embeddings.map.with_index do |emb, idx|
      "e.embedding <=> $#{idx + 2}"
    end.join(', ')

    # Build column names for each origin term
    distance_columns = origin_embeddings.map.with_index do |emb, idx|
      term_safe = emb[:term].gsub(/[^a-zA-Z0-9]/, '_')
      "e.embedding <=> $#{idx + 2} AS #{term_safe}_distance"
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
          e.id,
          e.identifier,
          e.label,
          t.value as tag,
          #{distance_columns},
          LEAST(#{vector_conditions}) AS min_distance
        FROM entries e
        LEFT JOIN entry_tags et ON et.entry_id = e.id
        LEFT JOIN tags t ON t.id = et.tag_id
        WHERE e.dictionary_id = $1
          AND e.embedding IS NOT NULL
      )
      SELECT
        id,
        identifier,
        label,
        tag,
        #{distance_column_names},
        min_distance,
        CASE
          #{case_conditions}
        END as closest_origin
      FROM distances
      WHERE min_distance < $#{origin_embeddings.length + 2}
      ORDER BY min_distance
      #{limit ? "LIMIT #{limit}" : ''}
    SQL

    params = [@dictionary.id] + origin_embeddings.map { |emb| emb[:vector] } + [distance_threshold]
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
        tag: row['tag'],
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

  # Two-stage outlier removal: global outliers first, then local (cluster-based) outliers
  # Stage 1: Remove entries that are outliers in the global embedding space
  # Stage 2: For remaining entries, remove outliers within their identifier clusters (min 3 entries)
  #
  # @param global_z_threshold [Float] Z-score threshold for global outlier detection (default: 3.0)
  # @param local_z_threshold [Float] Z-score threshold for local/cluster outlier detection (default: 2.0)
  # @param min_cluster_size [Integer] Minimum cluster size for local outlier detection (default: 3)
  # @param dry_run [Boolean] If true, only report what would be removed without deleting (default: true)
  #
  # Returns hash with detailed statistics about outliers found and removed
  def remove_outliers_two_stage(global_z_threshold: 3.0, local_z_threshold: 2.0, min_cluster_size: 3, dry_run: true)
    results = {
      stage1_global: {},
      stage2_local: {},
      total_removed: 0,
      dry_run: dry_run
    }

    # STAGE 1: Global outlier detection
    # Calculate global centroid and identify outliers across entire dictionary
    puts "Stage 1: Detecting global outliers (z-score > #{global_z_threshold})..."

    sql_global = <<~SQL
      WITH all_entries AS (
        SELECT id, identifier, label, embedding
        FROM entries
        WHERE dictionary_id = #{@dictionary.id}
          AND embedding IS NOT NULL
      ),
      global_centroid AS (
        SELECT AVG(embedding) AS centroid_embedding
        FROM all_entries
      ),
      distances AS (
        SELECT
          e.id,
          e.identifier,
          e.label,
          e.embedding <=> gc.centroid_embedding AS distance
        FROM all_entries e
        CROSS JOIN global_centroid gc
      ),
      stats AS (
        SELECT
          AVG(distance) AS mean_distance,
          STDDEV(distance) AS stddev_distance
        FROM distances
      )
      SELECT
        d.id,
        d.identifier,
        d.label,
        d.distance,
        (d.distance - s.mean_distance) / NULLIF(s.stddev_distance, 0) AS z_score
      FROM distances d
      CROSS JOIN stats s
      WHERE (d.distance - s.mean_distance) / NULLIF(s.stddev_distance, 0) > #{global_z_threshold}
      ORDER BY z_score DESC;
    SQL

    global_outliers = ActiveRecord::Base.connection.exec_query(sql_global)

    results[:stage1_global] = {
      threshold: global_z_threshold,
      outliers_found: global_outliers.count,
      outlier_ids: global_outliers.map { |r| r['id'] },
      sample_outliers: global_outliers.first(10).map do |row|
        {
          id: row['id'],
          identifier: row['identifier'],
          label: row['label'],
          distance: row['distance'].to_f.round(6),
          z_score: row['z_score'].to_f.round(4)
        }
      end
    }

    puts "  Found #{global_outliers.count} global outliers"

    # Track IDs to exclude from stage 2
    global_outlier_ids = global_outliers.map { |r| r['id'] }

    # STAGE 2: Local (cluster-based) outlier detection
    # Only analyze entries that survived stage 1
    puts "Stage 2: Detecting local outliers within clusters (z-score > #{local_z_threshold}, min cluster size: #{min_cluster_size})..."

    exclusion_clause = global_outlier_ids.any? ? "AND e.id NOT IN (#{global_outlier_ids.join(',')})" : ""

    sql_local = <<~SQL
      WITH cluster_entries AS (
        SELECT e.id, e.identifier, e.label, e.embedding
        FROM entries e
        WHERE e.dictionary_id = #{@dictionary.id}
          AND e.embedding IS NOT NULL
          #{exclusion_clause}
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
        (d.distance - cs.mean_distance) / NULLIF(cs.stddev_distance, 0) AS z_score
      FROM distances d
      INNER JOIN cluster_stats cs ON d.identifier = cs.identifier
      WHERE (d.distance - cs.mean_distance) / NULLIF(cs.stddev_distance, 0) > #{local_z_threshold}
      ORDER BY z_score DESC;
    SQL

    local_outliers = ActiveRecord::Base.connection.exec_query(sql_local)

    results[:stage2_local] = {
      threshold: local_z_threshold,
      min_cluster_size: min_cluster_size,
      outliers_found: local_outliers.count,
      outlier_ids: local_outliers.map { |r| r['id'] },
      sample_outliers: local_outliers.first(10).map do |row|
        {
          id: row['id'],
          identifier: row['identifier'],
          label: row['label'],
          distance: row['distance'].to_f.round(6),
          z_score: row['z_score'].to_f.round(4)
        }
      end
    }

    puts "  Found #{local_outliers.count} local outliers"

    # Combine all outlier IDs
    all_outlier_ids = (global_outlier_ids + local_outliers.map { |r| r['id'] }).uniq
    results[:total_removed] = all_outlier_ids.count

    # Perform deletion if not dry run
    if dry_run
      puts "\nDRY RUN - No entries deleted"
      puts "Would remove #{results[:total_removed]} entries total:"
      puts "  Stage 1 (global): #{global_outliers.count}"
      puts "  Stage 2 (local): #{local_outliers.count}"
    else
      puts "\nRemoving #{results[:total_removed]} outlier entries..."

      # Delete in transaction
      ActiveRecord::Base.transaction do
        # Delete entry_tags first (foreign key constraint)
        EntryTag.where(entry_id: all_outlier_ids).delete_all

        # Delete entries
        deleted_count = Entry.where(id: all_outlier_ids).delete_all

        puts "  Deleted #{deleted_count} entries"
        results[:actually_deleted] = deleted_count
      end
    end

    results
  end
end
