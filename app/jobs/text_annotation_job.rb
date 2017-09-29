class TextAnnotationJob < Struct.new(:target, :filename, :dictionaries, :options)
  include StateManagement

	def perform
    begin
      raise ArgumentError, "The annotation targets have to be in an array." unless targets.class == Array
      annotator = TextAnnotator.new(dictionaries, options[:tokens_len_max], options[:threshold], options[:rich])

      annotations_col = targets.each_slice(100).inject([]) do |col, slice|
        col += annotator.annotate_batch(slice)
      end

      annotator.done

      File.write(TextAnnotator::RESULTS_PATH + filename + '.json', JSON.generate(annotations_col))
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
