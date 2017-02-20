class TextAnnotationJob < Struct.new(:targets, :annotator, :filename)
	def perform
    begin
      results = []
      targets.each_with_index do |target, i|
        results << annotator.annotate(target)
      end

      File.write(TextAnnotator::RESULTS_PATH + filename + '.json', JSON.generate(results))
      File.delete(TextAnnotator::RESULTS_PATH + filename)
    rescue => e
      File.write(TextAnnotator::RESULTS_PATH + filename + '.json', JSON.generate({"message":e.message}))
      File.delete(TextAnnotator::RESULTS_PATH + filename)
    end
	end
end
