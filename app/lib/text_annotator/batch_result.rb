require 'fileutils'
require 'json'

class TextAnnotator
  class BatchResult
    PATH = "tmp/annotations/"

    attr_reader :name

    class << self
      def old_files
        to_delete = []
        Dir.foreach(PATH) do |filename|
          next if filename == '.' or filename == '..'
          filepath = result_file(filename)
          to_delete << filepath if Time.now - File.mtime(filepath) > 1.day
        end
        to_delete
      end

      def result_file(filename)
        PATH + filename
      end
    end

    def initialize(filename = nil)
      filename ||= new_file!
      @name = filename
    end

    def save!(result)
      File.write(file_path, JSON.generate(result))
      File.delete(temp_file_path)
    end

    def status
      if complete?
        if success?
          :success
        else
          :error
        end
      else
        if queued?
          :queued
        else
          :not_found
        end
      end
    end

    def file_path
      self.class.result_file(@name + '.json')
    end

    private

    def new_file!
      setup_directory

      filename = "annotation-result-#{SecureRandom.uuid}"
      FileUtils.touch(self.class.result_file(filename))
      filename
    end

    def setup_directory
      unless File.directory?(PATH)
        FileUtils.mkdir_p(PATH)
      end
    end

    def complete?
      File.exist?(file_path)
    end

    def success?
      annotations

      if annotations.class == Array
        annotations.first.has_key?(:text)
      else
        annotations.has_key?(:text)
      end
    end

    def queued?
      File.exist?(temp_file_path)
    end

    def temp_file_path
      self.class.result_file(@name)
    end

    def annotations
      @annotations ||= JSON.parse(File.read(file_path), symbolize_names: true)
    end
  end
end