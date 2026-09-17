# Build the site, then index it.  Pagefind reads the built HTML in _site and
# writes its bundle to _site/pagefind, so it has to run after Jekyll -- and
# `jekyll build` empties _site, which is why this isn't two independent targets.
JEKYLL ?= bundle exec jekyll
PAGEFIND ?= node_modules/.bin/pagefind

.PHONY: all build index serve clean

all: build

build: index

index:
	$(JEKYLL) build
	$(PAGEFIND) --site _site

# Watching would regenerate _site and delete the index underneath us, so the
# server runs against the build made above.  Re-run `make serve` after edits.
serve: build
	$(JEKYLL) serve --skip-initial-build --watch

clean:
	rm -rf _site .jekyll-cache .jekyll-metadata
