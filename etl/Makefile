DROP_DIR ?= input/drops
PDF_DIR  ?= input/pdfs
OCR_DIR  ?= input/ocr
OUTPUT_DIR ?= output
MODEL_DIR ?= models/chandra-mlx-4bit
R2_REMOTE ?= r2
R2_BUCKET ?= ethics-files

DROPS  := $(wildcard $(DROP_DIR)/*.zip)
STAMPS := $(patsubst $(DROP_DIR)/%.zip,$(PDF_DIR)/%/.extracted,$(DROPS))

.PHONY: all clean r2-sync r2-sync-dry-run pdfs pdfs-clean $(OUTPUT_DIR)/pdfs.jsonl metadata disclosure-pdfs disclosure-pdfs-clean ocr ocr-model ocr-status ocr-clean ocr-model-clean

# Everything: extract, OCR, then build the output.  The output is made by a
# sub-make so it runs after OCR even under -j.
all: ocr
	$(MAKE) $(OUTPUT_DIR)/pdfs.jsonl
	$(MAKE) $(OUTPUT_DIR)/metadata.json
	$(MAKE) disclosure-pdfs

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

# corpus-wide metadata for the site (the drops and their dates); see README.md
$(OUTPUT_DIR)/metadata.json: $(DROPS)
	ruby lib/metadata_json.rb --drop-dir $(DROP_DIR) --output $@

metadata: $(OUTPUT_DIR)/metadata.json

# hard link every PDF in pdfs.jsonl to $(OUTPUT_DIR)/pdfs/disclosures/<filename>,
# the directory synced to R2.  Uses the existing pdfs.jsonl; doesn't rebuild it.
disclosure-pdfs:
	ruby lib/pdfs_dir.rb --pdf-dir $(PDF_DIR) --jsonl $(OUTPUT_DIR)/pdfs.jsonl --output-dir $(OUTPUT_DIR)/pdfs/disclosures

disclosure-pdfs-clean:
	rm -rf $(OUTPUT_DIR)/pdfs

# Upload $(OUTPUT_DIR)/pdfs to the R2 bucket served at ethics-files.nathanielstory.com,
# so <filename> lands at /disclosures/<filename>.  Needs an `r2` rclone remote;
# see README.md.  --size-only because R2 doesn't keep the local mtimes; rclone
# sync deletes what's no longer local, so PDFs dropped from pdfs.jsonl go away
# in the bucket too.
R2_SYNC = rclone sync $(OUTPUT_DIR)/pdfs $(R2_REMOTE):$(R2_BUCKET) \
	  --size-only --transfers 16 --checkers 32 --fast-list --stats-one-line --progress \
	  --header-upload "Cache-Control: public, max-age=31536000, immutable"

# guard: an empty or missing directory would empty the bucket
r2-sync:
	@test -n "$$(ls -A $(OUTPUT_DIR)/pdfs/disclosures 2>/dev/null)" || \
	  { echo "$(OUTPUT_DIR)/pdfs/disclosures is empty; run make disclosure-pdfs first"; exit 1; }
	$(R2_SYNC)

# What would `make r2-sync` upload and delete?
r2-sync-dry-run:
	$(R2_SYNC) --dry-run

ocr-model-clean:
	rm -rf $(MODEL_DIR)

# delete everything in $(OUTPUT_DIR), but keep the directory
clean:
	[ ! -d $(OUTPUT_DIR) ] || find $(OUTPUT_DIR) -mindepth 1 -delete
