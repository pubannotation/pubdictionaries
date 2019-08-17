class TextAnnotationJob < Struct.new(:targets, :filename, :dictionaries, :options)
  include StateManagement

	def perform
    begin
      raise ArgumentError, "The annotation targets have to be in an array." unless targets.class == Array
      annotator = TextAnnotator.new(dictionaries, options[:tokens_len_max], options[:threshold], options[:abbreviation], options[:longest], options[:superfluous], options[:verbose])

      annotations_col = targets.each_slice(100).inject([]) do |col, slice|
        col += annotator.annotate_batch(slice)
      end

      annotator.dispose

      TextAnnotator::BatchResult.new(filename).save!(annotations_col)
    rescue => e
      TextAnnotator::BatchResult.new(filename).save!({"message":e.message})
    end
	end

  def after
    @job.update_attribute(:ended_at, Time.now)
    @job.destroy
  end
end
