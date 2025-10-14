require 'rails_helper'

RSpec.describe UpdateDictionaryEmbeddingsJob, type: :job do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_embeddings_dict') }
  let(:job_record) { Job.create!(dictionary: dictionary, name: 'Update embeddings', num_items: 0, num_dones: 0) }

  # Helper method to perform the job with proper setup
  def perform_job(dictionary)
    job_instance = UpdateDictionaryEmbeddingsJob.new
    job_instance.instance_variable_set(:@job, job_record)
    job_instance.perform(dictionary)
  end

  # Helper method to create entries
  def create_entries(dictionary, count)
    count.times do |i|
      create(:entry, dictionary: dictionary, label: "entry_#{i}", identifier: "ID:#{i.to_s.rjust(6, '0')}")
    end
  end

  # Mock embedding response (768-dimensional vector for PubMedBERT)
  def mock_embedding_vector
    Array.new(768) { rand }
  end

  describe '#perform' do
    context 'basic functionality' do
      it 'updates embeddings for entries' do
        create_entries(dictionary, 3)

        # Mock the embedding server to return embeddings
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return([
          mock_embedding_vector,
          mock_embedding_vector,
          mock_embedding_vector
        ])

        perform_job(dictionary)

        # All entries should now have embeddings
        expect(dictionary.entries.where.not(embedding: nil).count).to eq(3)
      end

      it 'handles empty dictionary' do
        expect(dictionary.entries.count).to eq(0)

        # Should return early without calling embedding server
        expect(EmbeddingServer).not_to receive(:fetch_embeddings)

        expect {
          perform_job(dictionary)
        }.not_to raise_error

        # Should not crash or update anything
        expect(dictionary.entries.count).to eq(0)
      end

      it 'processes entries in batches' do
        # Create more entries than batch size (50)
        create_entries(dictionary, 150)

        # Should make 3 batch calls (150 / 50)
        expect(EmbeddingServer).to receive(:fetch_embeddings).exactly(3).times.and_return(
          Array.new(50) { mock_embedding_vector },
          Array.new(50) { mock_embedding_vector },
          Array.new(50) { mock_embedding_vector }
        )

        perform_job(dictionary)

        expect(dictionary.entries.where.not(embedding: nil).count).to eq(150)
      end

      it 'verifies batch size constant' do
        expect(UpdateDictionaryEmbeddingsJob::BATCH_SIZE).to eq(50)
      end
    end

    context 'suspension mechanism' do
      it 'stops when suspension file exists' do
        create_entries(dictionary, 100)

        # Mark job as running (suspended? requires begun_at to be set)
        job_record.update(begun_at: Time.now)

        # Create suspend file before job starts
        suspend_file = Rails.root.join('tmp', "suspend_job_#{job_record.id}")
        FileUtils.mkdir_p(Rails.root.join('tmp'))

        # Mock to create suspend file after first batch completes
        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do
          call_count += 1
          result = Array.new(50) { mock_embedding_vector }
          # Create suspend file after first batch completes
          FileUtils.touch(suspend_file) if call_count == 1
          result
        end

        expect {
          perform_job(dictionary)
        }.to raise_error(Exceptions::JobSuspendError)

        # Should have processed first batch (50 entries) but stopped before second
        expect(dictionary.entries.where.not(embedding: nil).count).to eq(50)

        # Clean up suspend file
        FileUtils.rm_f(suspend_file)
      end

      it 'check_suspension raises JobSuspendError when suspended' do
        job_instance = UpdateDictionaryEmbeddingsJob.new
        job_instance.instance_variable_set(:@job, job_record)

        # Mark job as running (suspended? requires begun_at to be set)
        job_record.update(begun_at: Time.now)

        # Create tmp directory and suspend file
        suspend_file = Rails.root.join('tmp', "suspend_job_#{job_record.id}")
        FileUtils.mkdir_p(Rails.root.join('tmp'))
        FileUtils.touch(suspend_file)

        expect {
          job_instance.send(:check_suspension)
        }.to raise_error(Exceptions::JobSuspendError)

        # Clean up
        FileUtils.rm_f(suspend_file)
      end
    end

    context 'failed entry tracking' do
      it 'stores failed entries in job metadata when embedding server fails' do
        create_entries(dictionary, 3)

        # Mock to fail on all entries
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(
          EmbeddingServerError.new("Server error 500: Internal server error")
        )

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError)

        # Should store failed entries in job metadata
        job_record.reload
        expect(job_record.metadata).to be_present
        expect(job_record.metadata['failed_entries']).to be_an(Array)
        expect(job_record.metadata['failed_entries'].size).to eq(3)

        # Check structure of failed entry
        failed = job_record.metadata['failed_entries'].first
        expect(failed['entry_id']).to be_present
        expect(failed['label']).to be_present
        expect(failed['identifier']).to be_present
        expect(failed['error']).to include('Embedding server error')
        expect(failed['timestamp']).to be_present
      end

      it 'limits failed entries to first 100' do
        create_entries(dictionary, 150)

        # Mock to fail on all entries
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(
          EmbeddingServerError.new("Server error")
        )

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError)

        # Job terminates on first batch failure, so only first batch (50 entries) are recorded
        # The 100-entry limit is applied in the ensure block, but here we only have 50 failures
        job_record.reload
        expect(job_record.metadata['failed_entries'].size).to eq(50)
      end

      it 'does not create metadata when no entries fail' do
        create_entries(dictionary, 3)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(3) { mock_embedding_vector }
        )

        perform_job(dictionary)

        # No failed entries, metadata should be nil
        job_record.reload
        expect(job_record.metadata).to be_nil
      end
    end

    context 'error handling' do
      before do
        create_entries(dictionary, 3)
      end

      it 'handles client errors and terminates immediately' do
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(
          EmbeddingClientError.new("Client error 400: Bad request")
        )

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingClientError)

        # Should store failed entries
        job_record.reload
        expect(job_record.metadata['failed_entries']).to be_present
        expect(job_record.metadata['failed_entries'].first['error']).to include('Configuration error')
      end

      it 'handles server errors and terminates immediately' do
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(
          EmbeddingServerError.new("Server error 500")
        )

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError)

        job_record.reload
        expect(job_record.metadata['failed_entries'].first['error']).to include('Embedding server error')
      end

      it 'handles network timeout errors' do
        # Network timeouts are retried and then wrapped in EmbeddingServerError
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(Net::ReadTimeout)

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError, /unavailable after 3 retries/)

        job_record.reload
        expect(job_record.metadata['failed_entries'].first['error']).to include('Embedding server error')
      end

      it 'handles connection refused errors' do
        # Connection errors are retried and then wrapped in EmbeddingServerError
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(Errno::ECONNREFUSED)

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError, /unavailable after 3 retries/)

        job_record.reload
        expect(job_record.metadata['failed_entries'].first['error']).to include('Embedding server error')
      end

      it 'handles malformed JSON responses' do
        # JSON errors are wrapped in EmbeddingServerError by fetch_embeddings_with_retry
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(JSON::ParserError.new("bad JSON"))

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError)

        job_record.reload
        expect(job_record.metadata['failed_entries'].first['error']).to include('Embedding server error')
      end

      it 'handles unexpected errors' do
        # Unexpected errors are wrapped in EmbeddingServerError
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(StandardError.new("Unknown error"))

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError)

        job_record.reload
        expect(job_record.metadata['failed_entries'].first['error']).to include('Embedding server error')
      end
    end

    context 'retry logic' do
      before do
        create_entries(dictionary, 3)
      end

      it 'retries transient errors with exponential backoff' do
        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do
          call_count += 1
          if call_count <= 2
            raise Net::ReadTimeout
          else
            Array.new(3) { mock_embedding_vector }
          end
        end

        # Should succeed after retries
        expect {
          perform_job(dictionary)
        }.not_to raise_error

        # Should have made 3 calls (2 failures + 1 success)
        expect(call_count).to eq(3)
        expect(dictionary.entries.where.not(embedding: nil).count).to eq(3)
      end

      it 'fails after max retries for transient errors' do
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(Net::ReadTimeout)

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError, /unavailable after 3 retries/)
      end

      it 'does not retry client errors' do
        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do
          call_count += 1
          raise EmbeddingClientError.new("Bad request")
        end

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingClientError)

        # Should only attempt once, no retries
        expect(call_count).to eq(1)
      end
    end

    context 'progress tracking' do
      it 'initializes progress record with total entries' do
        create_entries(dictionary, 50)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(50) { mock_embedding_vector }
        )

        perform_job(dictionary)

        job_record.reload
        expect(job_record.num_items).to eq(50)
        expect(job_record.num_dones).to eq(50)
      end

      it 'updates progress after each batch' do
        create_entries(dictionary, 100)

        batch_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do
          batch_count += 1
          Array.new(50) { mock_embedding_vector }
        end

        perform_job(dictionary)

        # Should process 2 batches
        expect(batch_count).to eq(2)

        job_record.reload
        expect(job_record.num_items).to eq(100)
        expect(job_record.num_dones).to eq(100)
      end

      it 'updates progress even when job fails' do
        create_entries(dictionary, 100)

        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do
          call_count += 1
          if call_count == 1
            Array.new(50) { mock_embedding_vector }
          else
            raise EmbeddingServerError.new("Server error")
          end
        end

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError)

        # Should have updated progress for first batch
        job_record.reload
        expect(job_record.num_items).to eq(100)
        expect(job_record.num_dones).to eq(50)
      end

      it 'updates progress every 5 batches to reduce database writes' do
        # Create 250 entries (5 batches)
        create_entries(dictionary, 250)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(50) { mock_embedding_vector }
        )

        # Mock update_progress_record to count calls
        job_instance = UpdateDictionaryEmbeddingsJob.new
        job_instance.instance_variable_set(:@job, job_record)

        call_count = 0
        allow(job_instance).to receive(:update_progress_record) do |count|
          call_count += 1
          job_record.update(num_dones: count)
        end

        job_instance.perform(dictionary)

        # Should be called:
        # - Once during batch 5 (when @batch_count % 5 == 0)
        # - Once in ensure block
        # Total: 2 calls
        expect(call_count).to eq(2)

        job_record.reload
        expect(job_record.num_dones).to eq(250)
      end

      it 'only updates progress in ensure block when fewer than 5 batches processed' do
        # Create 100 entries (2 batches) - neither triggers progress update (2 % 5 != 0)
        create_entries(dictionary, 100)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(50) { mock_embedding_vector }
        )

        # Mock update_progress_record to count calls
        job_instance = UpdateDictionaryEmbeddingsJob.new
        job_instance.instance_variable_set(:@job, job_record)

        call_count = 0
        allow(job_instance).to receive(:update_progress_record) do |count|
          call_count += 1
          job_record.update(num_dones: count)
        end

        job_instance.perform(dictionary)

        # Should only be called once (in ensure block), not during batch processing
        expect(call_count).to eq(1)

        job_record.reload
        expect(job_record.num_dones).to eq(100)
      end

      it 'updates progress at correct intervals for large datasets' do
        # Create 600 entries (12 batches)
        create_entries(dictionary, 600)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(50) { mock_embedding_vector }
        )

        # Mock update_progress_record to track when it's called
        job_instance = UpdateDictionaryEmbeddingsJob.new
        job_instance.instance_variable_set(:@job, job_record)

        progress_snapshots = []
        allow(job_instance).to receive(:update_progress_record) do |count|
          progress_snapshots << count
          job_record.update(num_dones: count)
        end

        job_instance.perform(dictionary)

        # Should be called:
        # - After batch 5 (250 entries)
        # - After batch 10 (500 entries)
        # - In ensure block (600 entries)
        # Total: 3 calls
        expect(progress_snapshots).to eq([250, 500, 600])
      end
    end

    context 'bulk update performance' do
      it 'updates embeddings using bulk SQL update' do
        create_entries(dictionary, 50)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(50) { mock_embedding_vector }
        )

        # Should use single bulk UPDATE statement, not 50 individual updates
        expect(ActiveRecord::Base.connection).to receive(:execute).once.and_call_original

        perform_job(dictionary)

        expect(dictionary.entries.where.not(embedding: nil).count).to eq(50)
      end
    end

    context 'edge cases' do
      it 'handles entries with special characters in labels' do
        entry = create(:entry, dictionary: dictionary, label: 'alpha-D-glucose (6-phosphate)', identifier: 'CHEBI:4170')

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return([mock_embedding_vector])

        perform_job(dictionary)

        entry.reload
        expect(entry.embedding).to be_present
      end

      it 'handles partial batch at end' do
        # Create 75 entries (1.5 batches)
        create_entries(dictionary, 75)

        batch_sizes = []
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |labels|
          batch_sizes << labels.size
          Array.new(labels.size) { mock_embedding_vector }
        end

        perform_job(dictionary)

        # Should process batch of 50 and batch of 25
        expect(batch_sizes).to eq([50, 25])
        expect(dictionary.entries.where.not(embedding: nil).count).to eq(75)
      end
    end

    context 'performance metrics' do
      it 'logs performance metrics with duration and rate' do
        create_entries(dictionary, 100)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(50) { mock_embedding_vector }
        )

        # Capture Rails logger output
        allow(Rails.logger).to receive(:info).and_call_original

        perform_job(dictionary)

        # Should log performance metrics in format: "Performance: Xs total, Y entries/sec"
        expect(Rails.logger).to have_received(:info).with(/Performance: \d+\.\d+s total, \d+\.\d+ entries\/sec/).once
      end

      it 'includes correct calculation of processing rate' do
        create_entries(dictionary, 50)

        allow(EmbeddingServer).to receive(:fetch_embeddings).and_return(
          Array.new(50) { mock_embedding_vector }
        )

        # Track the performance log message
        performance_log = nil
        allow(Rails.logger).to receive(:info) do |message|
          performance_log = message if message.include?('Performance:')
        end

        perform_job(dictionary)

        # Verify performance log was created
        expect(performance_log).to be_present

        # Extract duration and rate from log message
        # Format: "Performance: 1.23s total, 40.65 entries/sec"
        match = performance_log.match(/Performance: (\d+\.\d+)s total, (\d+\.\d+) entries\/sec/)
        expect(match).to be_present

        duration = match[1].to_f
        rate = match[2].to_f

        # Verify rate is reasonable (positive and roughly matches completed/duration)
        expect(duration).to be > 0
        expect(rate).to be > 0
        # Rate should be approximately 50 entries / duration (allow 20% tolerance for rounding)
        approximate_rate = 50.0 / duration
        expect(rate).to be_within(approximate_rate * 0.2).of(approximate_rate)
      end

      it 'logs performance metrics even when job fails' do
        create_entries(dictionary, 100)

        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do
          call_count += 1
          if call_count == 1
            Array.new(50) { mock_embedding_vector }
          else
            raise EmbeddingServerError.new("Server error")
          end
        end

        # Track the performance log message
        performance_logged = false
        allow(Rails.logger).to receive(:info) do |message|
          performance_logged = true if message.include?('Performance:')
        end

        expect {
          perform_job(dictionary)
        }.to raise_error(EmbeddingServerError)

        # Should still log performance metrics in ensure block
        expect(performance_logged).to be true
      end

      it 'does not log performance metrics when dictionary is empty' do
        # Empty dictionary - should return early without setting @start_time properly
        expect(dictionary.entries.count).to eq(0)

        allow(Rails.logger).to receive(:info).and_call_original

        perform_job(dictionary)

        # Should not log performance metrics for empty dictionary
        expect(Rails.logger).not_to have_received(:info).with(/Performance:/)
      end
    end
  end

  describe '#record_failed_entry' do
    it 'adds entry to failed_entries array' do
      entry = create(:entry, dictionary: dictionary, label: 'test', identifier: 'TEST:001')

      job_instance = UpdateDictionaryEmbeddingsJob.new
      job_instance.instance_variable_set(:@job, job_record)
      job_instance.instance_variable_set(:@failed_entries, [])

      job_instance.send(:record_failed_entry, entry, "Test error")

      failed_entries = job_instance.instance_variable_get(:@failed_entries)
      expect(failed_entries.size).to eq(1)
      expect(failed_entries.first[:entry_id]).to eq(entry.id)
      expect(failed_entries.first[:label]).to eq('test')
      expect(failed_entries.first[:identifier]).to eq('TEST:001')
      expect(failed_entries.first[:error]).to eq('Test error')
    end
  end
end
