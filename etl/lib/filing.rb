# frozen_string_literal: true

require "date"

# Work out when a disclosure was filed, as an ISO 8601 string of whatever
# precision the corpus supports: "2025-09-08", "2025-09" or "2025".
#
# Nothing in the drops states the filing date as a field, but three things
# point at it, in descending order of precision:
#
#   filename  the Commission names most files after the date, American style
#             ("8.23.12", "12.5.2012") or ISO ("2013-11-13", "2014-8-15")
#   stamp     "RECEIVED / STATE ETHICS COMMISSION / 2012 AUG 23 AM 10:59",
#             OCRed off the scan
#   folder    the drops are filed in per-year ("2012/") or per-month
#             ("09 September 2025/", "February 2026 Disclosures/") directories
#
# Filename dates can't be read on their own, because a section number runs
# into the date: "Bowman§6.8.23.12.pdf" is § 6 filed 8.23.12, but reads just
# as well as 6.8.23 followed by a stray 12.  So we take every date the name
# could contain, overlapping matches included, and keep the ones whose year
# matches the folder -- the one signal present on nearly every file.
#
# The three don't mean quite the same thing: the Commission sometimes names a
# file for the day it was signed and sometimes for the day it arrived, up to a
# few weeks later.  So `date` is the date the disclosure is filed under, not
# the date it was signed, and `date_source` says which signal it came from.
module Filing
  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
  MONTH_NAME = /(?:#{MONTHS.join("|")})[a-z]*/i

  # "2013-11-13", "2014-8-15"
  ISO = /\b((?:19|20)\d{2})[-.](\d{1,2})[-.](\d{1,2})\b/
  # "8.23.12", "12.5.2012", "9/12/25" -- month first
  US = %r{\b(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{2,4})\b}

  # The received stamp.  The time is what makes it a stamp rather than prose
  # or a column of OCRed numbers, so we insist on it, and match within one
  # line so a year and a month from different paragraphs can't pair up.
  STAMP = /\b((?:19|20)\d{2})[ \t]+(#{MONTH_NAME})[ \t]*-?[ \t]*(\d{1,2})[ \t]*[AP]M/i

  # "<drop>/Nathaniel Story Records Request/2012/..."
  FOLDER_YEAR = %r{/((?:19|20)\d{2})/}
  # "<drop>/Nathan Story Request 3.28.26/09 September 2025/..."
  FOLDER_MONTH = %r{/(?:\d{1,2}[ \t]+)?(#{MONTH_NAME})[ \t]+((?:19|20)\d{2})}

  # Enough to throw out docket numbers ("20-12-2814" is not December 2814).
  YEARS = (1990..2099)

  # A stamp more than a year off the folder is an OCR misread, not a filing.
  STAMP_SLACK = 1

  def self.of(filenames, path, text)
    year, month = folder(path)
    stamp = stamp_date(text)

    if (date = filename_date(filenames, year, month, stamp))
      { date: date.iso8601, date_source: "filename" }
    elsif stamp && (year.nil? || (stamp.year - year).abs <= STAMP_SLACK)
      { date: stamp.iso8601, date_source: "received_stamp" }
    elsif month
      { date: format("%04d-%02d", year, month), date_source: "folder" }
    elsif year
      { date: year.to_s, date_source: "folder" }
    else
      { date: nil, date_source: nil }
    end
  end

  # Every date the names could be read as, narrowed to the folder's year and,
  # where the folder names a month and any candidate agrees, to that month.
  # Copies of one PDF are sometimes filed under dates a day or two apart, so
  # prefer the reading nearest the stamp, and failing that the earliest.
  def self.filename_date(filenames, year, month, stamp)
    dates = filenames.flat_map { |f| candidates(File.basename(f, ".*")) }.uniq
    dates = dates.select { |d| d.year == year } if year
    dates = dates.select { |d| d.month == month } if month && dates.any? { |d| d.month == month }
    dates.min_by { |d| [stamp ? (d - stamp).abs : 0, d] }
  end

  def self.candidates(stem)
    iso = scan_all(stem, ISO).map { |y, m, d| date(y, m, d) }
    us = scan_all(stem, US).map { |m, d, y| date(y, m, d) }
    (iso + us).compact
  end

  # String#scan resumes after each match, so on "§6.8.23.12" it would find
  # "6.8.23" and never try "8.23.12".  Matching a lookahead instead consumes
  # nothing, leaving scan to step through a character at a time.
  def self.scan_all(str, regexp)
    str.scan(/(?=#{regexp})/)
  end

  def self.stamp_date(text)
    m = text.match(STAMP) or return nil
    date(m[1], month_number(m[2]), m[3])
  end

  def self.folder(path)
    if (m = path.match(FOLDER_MONTH))
      [m[2].to_i, month_number(m[1])]
    elsif (m = path.match(FOLDER_YEAR))
      [m[1].to_i, nil]
    else
      [nil, nil]
    end
  end

  def self.month_number(name)
    MONTHS.index(name[0, 3].downcase) + 1
  end

  # Two-digit years are all this century; the corpus starts in 2011.
  def self.date(year, month, day)
    y = year.to_i
    y += y < 50 ? 2000 : 1900 if year.to_s.length <= 2
    Date.new(y, month.to_i, day.to_i) if YEARS.cover?(y) && Date.valid_date?(y, month.to_i, day.to_i)
  end
end
