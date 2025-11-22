# One-time job to create persistent semantic tables for existing dictionaries
# that have embeddings populated but no semantic table yet.
#
# Usage:
#   CreateSemanticTablesJob.perform_later
#   # or synchronously:
#   CreateSemanticTablesJob.perform_now
#
class CreateSemanticTablesJob < ApplicationJob
  queue_as :default

  def perform
    dictionaries = Dictionary.where(has_semantic_table: false)
    total = dictionaries.count
    created = 0
    skipped = 0
    failed = 0

    Rails.logger.info "CreateSemanticTablesJob: Processing #{total} dictionaries without semantic tables"

    dictionaries.find_each do |dict|
      unless dict.embeddings_populated?
        Rails.logger.debug "Skipping #{dict.name} - no embeddings"
        skipped += 1
        next
      end

      begin
        Rails.logger.info "Creating semantic table for #{dict.name} (id: #{dict.id})..."
        dict.rebuild_semantic_table!
        created += 1
        Rails.logger.info "Created semantic table for #{dict.name}"
      rescue => e
        failed += 1
        Rails.logger.error "Failed to create semantic table for #{dict.name}: #{e.message}"
      end
    end

    summary = "CreateSemanticTablesJob completed: #{created} created, #{skipped} skipped (no embeddings), #{failed} failed"
    Rails.logger.info summary
    summary
  end
end
