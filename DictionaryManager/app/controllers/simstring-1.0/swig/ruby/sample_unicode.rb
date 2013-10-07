#!/usr/bin/env ruby -Ku
# coding: utf-8

require File.join( File.dirname(__FILE__), '/simstring')

# Open a SimString database for writing with Unicode mode.
db = Simstring::Writer.new('sample_unicode.db', 3, false, true)

# Write a string, and close the database.
puts "Insert スパゲティ into the database"
db.insert('スパゲティ')
db.close()


# Open the database for reading.
db = Simstring::Reader.new('sample_unicode.db')

# Set a similarity measure and threshold.
db.measure = Simstring::Cosine
db.threshold = 0.6

# Use an 8-bit string in UTF-8 encoding.
puts "Searching with スパゲティー"
puts "Found: "
db.retrieve('スパゲティー').each do |entry|
	puts "   " + entry
end

