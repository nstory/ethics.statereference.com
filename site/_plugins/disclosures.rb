require "json"

# Counts the lines of etl/output/pdfs.jsonl for the homepage to report: the
# number of SFIs is left in site.data.sfi_count and the number of everything
# else in site.data.disclosure_count.  The disclosures have no pages of their
# own; search results link straight to the PDFs (see index.mjs).
#
# The drops the corpus was built from, read from etl/output/metadata.json, are
# left in site.data.disclosure_drops -- oldest first, with whatever fields
# metadata.json gives them.
module Disclosures
  class Generator < Jekyll::Generator
    safe true

    def generate(site)
      path = File.expand_path("../etl/output/pdfs.jsonl", site.source)
      count = 0
      sfi_count = 0
      File.foreach(path) do |line|
        if JSON.parse(line)["category"] == "Statement of Financial Interests"
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
  end
end
