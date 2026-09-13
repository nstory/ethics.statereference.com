DROP_DIR ?= input/drops
PDF_DIR  ?= input/pdfs

DROPS  := $(wildcard $(DROP_DIR)/*.zip)
STAMPS := $(patsubst $(DROP_DIR)/%.zip,$(PDF_DIR)/%/.extracted,$(DROPS))

.PHONY: pdfs pdfs-clean

# Extract every drop in $(DROP_DIR) into $(PDF_DIR)/<drop>/.
pdfs: $(STAMPS)

# we use tar to extract zips b/c unzip doesn't like unicode chars
$(PDF_DIR)/%/.extracted: $(DROP_DIR)/%.zip
	rm -rf $(@D)
	mkdir -p $(@D)
	tar -xf $< -C $(@D)
	touch $@

pdfs-clean:
	rm -rf $(PDF_DIR)
