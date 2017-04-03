class TextAnnotationJob < Struct.new(:target, :filename, :dictionaries, :options)
  include StateManagement

	def perform
    begin
      annotator = TextAnnotator.new(dictionaries, options[:tokens_len_max], options[:threshold], options[:rich])

      results = if target.class == Array
        target.map do |t|
          r = annotator.annotate(t[:text])
          t[:denotations] = r[:denotations] if r[:denotations].present?
          t[:relations] = r[:relations] if r[:relations].present?
          t[:modifications] = r[:modifications] if r[:modifications].present?
          t
        end
      else
        r = annotator.annotate(target[:text])
        target[:denotations] = r[:denotations] if r[:denotations].present?
        target[:relations] = r[:relations] if r[:relations].present?
        target[:modifications] = r[:modifications] if r[:modifications].present?
        target
      end

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
