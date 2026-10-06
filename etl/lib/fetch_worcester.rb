#!/usr/bin/env ruby
# frozen_string_literal: true

# Download every conflict of interest disclosure the City of Worcester posts
# on its open data portal (an ArcGIS Hub site) into <output dir>, ready to be
# zipped up as a drop.
#
# The portal tags each form "conflict of interest disclosure form", so we page
# through the Hub search API on that tag and fetch each item's PDF from ArcGIS.
#
# The PDFs' own names don't carry dates the way Filing reads them, but the
# titles do -- "Conflict of Interest Disclosure Form 2026/03/25 - Joseph Petty",
# or now and then "... – 20260713-Weekes-Walter" -- so each file is saved as
# "<year>/<yyyy-mm-dd> <name>.pdf", which Filing's FOLDER_YEAR and ISO patterns
# pick up.  A title we can't read keeps the item's own filename, under
# "undated/", with a warning.
#
# Files already in <output dir> are skipped, so a rerun only fetches new forms.

require "fileutils"
require "json"
require "open-uri"

SEARCH = "https://opendata.worcesterma.gov/api/search/v1/collections/all/items"
TAG = "conflict of interest disclosure form"
DATA = "https://www.arcgis.com/sharing/rest/content/items/%s/data"
PAGE = 100

# "2026/03/25 - Joseph Petty"
SLASHED = %r{(\d{4})/(\d{2})/(\d{2})\s*-\s*(.+)\z}
# "20260713-Weekes-Walter": last name, then first
COMPACT = /(\d{4})(\d{2})(\d{2})-([^-]+)-(.+)\z/

abort "usage: fetch_worcester.rb <output dir>" unless ARGV.size == 1
out_dir = ARGV[0]

def items
  Enumerator.new do |y|
    start = 1
    loop do
      query = URI.encode_www_form(filter: "tags='#{TAG}'", limit: PAGE, startindex: start)
      page = JSON.parse(URI.open("#{SEARCH}?#{query}").read)
      page["features"].each { |f| y << f }
      break if page["features"].size < PAGE

      start += PAGE
    end
  end
end

def path_for(props)
  title = props["title"].strip
  if (m = title.match(SLASHED))
    year, month, day, name = m.captures
  elsif (m = title.match(COMPACT))
    year, month, day, last, first = m.captures
    name = "#{first.tr("-", " ")} #{last}"
  else
    warn "can't read a date and name from #{title.inspect}"
    return File.join("undated", props["name"])
  end
  name = name.strip.delete("/")
  File.join(year, "#{year}-#{month}-#{day} #{name}.pdf")
end

seen = Hash.new(0)
fetched = skipped = 0
items.each do |f|
  rel = path_for(f["properties"])
  # two forms from the same person on the same day
  if (seen[rel] += 1) > 1
    rel = rel.sub(/\.pdf\z/i, " (#{seen[rel]}).pdf")
  end
  dest = File.join(out_dir, rel)

  if File.exist?(dest)
    skipped += 1
    next
  end

  FileUtils.mkdir_p(File.dirname(dest))
  data = URI.open(format(DATA, f["id"]), &:read)
  File.binwrite("#{dest}.part", data)
  File.rename("#{dest}.part", dest)
  fetched += 1
end

warn "#{out_dir}: #{fetched} fetched, #{skipped} already there"
