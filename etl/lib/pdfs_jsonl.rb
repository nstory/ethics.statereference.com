#!/usr/bin/env ruby
# frozen_string_literal: true

# Build output/pdfs.jsonl: one line per distinct PDF (by sha256), with the
# filenames it appeared under and the plain text of its OCR.
#
# The drops repeat documents -- the same file shows up under different names,
# years and drops -- so we key on the hash and collect every basename.  The
# fulltext and original_path come from the first copy (in path order) that has
# text, either chandra's <stem>.md or pdftotext's <stem>.txt (see ocr.rb).
# PDFs with neither yet are skipped with a warning; rerun after `make ocr`.
#
# PDFs whose sha256 is listed in exclusions.yml are left out entirely.
#
# Each line also gets a unique `filename`: the longest original name, normalized,
# e.g. "Smith_John_disclosure_9_12_25.pdf".  Where different PDFs normalize to
# the same name, later ones (in path order) get _1, _2, ... appended.
#
# `custodian` comes from metadata.yml, by the drop of original_path, and so
# does whether the PDF is a disclosure or an SFI (the drop's `kind`).
# Disclosures get category.rb's `category`, filing.rb's `date` and
# `date_source`, and filer.rb's `name`, `title` and `agency`.  SFIs get none
# of that: they come in many formats and we don't parse any of them, so their
# category is Category::SFI, their `date` is the drop's `year` (date_source
# "drop"), the rest is null, and their fulltext has the form's boilerplate
# stripped (see boilerplate.rb).

require "cgi"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "parallel"
require "yaml"
require_relative "boilerplate"
require_relative "category"
require_relative "drops"
require_relative "filer"
require_relative "filing"

opts = {
  pdf_dir: "input/pdfs",
  ocr_dir: "input/ocr",
  output: "output/pdfs.jsonl",
  exclusions: "exclusions.yml",
  metadata: "metadata.yml",
}

OptionParser.new do |o|
  o.banner = "usage: pdfs_jsonl.rb [options]"
  o.on("--pdf-dir DIR") { |v| opts[:pdf_dir] = v }
  o.on("--ocr-dir DIR") { |v| opts[:ocr_dir] = v }
  o.on("--output FILE") { |v| opts[:output] = v }
  o.on("--exclusions FILE") { |v| opts[:exclusions] = v }
  o.on("--metadata FILE", "drop metadata, for each drop's kind, custodian and year") { |v| opts[:metadata] = v }
end.parse!

PDF_DIR = File.expand_path(opts[:pdf_dir])
OCR_DIR = File.expand_path(opts[:ocr_dir])
EXCLUSIONS = YAML.load_file(opts[:exclusions]).to_set
DROPS = Drops.load(opts[:metadata])

# Same layout ocr.rb writes: <pdf_dir>/<drop>/<rel>.pdf -> <ocr_dir>/<drop>/<rel>/<stem>.{md,txt}.
# ocr.rb writes one or the other, never both.
def ocr_text_path(pdf)
  rel = pdf.delete_prefix("#{PDF_DIR}/")
  base = File.join(OCR_DIR, rel.delete_suffix(File.extname(rel)), File.basename(pdf, ".*"))
  %w[md txt].map { |ext| "#{base}.#{ext}" }.find { |f| File.exist?(f) }
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
  squeeze_whitespace(text)
end

def squeeze_whitespace(text)
  text.lines.map { |l| l.gsub(/[ \t ]+/, " ").strip }
    .join("\n")
    .gsub(/\n{3,}/, "\n\n")
    .strip
end

# pdftotext's output is already plain text -- running it through plain_text
# would eat anything in it that looks like markup -- so it only needs the
# column padding from -layout squeezed out.
def fulltext_of(path)
  text = File.read(path, encoding: "UTF-8")
  path.end_with?(".md") ? plain_text(text) : squeeze_whitespace(text)
end

