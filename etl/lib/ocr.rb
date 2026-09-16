#!/usr/bin/env ruby
# frozen_string_literal: true

# OCR every PDF under --pdf-dir that doesn't already have output under --ocr-dir.
#
# We pick the pending PDFs and hand them to lib/ocr_mlx.py as a manifest; that
# script loads chandra once and does the inference.  It writes each document
# straight to its final destination, so there's no staging step and no name
# mangling to undo -- two PDFs with the same basename in different year folders
# land in different output directories and never collide.

require "fileutils"
require "json"
require "optparse"
require "tmpdir"

opts = {
  pdf_dir: "input/pdfs",
  ocr_dir: "input/ocr",
  model: File.expand_path("../models/chandra-mlx-4bit", __dir__),
  batch_size: 8,
  limit: nil,
  dry_run: false,
}

OptionParser.new do |o|
  o.banner = "usage: ocr.rb [options]"
  o.on("--pdf-dir DIR")      { |v| opts[:pdf_dir] = v }
  o.on("--ocr-dir DIR")      { |v| opts[:ocr_dir] = v }
  o.on("--model DIR", "converted MLX model (see `make ocr-model`)") { |v| opts[:model] = v }
  o.on("--batch-size N", Integer, "pages per inference batch") { |v| opts[:batch_size] = v }
  o.on("--limit N", Integer, "only OCR the first N pending PDFs") { |v| opts[:limit] = v }
  o.on("--dry-run", "list what would be OCRed, then stop") { opts[:dry_run] = true }
end.parse!

PDF_DIR = File.expand_path(opts[:pdf_dir])
OCR_DIR = File.expand_path(opts[:ocr_dir])

# A PDF at <pdf_dir>/<drop>/<rel>.pdf gets OCRed into <ocr_dir>/<drop>/<rel>/.
# We keep <rel>'s subdirectories rather than flattening to the basename because
# basenames collide (91 of them in sec-2025-08-07 alone).
Job = Struct.new(:pdf, :dest_dir, :stem, keyword_init: true)

def stale?(pdf, dest_dir, stem)
  md = File.join(dest_dir, "#{stem}.md")
  return true unless File.exist?(md)
  File.mtime(md) < File.mtime(pdf)
end

pdfs = Dir.glob(File.join(PDF_DIR, "*", "**", "*.pdf"), File::FNM_CASEFOLD).sort

jobs = []
pdfs.each do |pdf|
  rel = pdf.delete_prefix("#{PDF_DIR}/")
  dest_dir = File.join(OCR_DIR, rel.delete_suffix(File.extname(rel)))
  stem = File.basename(pdf, ".*")
  next unless stale?(pdf, dest_dir, stem)

  jobs << Job.new(pdf: pdf, dest_dir: dest_dir, stem: stem)
end

jobs = jobs.first(opts[:limit]) if opts[:limit]

puts "#{pdfs.size} PDF(s) found, #{jobs.size} needing OCR"

if jobs.empty?
  puts "nothing to do"
  exit 0
end

if opts[:dry_run]
  jobs.each { |job| puts "  #{job.pdf.delete_prefix("#{PDF_DIR}/")}" }
  exit 0
end

unless File.directory?(opts[:model])
  abort "model not found at #{opts[:model]}; run `make ocr-model` first"
end

ok = false
Dir.mktmpdir("ocr-manifest") do |dir|
  manifest = File.join(dir, "jobs.json")
  File.write(manifest, JSON.generate(jobs.map(&:to_h)))

  cmd = [
    "uv", "run", "--quiet", "--python", "3.12",
    File.expand_path("ocr_mlx.py", __dir__),
    manifest,
    "--model", opts[:model],
    "--batch-size", opts[:batch_size].to_s,
  ]
  puts cmd.join(" ")
  ok = system(*cmd)
end

# ocr_mlx.py writes each document as it finishes and reports its own failures,
# so a non-zero exit still leaves completed work on disk.  Anything missing
# stays stale and gets retried on the next run.
unless ok
  warn "ocr_mlx.py exited non-zero; completed documents were still written"
  exit 1
end
