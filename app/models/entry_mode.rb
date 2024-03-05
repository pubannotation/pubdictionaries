class EntryMode
  MODE_GRAY  = 0
  MODE_WHITE = 1
  MODE_BLACK = 2
  MODE_ACTIVE = 3 # gray + white (for downloading)
  MODE_CUSTOM = 4 # white + black (for downloading)
  MODE_PATTERN = 5 # patterns (regular expressions)
  MODE_AUTO_EXPANDED = 6

  MODES = {
    MODE_GRAY  => 'gray',
    MODE_WHITE => 'white',
    MODE_BLACK => 'black',
    MODE_ACTIVE => 'active',
    MODE_CUSTOM => 'custom',
    MODE_PATTERN => 'pattern',
    MODE_AUTO_EXPANDED => 'auto expand'
  }.freeze

  def self.to_s(mode)
    MODES[mode] || ''
  end

end
