require "json"

# Generates a page at /disclosures/<filename without .pdf>/ for every line of
# etl/output/pdfs.jsonl.  The record is available to the layout as
# page.disclosure (not merged into the page, since `name` and `title` clash
# with Jekyll's own page attributes), and the PDF itself in the R2 bucket as
# page.pdf_url.  The number of pages generated is left in
# site.data.disclosure_count for the homepage to report.
#
# The drops the corpus was built from, read from etl/output/metadata.json, are
# left in site.data.disclosure_drops -- oldest first, with whatever fields
# metadata.json gives them.
module Disclosures
  class Generator < Jekyll::Generator
    safe true

    def generate(site)
      path = File.expand_path("../etl/output/pdfs.jsonl", site.source)
      files_url = site.config["files_url"].to_s.chomp("/")
      count = 0
      File.foreach(path) do |line|
        disclosure = JSON.parse(line)
        slug = File.basename(disclosure["filename"], ".pdf")
        page = Jekyll::PageWithoutAFile.new(site, site.source, "disclosures/#{slug}", "index.html")
        page.data.merge!(
          "layout" => "disclosure",
          # The longest original filename, which is the one `filename` itself is
          # derived from, so the title and the slug describe the same file.
          "title" => disclosure["original_filenames"].max_by(&:length) || disclosure["filename"],
          "disclosure" => disclosure,
          "pdf_url" => "#{files_url}/disclosures/#{disclosure["filename"]}"
        )
        site.pages << page
        count += 1
      end
      site.data["disclosure_count"] = count

      metadata = JSON.parse(File.read(File.expand_path("../etl/output/metadata.json", site.source)))
      site.data["disclosure_drops"] = metadata["drops"]
    end
  end
end
