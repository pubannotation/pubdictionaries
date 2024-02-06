require_relative './test_helper'

class TextAnnotator
  class TestBatchResult < Test::Unit::TestCase
    class << self
      def shutdown
        Dir.foreach(BatchResult::PATH) do |f|
          fn = File.join(BatchResult::PATH, f)
          File.delete(fn) if f != '.' && f != '..'
        end
      end
    end

    setup do
      Dir.mkdir BatchResult::PATH unless Dir.exist? BatchResult::PATH
    end

    sub_test_case 'describe self.old_files' do
      setup do
        # Create a file older than 0 seconds
        BatchResult.new(nil, 1).save!({})
      end

      test 'detect old files ' do
        files = BatchResult.older_files 0
        assert_not_empty files
      end
    end

    sub_test_case 'describe initializer' do
      sub_test_case 'without parameter' do
        setup do
          @result = BatchResult.new nil, 1
        end

        test 'generate new name' do
          assert_not_empty(@result.filename)
        end
      end

      sub_test_case 'specify name with parameter' do
        setup do
          @result = BatchResult.new('filename')
        end

        test 'set name according to parameter ' do
          assert_equal('filename', @result.filename)
        end
      end
    end

    sub_test_case 'describe file_path' do
      setup do
        @result = BatchResult.new(nil, 1)
      end

      test 'return json file path' do
        assert_equal(BatchResult.to_path(@result.filename), @result.file_path)
      end
    end

    sub_test_case 'describe save!' do
      setup do
        @result = BatchResult.new nil, 1
        @result.save!({})
      end

      test 'save hash as json' do
        assert_equal({}, JSON.parse(File.read(@result.file_path)))
      end
    end

    sub_test_case 'describe status' do
      setup do
        @result = BatchResult.new nil, 1
      end

      sub_test_case 'initially' do
        test 'status is queued' do
          assert_equal(:not_found, @result.status)
        end
      end

      sub_test_case 'when one or more texts are saved' do
        setup do
          @result.save!([{text: 'text'}])
        end

        test 'status is success' do
          assert_equal(:success, @result.status)
        end
      end

      sub_test_case 'when unexpected data saved' do
        setup do
          @result.save!("unexpected data")
        end

        test 'status is error' do
          assert_equal(:error, @result.status)
        end
      end
    end
  end
end
