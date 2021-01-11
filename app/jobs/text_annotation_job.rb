class TextAnnotationJob < Struct.new(:target, :dictionaries, :options)
  include StateManagement

	def perform
    begin
      single_target = false
      targets = if target.class == Array
        target
      else
        single_target = true
        [target]
      end

      if @job
        @job.update_attribute(:num_items, targets.length)
        @job.update_attribute(:num_dones, 0)
      end

      dictionaries.each{|dictionary| dictionary.compile! if dictionary.compilable?}

      annotator = TextAnnotator.new(dictionaries, options)

      i = 0
      annotation_result = []
      buffer = []
      buffer_size = 0
      targets.each_with_index do |t, i|
        t_size = t[:text].length
        if buffer.present? && (buffer_size + t_size > 100000)
          annotation_result += annotator.annotate_batch(buffer)
          @job.update_attribute(:num_dones, i) if @job
          buffer.clear
          buffer_size = 0
        end
        buffer << t
        buffer_size += t_size
      end

      unless buffer.empty?
        annotation_result += annotator.annotate_batch(buffer)
        @job.update_attribute(:num_dones, targets.length) if @job
      end

      annotation_result = annotation_result.first if single_target

      annotator.dispose

      if @job
        if options[:no_text]
          if annotation_result.class == Hash
            annotations_result.delete(:text)
          elsif annotation_result.respond_to?(:each)
            annotation_result.each{|ann| ann.delete(:text)}
          end
        end
        TextAnnotator::BatchResult.new(nil, @job.id).save!(annotation_result)
      end
    rescue => e
      if @job
        @job.update_attribute(:message, e.message)
      end
    end
	end
end
