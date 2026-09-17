# frozen_string_literal: true

# Pull the filer's name, title and agency out of a disclosure's OCR text.
#
# The State Ethics Commission forms open with an information section of
# labeled fields, which the OCR gives as "Label: value" or the label on one
# line and the value on the next:
#
#   Name of public employee:
#   Deborah Goldberg
#
#   Title or Position:
#   State Treasurer and Receiver General
#
# We take the first occurrence of each label, as filled in.  Letters and memos
# have no labels, so their fields are nil, as is any field left blank.
module Filer
  # not "Name of Appointing Authority", "Name of course", ...
  NAME = /\A(?:Name of (?:(?:elected |non-elected |special )?(?:state |public |municipal |county )?(?:employee|official)|Faculty Member)|Name(?=\s*(?::|\z)))/i

  LABELS = {
    title: /\A(?:Title ?(?:or|\/) ?Position|Public official position)/i,
    agency: /\A(?:(?:County |Municipal |State )?Agency ?\/ ?Department|(?:County |Municipal |State )Agency(?=\s*(?::|\z)))/i,
  }.freeze

  # Plain "Title:", "Agency:" and "Department:" also label other things, like
  # the textbook in a course materials disclosure, so they only count shortly
  # after the name.
  BARE_LABELS = {
    title: /\ATitle(?=\s*(?::|\z))/i,
    agency: /\A(?:Agency|Department)(?=\s*(?::|\z))/i,
  }.freeze
  NEAR_NAME = 6 # lines

  # A "value" that's really the next label or section heading, or a received
  # stamp, i.e. the field was left blank.
  BLANK = Regexp.union(
    NAME, *LABELS.values, *BARE_LABELS.values,
    /\A(?:Office|Public office|Agency address|Course Number|Fill in|Check one)\b/i,
    /\A[A-Z ]+ INFORMATION\b/,
    /\A[-_.\\\s]*\z/,
    /\A\d{1,4}\s+[A-Z]{3}\b/,
  )

  # Received stamps, redaction marks and form instructions mixed in with the
  # fields.
  NOISE = Regexp.union(
    /This is [“"]my State Agency\.?[”"]\.?/,
    /Please provide information about your [^.\n]*position\./i,
    /\[insert (?:name|title)\]/i,
    /(?:\d{2,4}\s+)?[A-Z]{3,4}\s*-?\s*\d+\s*[AP]M\s*\d+\s*:\s*\d+/,
    /[A-Z ]+ EMPLOYEE INFORMATION|PUBLIC OFFICIAL INFORMATION|RECEIVED|STATE ETHICS COMMISSION/,
    /\[?REDACTED\]?/,
  )

  def self.of(text)
    lines = text.gsub(NOISE, " ").lines.map { |l| l.squeeze(" ").strip }.reject(&:empty?)
    n = lines.index { |l| l.match?(NAME) }
    fields = { name: n && value(lines, n, NAME) }
    LABELS.each do |key, label|
      i = lines.index { |l| l.match?(label) }
      i ||= n && (n + 1..n + NEAR_NAME).find { |j| lines[j]&.match?(BARE_LABELS[key]) }
      fields[key] = i && value(lines, i, Regexp.union(label, BARE_LABELS[key]))
    end
    fields
  end

  # The rest of the label's line, or failing that the next line.
  def self.value(lines, i, label)
    rest = lines[i].sub(label, "").sub(/\A[\s:]+/, "")
    value = (rest.empty? ? lines[i + 1] : rest)&.sub(/\A[\s:]+/, "")
    value unless value.nil? || value.match?(BLANK)
  end
end