# The longest original name, reduced to ASCII letters, digits, "_" and "-" so
# it's safe in URLs and shell commands.  Dots in the stem become "_" (Jekyll
# mangles URLs containing ".." or ending in ".").
def normalized_filename(filenames)
  name = filenames.max_by(&:length)
  stem = File.basename(name, ".*")
    .unicode_normalize(:nfd).gsub(/\p{Mn}/, "") # deburr: "Díaz" -> "Diaz"
    .gsub(/[\s.]+/, "_")
    .gsub(/[^A-Za-z0-9_-]/, "")
    .squeeze("_").sub(/\A[_-]+/, "").delete_suffix("_")
  [stem.empty? ? "document" : stem, File.extname(name).downcase]
end

pdfs = Dir.glob(File.join(PDF_DIR, "*", "**", "*.pdf"), File::FNM_CASEFOLD).sort

docs = {} # sha256 => { filenames:, text:, path: }
missing = []
excluded = 0

shas = Parallel.map(pdfs) { |pdf| Digest::SHA256.file(pdf).hexdigest }
pdfs.zip(shas).each do |pdf, sha|
  if EXCLUSIONS.include?(sha)
    excluded += 1
    next
  end

  doc = docs[sha] ||= { filenames: [], text: nil }
  name = File.basename(pdf)
  doc[:filenames] << name unless doc[:filenames].include?(name)

  next if doc[:text]

  if (text = ocr_text_path(pdf))
    doc[:text] = text
    doc[:path] = pdf.delete_prefix("#{PDF_DIR}/")
  else
    missing << [pdf, sha]
  end
end

# a later copy of the same document may have been OCRed
missing = missing.filter_map { |pdf, sha| pdf unless docs[sha][:text] }
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

distinct = docs.size
docs.select! { |_, doc| doc[:text] }
docs.each_value do |doc|
  doc[:drop] = doc[:path].split("/").first
  doc[:kind] = Drops.kind(DROPS[doc[:drop]])
end

# The text cleanup and regex matching are CPU-bound, so spread them across
# processes (threads would just queue up behind the GVL).  Parallel.map keeps
# the input order.  The fulltexts are read in a pass of their own because
# stripping an SFI's boilerplate takes every other SFI in its drop.
fulltexts = Parallel.map(docs.values) { |doc| fulltext_of(doc[:text]) }
docs.each_value.zip(fulltexts) { |doc, fulltext| doc[:fulltext] = fulltext }

boilerplate = docs.each_value
  .select { |doc| doc[:kind] == Drops::SFI }
  .group_by { |doc| doc[:drop] }
  .transform_values { |ds| Boilerplate.common_lines(ds.map { |d| d[:fulltext] }) }

def disclosure_fields(doc)
  fulltext = doc[:fulltext]
  {
    category: Category.of(fulltext),
    **Filing.of(doc[:filenames], doc[:path], fulltext),
    fulltext: fulltext,
    **Filer.of(fulltext).slice(:name, :title, :agency),
  }
end

def sfi_fields(doc, boilerplate)
  {
    category: Category::SFI,
    date: DROPS.dig(doc[:drop], "year")&.to_s,
    date_source: "drop",
    fulltext: Boilerplate.strip(doc[:fulltext], boilerplate),
    name: nil,
    title: nil,
    agency: nil,
  }
end

FileUtils.mkdir_p(File.dirname(opts[:output]))
tmp = "#{opts[:output]}.tmp"
lines = Parallel.map(docs.to_a) do |sha, doc|
  fields = doc[:kind] == Drops::SFI ? sfi_fields(doc, boilerplate[doc[:drop]]) : disclosure_fields(doc)
  JSON.generate(
    filename: doc[:filename],
    custodian: DROPS.dig(doc[:drop], "custodian"),
    category: fields[:category],
    date: fields[:date],
    date_source: fields[:date_source],
    original_filenames: doc[:filenames],
    original_path: doc[:path],
    sha256sum: sha,
    fulltext: fields[:fulltext],
    name: fields[:name],
    title: fields[:title],
    agency: fields[:agency],
  )
end
File.open(tmp, "w") { |f| f.puts(lines) }
File.rename(tmp, opts[:output])

counts = docs.each_value.map { |doc| doc[:kind] }.tally.map { |kind, n| "#{n} #{kind}" }.join(", ")
puts "#{pdfs.size} PDF(s), #{excluded} excluded, #{distinct} distinct, " \
     "#{lines.size} written to #{opts[:output]} (#{counts})"
