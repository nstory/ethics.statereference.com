#!/usr/bin/env ruby
# frozen_string_literal: true

# Build output/metadata.json: what the site needs to know about the corpus as
# a whole, as opposed to pdfs.jsonl's line per document.
#
# Right now that's just the drops -- one entry per zip in input/drops, with the
# date parsed out of its name -- which is where the site's "current through"
# date comes from.  Drops are named YYYY-MM-DD-<agency>.zip (see README.md); a
# zip that isn't is an error rather than a drop with no date, since it would
# quietly leave the corpus looking older than it is.

require "date"
require "fileutils"
require "json"
require "optparse"

opts = {
  drop_dir: "input/drops",
  output: "output/metadata.json",
}

OptionParser.new do |o|
  o.banner = "usage: metadata_json.rb [options]"
  o.on("--drop-dir DIR") { |v| opts[:drop_dir] = v }
  o.on("--output FILE") { |v| opts[:output] = v }
end.parse!

DROP_NAME = /\A(\d{4})-(\d{2})-(\d{2})-.+\.zip\z/

# sorted by name, which is chronological given the date prefix
drops = Dir.glob(File.join(opts[:drop_dir], "*.zip")).map { |p| File.basename(p) }.sort.map do |filename|
  match = DROP_NAME.match(filename) or
    abort "#{opts[:drop_dir]}/#{filename}: not named YYYY-MM-DD-<agency>.zip"
  date = begin
    Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
  rescue Date::Error
    abort "#{opts[:drop_dir]}/#{filename}: #{match[1]}-#{match[2]}-#{match[3]} is not a date"
  end

  { filename: filename, date: date.iso8601 }
end

FileUtils.mkdir_p(File.dirname(opts[:output]))
tmp = "#{opts[:output]}.tmp"
File.write(tmp, "#{JSON.pretty_generate(drops: drops)}\n")
File.rename(tmp, opts[:output])

puts "#{drops.size} drop(s) written to #{opts[:output]}"
