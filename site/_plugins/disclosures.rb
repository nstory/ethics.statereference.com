require "json"

# Generates a page at /disclosures/<filename without .pdf>/ for every line of
# etl/output/pdfs.jsonl.  The record is available to the layout as
# page.disclosure (not merged into the page, since `name` and `title` clash
# with Jekyll's own page attributes), and the PDF itself in the R2 bucket as
# page.pdf_url.
module Disclosures
  class Generator < Jekyll::Generator
    safe true

    def generate(site)
      path = File.expand_path("../etl/output/pdfs.jsonl", site.source)
      files_url = site.config["files_url"].to_s.chomp("/")
      File.foreach(path) do |line|
        disclosure = JSON.parse(line)
        slug = File.basename(disclosure["filename"], ".pdf")
        page = Jekyll::PageWithoutAFile.new(site, site.source, "disclosures/#{slug}", "index.html")
        page.data.merge!(
          "layout" => "disclosure",
          "title" => [disclosure["name"], disclosure["category"]].compact.join(" – "),
          "disclosure" => disclosure,
          "pdf_url" => "#{files_url}/disclosures/#{disclosure["filename"]}"
        )
        site.pages << page
      end
    end
  end
end
