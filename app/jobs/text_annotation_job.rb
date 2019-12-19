class TextAnnotationJob < Struct.new(:targets, :dictionaries, :options)
  include StateManagement

	def perform
    begin
      raise ArgumentError, "Annotation targets have to be in an array." unless targets.class == Array

      if @job
        @job.update_attribute(:num_items, targets.length)
        @job.update_attribute(:num_dones, 0)
      end

      annotator = TextAnnotator.new(dictionaries, options)

      i = 0
      annotations_col = targets.each_slice(100).inject([]) do |col, slice|
        col += annotator.annotate_batch(slice)
        @job.update_attribute(:num_dones, i += slice.length) if @job
        col
      end

      annotator.dispose

      if @job
        TextAnnotator::BatchResult.new(nil, @job.id).save!(annotations_col)
      end
    rescue => e
      if @job
        TextAnnotator::BatchResult.new(nil, @job.id).save!({"message":e.message})
      end
    end
	end
end
