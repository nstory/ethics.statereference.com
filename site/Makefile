# Build the site, then index it.  index.mjs builds the Pagefind index from
# etl/output/pdfs.jsonl, not from the site, but writes its bundle to
# _site/pagefind -- and `jekyll build` empties _site, so it still has to run
# after Jekyll, which is why this isn't two independent targets.  Pagefind
# never deletes a previous run's files, and keep_files (see reindex) spares
# _site/pagefind from Jekyll, so each indexing clears it first; left alone,
# stale fragments pile up by the tens of thousands.
JEKYLL ?= bundle exec jekyll
# The R2 bucket the PDFs are served from, which is where search results link.
FILES_URL := $(shell ruby -ryaml -e 'puts YAML.load_file("_config.yml")["files_url"]')
WRANGLER ?= npx wrangler@4.25.0

.PHONY: all build index reindex serve deploy login clean

all: build

build: index

index:
	$(JEKYLL) build
	rm -rf _site/pagefind
	node index.mjs $(FILES_URL)

# _config.yml's keep_files holds onto _site/pagefind across the regenerations
# watching does, so edits leave search working against the index built above.
# The index only goes stale when etl/output/pdfs.jsonl changes; `make reindex`
# refreshes it in place, from another shell, without stopping the server.
reindex:
	rm -rf _site/pagefind
	node index.mjs $(FILES_URL)

serve: build
	$(JEKYLL) serve --skip-initial-build --watch

deploy: build
	$(WRANGLER) pages deploy _site --project-name ethics

login:
	$(WRANGLER) login

clean:
	rm -rf _site .jekyll-cache .jekyll-metadata
