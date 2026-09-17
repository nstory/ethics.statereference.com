DROP_DIR ?= input/drops
PDF_DIR  ?= input/pdfs
OCR_DIR  ?= input/ocr
OUTPUT_DIR ?= output
MODEL_DIR ?= models/chandra-mlx-4bit

DROPS  := $(wildcard $(DROP_DIR)/*.zip)
STAMPS := $(patsubst $(DROP_DIR)/%.zip,$(PDF_DIR)/%/.extracted,$(DROPS))

.PHONY: pdfs pdfs-clean $(OUTPUT_DIR)/pdfs.jsonl ocr ocr-model ocr-status ocr-clean ocr-model-clean

# extract every drop in $(DROP_DIR) into $(PDF_DIR)/<drop>/
pdfs: $(STAMPS)

# we use tar to extract zips b/c unzip doesn't like unicode chars
$(PDF_DIR)/%/.extracted: $(DROP_DIR)/%.zip
	rm -rf $(@D)
	mkdir -p $(@D)
	tar -xf $< -C $(@D)
	touch $@

pdfs-clean:
	rm -rf $(PDF_DIR)

# Quantize chandra to 4-bit MLX.  ~10GB download, ~3GB on disk afterwards.
# 4-bit was checked against 8-bit and bf16 on handwritten forms from the corpus
# and read every filled-in field identically, so the smaller weights are free.
$(MODEL_DIR):
	uv run --quiet --python 3.12 --with mlx-vlm \
	  mlx_vlm.convert --hf-path datalab-to/chandra-ocr-2 \
	  --mlx-path $(MODEL_DIR) -q --q-bits 4

ocr-model: $(MODEL_DIR)

# phony target populates input/ocr
ocr: pdfs $(MODEL_DIR)
	ruby lib/ocr.rb --pdf-dir $(PDF_DIR) --ocr-dir $(OCR_DIR) --model $(MODEL_DIR) $(OCR_FLAGS)

# What would `make ocr` work on?
ocr-status:
	ruby lib/ocr.rb --pdf-dir $(PDF_DIR) --ocr-dir $(OCR_DIR) --dry-run

# one line per distinct PDF with its OCR fulltext; see README.md.  Phony
# because make can't track the OCR files it reads (their names have spaces).
$(OUTPUT_DIR)/pdfs.jsonl: pdfs
	ruby lib/pdfs_jsonl.rb --pdf-dir $(PDF_DIR) --ocr-dir $(OCR_DIR) --output $@

ocr-model-clean:
	rm -rf $(MODEL_DIR)
