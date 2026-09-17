#!/usr/bin/env ruby
# frozen_string_literal: true

# Build output/pdfs.jsonl: one line per distinct PDF (by sha256), with the
# filenames it appeared under and the plain text of its OCR.
#
# The drops repeat documents -- the same file shows up under different names,
# years and drops -- so we key on the hash and collect every basename.  The
# fulltext and original_path come from the first copy (in path order) that has
# been OCRed.  PDFs with no OCR yet are skipped with a warning; rerun after
# `make ocr`.
#
# PDFs whose sha256 is listed in exclusions.yml are left out entirely.
#
# Each line also gets a unique `filename`: the longest original name, normalized,
# e.g. "Smith_John_disclosure_9.12.25.pdf".  Where different PDFs normalize to
# the same name, later ones (in path order) get _1, _2, ... appended.  See
# category.rb for the `category` field and filer.rb for `name`, `title` and
# `agency`.

require "cgi"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "parallel"
require "yaml"
require_relative "category"
require_relative "filer"

opts = {
  pdf_dir: "input/pdfs",
  ocr_dir: "input/ocr",
  output: "output/pdfs.jsonl",
  exclusions: "exclusions.yml",
}

OptionParser.new do |o|
  o.banner = "usage: pdfs_jsonl.rb [options]"
  o.on("--pdf-dir DIR") { |v| opts[:pdf_dir] = v }
  o.on("--ocr-dir DIR") { |v| opts[:ocr_dir] = v }
  o.on("--output FILE") { |v| opts[:output] = v }
  o.on("--exclusions FILE") { |v| opts[:exclusions] = v }
end.parse!

PDF_DIR = File.expand_path(opts[:pdf_dir])
OCR_DIR = File.expand_path(opts[:ocr_dir])
EXCLUSIONS = YAML.load_file(opts[:exclusions]).to_set

# Same layout ocr.rb writes: <pdf_dir>/<drop>/<rel>.pdf -> <ocr_dir>/<drop>/<rel>/<stem>.md
def ocr_markdown_path(pdf)
  rel = pdf.delete_prefix("#{PDF_DIR}/")
  File.join(OCR_DIR, rel.delete_suffix(File.extname(rel)), "#{File.basename(pdf, ".*")}.md")
end

BLOCK_TAGS = /<\/?(?:p|br|div|tr|table|thead|tbody|h\d|li|ul|ol)\b[^>]*>/i
CELL_TAGS = /<\/?(?:td|th)\b[^>]*>/i

# chandra's markdown is markdown with HTML tables and form widgets mixed in.
# Reduce it to words for the fulltext index.
def strip_tags(html)
  html
    .gsub(/<!--.*?-->/m, " ")
    .gsub(BLOCK_TAGS, "\n")
    .gsub(/<(?:br|hr)\b\/?(?!>)/i, "\n") # unclosed, e.g. "<br</td>"
    .gsub(CELL_TAGS, " ")
    .gsub(/<[^>]+>/, " ")
end

def plain_text(markdown)
  # Strip again after unescaping: some pages have entity-escaped markup
  # (&lt;br/&gt;) inside table cells.
  text = strip_tags(CGI.unescapeHTML(strip_tags(markdown)))
    .gsub(/^\s{0,3}#+\s+/, "")          # heading markers
    .gsub(/(\*\*|__)(.+?)\1/m, '\2')    # bold
    .gsub(/\\?\*{2,}/, "")             # unmatched bold markers
    .gsub(/!\[[^\]]*\]\([^)]*\)/, " ")  # images
    .gsub(/\[([^\]]*)\]\([^)]*\)/, '\1') # links
  text.lines.map { |l| l.gsub(/[ \t ]+/, " ").strip }
    .join("\n")
    .gsub(/\n{3,}/, "\n\n")
    .strip
end

# The longest original name, reduced to ASCII letters, digits, "_", "." and "-"
# so it's safe in URLs and shell commands.
def normalized_filename(filenames)
  name = filenames.max_by(&:length)
  stem = File.basename(name, ".*")
    .unicode_normalize(:nfd).gsub(/\p{Mn}/, "") # deburr: "Díaz" -> "Diaz"
    .gsub(/\s+/, "_")
    .gsub(/[^A-Za-z0-9_.-]/, "")
    .squeeze("_").sub(/\A[_.-]+/, "").delete_suffix("_") # no hidden files
  [stem.empty? ? "document" : stem, File.extname(name).downcase]
end

pdfs = Dir.glob(File.join(PDF_DIR, "*", "**", "*.pdf"), File::FNM_CASEFOLD).sort

docs = {} # sha256 => { filenames:, markdown: }
missing = []
excluded = 0

shas = Parallel.map(pdfs) { |pdf| Digest::SHA256.file(pdf).hexdigest }
pdfs.zip(shas).each do |pdf, sha|
  if EXCLUSIONS.include?(sha)
    excluded += 1
    next
  end

  doc = docs[sha] ||= { filenames: [], markdown: nil }
  name = File.basename(pdf)
  doc[:filenames] << name unless doc[:filenames].include?(name)

  next if doc[:markdown]

  md = ocr_markdown_path(pdf)
  if File.exist?(md)
    doc[:markdown] = md
    doc[:path] = pdf.delete_prefix("#{PDF_DIR}/")
  else
    missing << [pdf, sha]
  end
end

# a later copy of the same document may have been OCRed
missing = missing.filter_map { |pdf, sha| pdf unless docs[sha][:markdown] }
unless missing.empty?
  warn "skipping #{missing.size} PDF(s) with no OCR output (run `make ocr`):"
  missing.each { |pdf| warn "  #{pdf.delete_prefix("#{PDF_DIR}/")}" }
end

# Compare case-insensitively so the files can live on a case-insensitive
# filesystem; keep counting if "Foo_1.pdf" is itself taken.
taken = {}
docs.each_value do |doc|
  stem, ext = normalized_filename(doc[:filenames])
  filename = "#{stem}#{ext}"
  n = 0
  filename = "#{stem}_#{n += 1}#{ext}" while taken[filename.downcase]
  taken[filename.downcase] = true
  doc[:filename] = filename
end

FileUtils.mkdir_p(File.dirname(opts[:output]))
tmp = "#{opts[:output]}.tmp"
# The text cleanup and regex matching are CPU-bound, so spread them across
# processes (threads would just queue up behind the GVL).  Parallel.map keeps
# the input order.
lines = Parallel.map(docs.select { |_, doc| doc[:markdown] }) do |sha, doc|
  fulltext = plain_text(File.read(doc[:markdown], encoding: "UTF-8"))
  JSON.generate(
    filename: doc[:filename],
    category: Category.of(fulltext),
    original_filenames: doc[:filenames],
    original_path: doc[:path],
    sha256sum: sha,
    fulltext: fulltext,
    **Filer.of(fulltext).slice(:name, :title, :agency),
  )
end
File.open(tmp, "w") { |f| f.puts(lines) }
written = lines.size
File.rename(tmp, opts[:output])

puts "#{pdfs.size} PDF(s), #{excluded} excluded, #{docs.size} distinct, #{written} written to #{opts[:output]}"
