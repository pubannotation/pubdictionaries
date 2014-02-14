# file development_reload.rb
if Rails.env.development?
  ActionDispatch::Callbacks.after do
    Dir.entries("#{Rails.root}/app/controllers/text_annotator").each do |entry|
      load entry if entry =~ /.rb$/
    end
  end
end
