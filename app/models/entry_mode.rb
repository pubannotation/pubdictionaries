class EntryMode
  GRAY  = 0
  WHITE = 1
  BLACK = 2
  ACTIVE = 3 # gray + white (for downloading)
  CUSTOM = 4 # white + black (for downloading)
  PATTERN = 5 # patterns (regular expressions)
  AUTO_EXPANDED = 6

  MODES = {
    GRAY  => 'gray',
    WHITE => 'white',
    BLACK => 'black',
    ACTIVE => 'active',
    CUSTOM => 'custom',
    PATTERN => 'pattern',
    AUTO_EXPANDED => 'auto expand'
  }.freeze

  def self.to_s(mode)
    MODES[mode] || ''
  end

end
