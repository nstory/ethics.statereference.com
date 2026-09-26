# Build the site, then index it.  Pagefind reads the built HTML in _site and
# writes its bundle to _site/pagefind, so it has to run after Jekyll -- and
# `jekyll build` empties _site, which is why this isn't two independent targets.
# Pagefind never deletes a previous run's files, and keep_files (see reindex)
# spares _site/pagefind from Jekyll, so each indexing clears it first; left
# alone, stale fragments pile up by the tens of thousands.
JEKYLL ?= bundle exec jekyll
PAGEFIND ?= node_modules/.bin/pagefind
WRANGLER ?= npx wrangler@4.25.0

.PHONY: all build index reindex serve deploy login clean

all: build

build: index

index:
	$(JEKYLL) build
	rm -rf _site/pagefind
	$(PAGEFIND) --site _site

# _config.yml's keep_files holds onto _site/pagefind across the regenerations
# watching does, so edits leave search working against the index built above.
# That index goes stale as pages change; `make reindex` refreshes it in place,
# from another shell, without stopping the server.
reindex:
	rm -rf _site/pagefind
	$(PAGEFIND) --site _site

serve: build
	$(JEKYLL) serve --skip-initial-build --watch

deploy: build
	$(WRANGLER) pages deploy _site --project-name ethics

login:
	$(WRANGLER) login

clean:
	rm -rf _site .jekyll-cache .jekyll-metadata
