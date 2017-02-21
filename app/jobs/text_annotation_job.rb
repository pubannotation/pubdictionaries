class TextAnnotationJob < Struct.new(:texts, :filename, :dictionaries, :options)
	def perform
    begin
      annotator = TextAnnotator.new(dictionaries, options[:tokens_len_max], options[:threshold], options[:rich])
      results = texts.inject([]){|r, text| r << annotator.annotate(text)}

      File.write(TextAnnotator::RESULTS_PATH + filename + '.json', JSON.generate(results))
      File.delete(TextAnnotator::RESULTS_PATH + filename)
    rescue => e
      File.write(TextAnnotator::RESULTS_PATH + filename + '.json', JSON.generate({"message":e.message}))
      File.delete(TextAnnotator::RESULTS_PATH + filename)
    end
	end
end
