# ethics.statereference.com
Database for Massachusetts conflict of interest law ethics disclosures.

## directories
| path | purpose |
|--------|-------|
| etl/input/drops/xxx.zip | drop of ethics disclosures from an agency; named YYYY-MM-DD-agency.zip, e.g. 2025-08-07-sec.zip |
| etl/input/pdfs/xxx | extracted files from drop xxx |
| etl/input/ocr/xxx/yyy | chandra ocr of pdfs/xxx/yyy.pdf |
| etl/models/chandra-mlx-4bit | chandra quantized for MLX; built by `make ocr-model` |
| etl/output/pdfs.jsonl | pdf metadata for ingestion by site |

## pdfs.jsonl
One line per PDF, each line is a JSON object with these fields:
- `filename` unique filename for the PDF: the longest of `original_filenames`, deburred, spaces converted to underscores and characters other than letters, numbers, `_`, `.` and `-` removed, e.g. `Smith_John_930CMR5.082d2_disclosure_9.12.25.pdf`; if different PDFs end up with the same name (ignoring case), later ones get `_1`, `_2`, etc. appended before `.pdf`
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

## TODO
- [ ] exclusion list (remoed PDFs)
