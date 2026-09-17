#!/usr/bin/env ruby
# frozen_string_literal: true

# Build output/pdfs/disclosures/: one hard link per line of output/pdfs.jsonl,
# named by its unique `filename` and pointing at its `original_path`.  This is
# the directory that gets synced to the R2 bucket, so a disclosure's PDF lives
# at disclosures/<filename> there.
#
# Hard links cost no disk space, but they need input/pdfs and output on the
# same filesystem.  Files in the directory that aren't in pdfs.jsonl (e.g. newly
# excluded PDFs) are removed.

require "fileutils"
require "json"
require "optparse"

opts = {
  pdf_dir: "input/pdfs",
  jsonl: "output/pdfs.jsonl",
  output_dir: "output/pdfs/disclosures",
}

OptionParser.new do |o|
  o.banner = "usage: pdfs_dir.rb [options]"
  o.on("--pdf-dir DIR") { |v| opts[:pdf_dir] = v }
  o.on("--jsonl FILE") { |v| opts[:jsonl] = v }
  o.on("--output-dir DIR") { |v| opts[:output_dir] = v }
end.parse!

FileUtils.mkdir_p(opts[:output_dir])

wanted = Set.new
linked = 0
File.foreach(opts[:jsonl]) do |line|
  record = JSON.parse(line)
  src = File.join(opts[:pdf_dir], record["original_path"])
  dest = File.join(opts[:output_dir], record["filename"])
  wanted << record["filename"]

  # already linked to the right file
  next if File.exist?(dest) && File.identical?(src, dest)

  FileUtils.ln(src, dest, force: true)
  linked += 1
end

removed = 0
Dir.children(opts[:output_dir]).each do |name|
  next if wanted.include?(name)

  FileUtils.rm(File.join(opts[:output_dir], name))
  removed += 1
end

warn "#{opts[:output_dir]}: #{wanted.size} PDFs, #{linked} linked, #{removed} removed"
