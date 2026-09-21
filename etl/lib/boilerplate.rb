# frozen_string_literal: true

require "set"

# Strip the form's own words from a set of filled-in copies of it.
#
# Every SFI in a drop is the same form -- the questions, instructions and page
# headers are identical from filer to filer, and they're most of the text: the
# answers are under a fifth of it.  Left in, every search for "real estate" or
# "spouse" would match every filer.  Rather than describe each form, we let the
# drop describe itself: a line that turns up in nearly every document is the
# form talking, not the filer.  The cut is at 95%, but little hangs on the
# exact number -- lines are either on (nearly) every copy or on a handful.
module Boilerplate
  THRESHOLD = 0.95
  # Below this many copies, "nearly every one" stops meaning anything -- with
  # one document, every line is in all of them.
  MIN_TEXTS = 20

  # Lines are compared with their whitespace squeezed, since pdftotext -layout
  # pads the same label differently depending on what's beside it.
  def self.key(line)
    line.gsub(/\s+/, " ").strip
  end

  # The lines present in at least THRESHOLD of the texts.  Each text counts a
  # line once however often it repeats it (e.g. a header on every page).
  def self.common_lines(texts)
    return Set.new if texts.size < MIN_TEXTS

    counts = Hash.new(0)
    texts.each do |text|
      text.each_line.map { |l| key(l) }.reject(&:empty?).uniq.each { |k| counts[k] += 1 }
    end
    min = (texts.size * THRESHOLD).ceil
    counts.select { |_, n| n >= min }.keys.to_set
  end

  def self.strip(text, common)
    text.each_line(chomp: true)
      .reject { |l| common.include?(key(l)) }
      .join("\n")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end
end
