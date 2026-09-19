# Build the site, then index it.  Pagefind reads the built HTML in _site and
# writes its bundle to _site/pagefind, so it has to run after Jekyll -- and
# `jekyll build` empties _site, which is why this isn't two independent targets.
JEKYLL ?= bundle exec jekyll
PAGEFIND ?= node_modules/.bin/pagefind

.PHONY: all build index reindex serve clean

all: build

build: index

index:
	$(JEKYLL) build
	$(PAGEFIND) --site _site

# _config.yml's keep_files holds onto _site/pagefind across the regenerations
# watching does, so edits leave search working against the index built above.
# That index goes stale as pages change; `make reindex` refreshes it in place,
# from another shell, without stopping the server.
reindex:
	$(PAGEFIND) --site _site

serve: build
	$(JEKYLL) serve --skip-initial-build --watch

clean:
	rm -rf _site .jekyll-cache .jekyll-metadata
