# ethics.statereference.com
Database for Massachusetts conflict of interest law ethics disclosures.

## directories
| path | purpose |
|--------|-------|
| etl/input/drops/xxx.zip | drop of ethics disclosures from an agency |
| etl/input/pdfs/xxx | extracted files from drop xxx |
| etl/input/ocr/xxx/yyy | chandra ocr of pdfs/xxx/yyy.pdf |
| etl/models/chandra-mlx-4bit | chandra quantized for MLX; built by `make ocr-model` |

## ocr
`make ocr` OCRs every PDF that doesn't have up-to-date output yet, running
chandra on MLX at roughly 8s/page.  Interrupted runs resume.

The GPU is shared with the rest of the desktop, and a busy browser can slow a
run by an order of magnitude, so leave the machine mostly idle for long runs.
