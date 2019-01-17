class TextAnnotator
  module Result
    class << self
      def setup_directory
        unless File.directory?(TextAnnotator::RESULTS_PATH)
          FileUtils.mkdir_p(TextAnnotator::RESULTS_PATH)
        end
      end
    end
  end
end