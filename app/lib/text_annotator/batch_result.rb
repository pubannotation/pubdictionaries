require 'fileutils'
require 'json'

class TextAnnotator
  class BatchResult
    PATH = "tmp/annotations/"

    attr_reader :name

    class << self
      def older_files(duration)
        to_delete = []
        Dir.foreach(PATH) do |filename|
          next if filename == '.' or filename == '..'
          filepath = to_path(filename)
          to_delete << filepath if Time.now - File.mtime(filepath) > duration
        end
        to_delete
      end

      def to_path(filename)
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
      self.class.to_path(@name + '.json')
    end

    private

    def new_file!
      setup_directory

      filename = "annotation-result-#{SecureRandom.uuid}"
      FileUtils.touch(self.class.to_path(filename))
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
      self.class.to_path(@name)
    end

    def annotations
      @annotations ||= JSON.parse(File.read(file_path), symbolize_names: true)
    end
  end
end