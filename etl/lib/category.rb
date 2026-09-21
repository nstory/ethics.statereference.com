# frozen_string_literal: true

# Sort a disclosure into a broad category from its OCR text.
#
# Most PDFs contain a State Ethics Commission form whose title names the type,
# e.g. "DISCLOSURE BY SPECIAL STATE EMPLOYEE OF FINANCIAL INTEREST IN A STATE
# CONTRACT".  We categorize by the first form title found.  Letters and memos
# have no title, so we fall back to the G.L. c. 268A section or 930 CMR rule
# they cite.
module Category
  FINANCIAL_INTEREST = "Financial Interest"
  TRAVEL_AND_GIFTS = "Travel & Gifts"
  APPEARANCE_OF_CONFLICT = "Appearance of Conflict"
  OTHER = "Other"
  # Not read from the text: every PDF in an SFI drop is one (see pdfs_jsonl.rb).
  SFI = "Statement of Financial Interests"

  # Checked in order; "FINANCIAL INTEREST" is last because it also appears in
  # some titles that belong elsewhere.
  TITLES = [
    [TRAVEL_AND_GIFTS, /TRAVEL|ATTENDANCE AT AN EVENT|HOSPITALITY|HONORARIUM|GIFT|EXPENSES|RECONCILIATION STATEMENT/],
    # 930 CMR 6.02(3) unpaid positions, §7 health facility jobs, §6B family members
    [OTHER, /UNCOMPENSATED POSITION|OF ELECTION OR APPOINTMENT|PART-TIME POSITION|FAMILY MEMBERS/],
    [APPEARANCE_OF_CONFLICT, /APPEARANCE OF CONFLICT/],
    [FINANCIAL_INTEREST, /FINANCIAL INTEREST/],
  ].freeze

  # Citations, checked in priority order: a legislator's letter under both §6A
  # and §23(b)(3) is a Financial Interest disclosure.
  SECTION = /(?:§+|\bs\.|\bsec(?:tion|\.)?)\s*/i
  CITATIONS = [
    [FINANCIAL_INTEREST, /#{SECTION}(?:1\s*\(o\)|6(?![B\d.])|7\b|13\b|19\b|20\b)|CMR\s*6\.(?:05|06|07|13|25|26)/i],
    [TRAVEL_AND_GIFTS, /CMR\s*5\.0[68]|honorari/i],
    [APPEARANCE_OF_CONFLICT, /23\s*\(?b\)?\s*\(?3/i],
  ].freeze

  # Clutter the OCR mixes into form titles: received stamps, redaction marks,
  # "(as defined by G.L. c. 268B, § 1)".
  NOISE = [
    /\[?REDACTED\]?/i,
    /RECEIVED|(?:STATE )?ETHICS COMMISSION/,
    /(?:\d{2,4}\s+)?[A-Z]{3,4}\s*-?\s*\d+\s*[AP]M\s*\d+\s*:\s*\d+/,
    /\([^)]*\)/,
  ].freeze

  def self.of(text)
    title = form_title(text)
    return TITLES.find { |_, re| title.match?(re) }&.first || OTHER if title

    CITATIONS.find { |_, re| text.match?(re) }&.first || OTHER
  end

  # The first uppercase "DISCLOSURE BY/OF/UNDER ..." or "RECONCILIATION
  # STATEMENT" line, joined with the line after it, which usually holds the
  # rest of the title.
  def self.form_title(text)
    lines = NOISE.reduce(text) { |t, re| t.gsub(re, " ") }
      .lines.map { |l| l.delete("*").squeeze(" ").strip }.reject(&:empty?)
    i = lines.index do |l|
      l.match?(/\A(?:DISCLOSURE (?:BY|OF|UNDER)|RECONCILIATION STATEMENT)\b/) && l == l.upcase
    end
    "#{lines[i]} #{lines[i + 1]}" if i
  end
end
