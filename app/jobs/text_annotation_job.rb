class TextAnnotationJob < Struct.new(:texts, :filename, :dictionaries, :options)
  include StateManagement

	def perform
    begin
      annotator = TextAnnotator.new(dictionaries, options[:tokens_len_max], options[:threshold], options[:rich])
      results = (texts.class == Array) ? texts.inject([]){|r, text| r << annotator.annotate(text)} : annotator.annotate(texts)

      File.write(TextAnnotator::RESULTS_PATH + filename + '.json', JSON.generate(results))
      File.delete(TextAnnotator::RESULTS_PATH + filename)
    rescue => e
      File.write(TextAnnotator::RESULTS_PATH + filename + '.json', JSON.generate({"message":e.message}))
      File.delete(TextAnnotator::RESULTS_PATH + filename)
    end
	end

  def after
    @job.update_attribute(:ended_at, Time.now)
    @job.destroy
  end
end
