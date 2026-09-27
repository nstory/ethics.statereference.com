# ethics.statereference.com
Database for Massachusetts ethics disclosures.

[Visit the site](https://ethics.statereference.com)

## AI Policy
Almost all of the code in this repo was written by [Claude Code](https://claude.com/product/claude-code). Two principles:
- AI is for writing code that's run by the computer
- AI is not for writing English that's read by humans

## FILES & DIRECTORIES
| path | purpose |
|--------|-------|
| etl/input/drops/xxx.zip | drop of ethics disclosures from an agency; named YYYY-MM-DD-agency.zip, e.g. 2025-08-07-sec.zip |
| etl/input/pdfs/xxx | extracted files from drop xxx |
| etl/input/ocr/xxx/yyy | text of pdfs/xxx/yyy.pdf: `yyy.md` from chandra ocr, or `yyy.txt` from pdftotext for PDFs in SFI drops that have a text layer on every page |
| etl/models/chandra-mlx-4bit | chandra quantized for MLX; built by `make ocr-model` |
| etl/metadata.yml | hand-maintained metadata for each drop |
| etl/output/pdfs.jsonl | pdf metadata for ingestion by site |
| etl/output/metadata.json | corpus-wide metadata for ingestion by site |
| etl/output/pdfs/disclosures/xxx.pdf | hard link to each PDF named for upload to R2 |
| site/ | jekyll site for ethics.statereference.com |

## CONTRIBUTIONS
The ETL portion of the project probably only runs on my machine. If you do wish to contribute, you probably shouldn't try modifying the code by hand. Ask an AI coding agent to do the work.

## LICENSE
MIT
