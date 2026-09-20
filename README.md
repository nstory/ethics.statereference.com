# ethics.statereference.com
Database for Massachusetts conflict of interest law ethics disclosures.

[Visit the site](https://ethics.statereference.com)

## AI Policy
Almost all of the code in this repo was written by [Claude Code](https://claude.com/product/claude-code). Two principles:
- AI is for writing code that's run by the computer
- AI is not for writing English that's read by humans

## directories
| path | purpose |
|--------|-------|
| etl/input/drops/xxx.zip | drop of ethics disclosures from an agency; named YYYY-MM-DD-agency.zip, e.g. 2025-08-07-sec.zip |
| etl/input/pdfs/xxx | extracted files from drop xxx |
| etl/input/ocr/xxx/yyy | chandra ocr of pdfs/xxx/yyy.pdf |
| etl/models/chandra-mlx-4bit | chandra quantized for MLX; built by `make ocr-model` |
| etl/metadata.yml | hand-maintained metadata for each drop |
| etl/output/pdfs.jsonl | pdf metadata for ingestion by site |
| etl/output/metadata.json | corpus-wide metadata for ingestion by site |
| etl/output/pdfs/disclosures/xxx.pdf | hard link to each PDF named for upload to R2 |
| site/ | jekyll site for ethics.stateference.com |

## metadata.json
Metadata about the corpus as a whole, as opposed to `pdfs.jsonl`'s line per PDF. A single JSON object with these fields:
- `drops` array with one entry per drop in `etl/input/drops`, oldest first, each an object with:
  - `filename` name of the drop's zip, e.g. `2025-08-07-sec.zip`
  - `date` date the drop was received, parsed from `filename`, e.g. `2025-08-07`
  - `custodian` agency the drop came from, e.g. `State Ethics Commission`
  - `url` where the drop was published, if it was; absent otherwise
  - `notes` what's in the drop, if it needs saying; absent otherwise

## metadata.yml
Everything about a drop that isn't in its name, one entry per zip in `etl/input/drops`, keyed by the zip's filename. Every drop needs an entry and every entry needs a drop; otherwise `make metadata` fails. Each entry's fields are copied into that drop's `metadata.json` object as they are, so a new field needs no code:
```yaml
2025-08-07-sec.zip:
  custodian: State Ethics Commission
  url: https://example.com/where-it-was-published
  notes: All disclosures June 2025 to present.
```

## pdfs.jsonl
One line per PDF, each line is a JSON object with these fields:
- `filename` unique filename for the PDF: the longest of `original_filenames`, deburred, spaces and dots converted to underscores (runs of underscores squeezed to one) and characters other than letters, numbers, `_` and `-` removed, e.g. `Smith_John_930CMR5_082d2_disclosure_9_12_25.pdf`; if different PDFs end up with the same name (ignoring case), later ones get `_1`, `_2`, etc. appended before `.pdf`
- `category` broad type of disclosure, one of:
  - `Financial Interest` financial interest in an official action or a public contract (G.L. c. 268A §§ 6, 6A, 7, 13, 19, 20; 930 CMR 6.05–6.07, 6.13, 6.25, 6.26)
  - `Travel & Gifts` travel expenses, event attendance, honoraria and gifts (930 CMR 5.06, 5.08)
  - `Appearance of Conflict` appearance of a conflict of interest (§ 23(b)(3))
  - `Other` everything else, e.g. uncompensated positions (930 CMR 6.02), family members (§ 6B), correspondence

  determined from the title of the first disclosure form in the text, or for letters and memos, from the sections they cite
- `original_filenames` array of filenames the PDF was provided under across all drops (identical files are merged by sha256) e.g. `Smith, John 930CMR5.082d2 disclosure 9.12.25.pdf`
- `original_path` path of one of the original files, relative to `etl/input/pdfs/`, e.g. `2025-08-07-sec/Nathaniel Story Records Request/2012/AlcornRichard§13Disclosure - 11.12.12.pdf`
- `sha256sum` sha256 of the PDF; unique per line
- `fulltext` the OCR'd text of the PDF (used for creating the fulltext index)
- `name` name of the filer, as written on the disclosure form, e.g. `Deborah B. Goldberg`; `null` if the PDF has no form (letters, memos, emails) or the field was left blank
- `title` filer's title or position, as written on the form, e.g. `State Treasurer and Receiver General`; `null` as for `name`
- `agency` filer's agency or department, as written on the form, e.g. `Office of the State Treasurer and Receiver General`; `null` as for `name`, and also for forms without an agency field (e.g. § 6A disclosures by legislators)

  `name`, `title` and `agency` are taken from the first form in the PDF and not cleaned up, so the same person or agency can appear with different spellings, capitalization or OCR errors
