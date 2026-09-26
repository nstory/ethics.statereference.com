require "json"

# Generates a page at /disclosures/<filename without .pdf>/ for every line of
# etl/output/pdfs.jsonl.  The record is available to the layout as
# page.disclosure (not merged into the page, since `name` and `title` clash
# with Jekyll's own page attributes), and the PDF itself in the R2 bucket as
# page.pdf_url.  For the homepage to report, the number of SFIs is left in
# site.data.sfi_count and the number of everything else in
# site.data.disclosure_count.
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
      sfi_count = 0
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
        description = describe(disclosure)
        page.data["description"] = description if description
        site.pages << page
        if disclosure["category"] == "Statement of Financial Interests"
          sfi_count += 1
        else
          count += 1
        end
      end
      site.data["disclosure_count"] = count
      site.data["sfi_count"] = sfi_count

      metadata = JSON.parse(File.read(File.expand_path("../etl/output/metadata.json", site.source)))
      site.data["disclosure_drops"] = metadata["drops"]
    end

    private

    # The page's meta description (jekyll-seo-tag), e.g. "Statement of Financial
    # Interests filed by Maura Healey in 2024."  Many records have no name and a
    # few no date; whichever is missing is left out, and with neither there's
    # nothing to say beyond the site's own description, so this returns nil.
    def describe(disclosure)
      name = disclosure["name"]
      year = disclosure["date"].to_s[0, 4]
      return nil if name.to_s.empty? && year.empty?

      kind = disclosure["category"] == "Statement of Financial Interests" ? "Statement of Financial Interests" : "Disclosure"
      parts = [kind, "filed"]
      parts << "by #{name}" unless name.to_s.empty?
      parts << "in #{year}" unless year.empty?
      "#{parts.join(" ")}."
    end
  end
end
