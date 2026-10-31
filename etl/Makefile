DROP_DIR ?= input/drops
PDF_DIR  ?= input/pdfs
OCR_DIR  ?= input/ocr
OUTPUT_DIR ?= output
MODEL_DIR ?= models/chandra-mlx-4bit
R2_REMOTE ?= r2
R2_BUCKET ?= ethics-files
DROPS_URL ?= https://ethics-files.nathanielstory.com/ethics-drops
DROPS_SHA256 ?= drops.sha256

DROPS  := $(wildcard $(DROP_DIR)/*.zip)
STAMPS := $(patsubst $(DROP_DIR)/%.zip,$(PDF_DIR)/%/.extracted,$(DROPS))

.PHONY: all clean r2-sync r2-sync-dry-run drops-sync drops-download pdfs pdfs-clean $(OUTPUT_DIR)/pdfs.jsonl metadata disclosure-pdfs disclosure-pdfs-clean ocr ocr-model ocr-status ocr-clean ocr-model-clean

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
	ruby lib/pdfs_jsonl.rb --pdf-dir $(PDF_DIR) --ocr-dir $(OCR_DIR) --metadata metadata.yml --output $@

# corpus-wide metadata for the site (the drops and what we know about them);
# see README.md
$(OUTPUT_DIR)/metadata.json: $(DROPS) metadata.yml
	ruby lib/metadata_json.rb --drop-dir $(DROP_DIR) --metadata metadata.yml --output $@

metadata: $(OUTPUT_DIR)/metadata.json

# hard link every PDF in pdfs.jsonl to $(OUTPUT_DIR)/pdfs/disclosures/<filename>,
# the directory synced to R2.  Uses the existing pdfs.jsonl; doesn't rebuild it.
disclosure-pdfs:
	ruby lib/pdfs_dir.rb --pdf-dir $(PDF_DIR) --jsonl $(OUTPUT_DIR)/pdfs.jsonl --output-dir $(OUTPUT_DIR)/pdfs/disclosures

disclosure-pdfs-clean:
	rm -rf $(OUTPUT_DIR)/pdfs

# Upload $(OUTPUT_DIR)/pdfs/disclosures to the R2 bucket served at
# ethics-files.nathanielstory.com, so <filename> lands at /disclosures/<filename>.
# Needs an `r2` rclone remote; see README.md.  --size-only because R2 doesn't
# keep the local mtimes; rclone sync deletes what's no longer local, so PDFs
# dropped from pdfs.jsonl go away in the bucket too.  Only disclosures/ is
# synced, so the rest of the bucket is left alone.
R2_SYNC = rclone sync $(OUTPUT_DIR)/pdfs/disclosures $(R2_REMOTE):$(R2_BUCKET)/disclosures \
	  --size-only --transfers 16 --checkers 32 --fast-list --stats-one-line --progress \
	  --header-upload "Cache-Control: public, max-age=31536000, immutable"

# guard: a missing or partial directory would delete PDFs from the bucket
R2_MIN_FILES ?= 15578
r2-sync:
	@n=$$(find $(OUTPUT_DIR)/pdfs/disclosures -type f 2>/dev/null | wc -l | tr -d " "); \
	  test "$$n" -ge $(R2_MIN_FILES) || \
	  { echo "$(OUTPUT_DIR)/pdfs/disclosures has $$n files, expected at least $(R2_MIN_FILES); run make disclosure-pdfs first"; exit 1; }
	$(R2_SYNC)

# What would `make r2-sync` upload and delete?
r2-sync-dry-run:
	$(R2_SYNC) --dry-run

# Upload the zips in $(DROP_DIR) as they are, so <drop>.zip lands at
# $(DROPS_URL)/<drop>.zip, and record their checksums for drops-download.  copy,
# not sync, so nothing in the bucket is ever deleted; a drop that has changed is
# overwritten.
drops-sync:
	cd $(DROP_DIR) && shasum -a 256 *.zip > $(abspath $(DROPS_SHA256))
	rclone copy $(DROP_DIR) $(R2_REMOTE):$(R2_BUCKET)/ethics-drops \
	  --include "*.zip" --stats-one-line --progress

# Fetch whichever drops in $(DROPS_SHA256) are missing from $(DROP_DIR), then
# verify all of them.  Needs no R2 credentials.
drops-download:
	awk '{print "$(DROPS_URL)/" $$2}' $(DROPS_SHA256) | \
	  wget --no-clobber --directory-prefix=$(DROP_DIR) --input-file=-
	cd $(DROP_DIR) && shasum -a 256 -c $(abspath $(DROPS_SHA256))

ocr-model-clean:
	rm -rf $(MODEL_DIR)

# delete everything in $(OUTPUT_DIR), but keep the directory
clean:
	[ ! -d $(OUTPUT_DIR) ] || find $(OUTPUT_DIR) -mindepth 1 -delete
