# frozen_string_literal: true

require "yaml"

# What metadata.yml says about each drop, keyed by the directory `make pdfs`
# extracts it into -- the zip's name without ".zip" -- since that's the name
# the scripts after extraction see at the head of every path.
module Drops
  DISCLOSURE = "disclosure"
  SFI = "sfi"

  def self.load(path)
    YAML.load_file(path).to_h { |zip, entry| [File.basename(zip, ".zip"), entry || {}] }
  end

  # Drops with no `kind` predate the field, and they're all disclosures.
  def self.kind(entry)
    entry&.fetch("kind", nil) || DISCLOSURE
  end
end
