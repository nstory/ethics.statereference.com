// Search results for /search, backed by the Pagefind index built from the
// hidden fulltext in _layouts/disclosure.html.
//
// Pagefind returns the whole result set from one search() call, as stubs whose
// data() is fetched lazily.  Paging is therefore just a slice of that array --
// no re-querying, and results.length is an exact total rather than an estimate.

const PAGE_SIZE = 20;
const PAGE_WINDOW = 2; // page links shown either side of the current one

// What the sort control offers, and what each option means to Pagefind.  A
// sort replaces relevance ranking rather than refining it -- Pagefind will do
// one or the other -- so "relevance" is the absence of a sort, not a key of
// its own.  The key is date, indexed by _layouts/disclosure.html.
const SORTS = {
  relevance: null,
  newest: { date: "desc" },
  oldest: { date: "asc" },
};

const main = document.querySelector("[data-pagefind-bundle]");
const summaryEl = document.querySelector("[data-search-summary]");
const resultsEl = document.querySelector("[data-search-results]");
const pagerEl = document.querySelector("[data-search-pagination]");
const form = document.querySelector("[data-search-form]");
const input = document.querySelector("[data-search-input]");
const sortWrap = document.querySelector("[data-sort]");
const sortSelect = document.querySelector("[data-sort-select]");

// The category filter, rendered from _data/categories.yml by the search-form
// include.  Each checkbox carries the URL slug as its value and the exact
// Pagefind filter value -- the category name -- in data-category.
const toggle = document.querySelector("[data-category-toggle]");
const toggleLabel = document.querySelector("[data-category-toggle-label]");
const menu = document.querySelector("[data-category-menu]");
const clearButton = document.querySelector("[data-category-clear]");
const boxes = [...document.querySelectorAll("[data-category]")];

let pagefindPromise = null;
// Counts for every category across the whole index, from pagefind.filters().
// Used when nothing is being searched; a live search has better numbers.
let baseCounts = null;
let cache = { key: null, results: [], counts: null };
// Bumped on every new search so a slow one that lands after a newer one can
// tell it's stale and bail out instead of overwriting the newer results.
let token = 0;

function getPagefind() {
  // Cache the promise, not the module: init() and filters() have to finish
  // before anyone searches, and preload() races search() for this call.
  // filters() is also what makes Pagefind return counts alongside each search.
  pagefindPromise ??= (async () => {
    const api = await import(main.dataset.pagefindBundle);
    await api.init();
    baseCounts = (await api.filters()).category ?? null;
    return api;
  })();
  return pagefindPromise;
}

function readUrl() {
  const params = new URLSearchParams(location.search);
  const page = parseInt(params.get("page") ?? "1", 10);
  // Selecting through the menu's own order drops unknown slugs and duplicates,
  // so a hand-edited URL can't produce a selection the menu can't show.
  const slugs = new Set((params.get("category") ?? "").split(","));
  const sort = params.get("sort");
  return {
    query: (params.get("q") ?? "").trim(),
    categories: boxes.filter((box) => slugs.has(box.value)).map((box) => box.dataset.category),
    // hasOwn, not `in`: `?sort=toString` would otherwise name a real key.
    sort: Object.hasOwn(SORTS, sort) ? sort : "relevance",
    page: Number.isFinite(page) && page > 0 ? page : 1,
  };
}

// Takes a whole state -- {query, categories, sort, page} -- since every control
// changes one field of it and leaves the rest alone.
function urlFor({ query, categories, sort, page }) {
  const params = new URLSearchParams();
  if (query) params.set("q", query);
  if (categories.length) {
    const chosen = boxes.filter((box) => categories.includes(box.dataset.category));
    params.set("category", chosen.map((box) => box.value).join(","));
  }
  if (sort !== "relevance") params.set("sort", sort);
  if (page > 1) params.set("page", String(page));
  const search = params.toString();
  return search ? `${location.pathname}?${search}` : location.pathname;
}

// Identifies a result set, so paging within one doesn't re-run the search.
// Sort is part of it: Pagefind orders the set as it builds it, so a different
// order is a different search rather than a re-arrangement of this one.
function cacheKey({ query, categories, sort }) {
  return JSON.stringify([categories, sort, query]);
}

// "in Travel & Gifts", "in Travel & Gifts or Other" -- the filter ORs within
// itself, so "or" is what a multiple selection actually means.
function scope(categories) {
  return categories.length ? ` in ${categories.join(" or ")}` : "";
}

function pageNumbers(current, total) {
  const wanted = new Set([1, total, current]);
  for (let i = 1; i <= PAGE_WINDOW; i++) {
    wanted.add(current - i);
    wanted.add(current + i);
  }
  const shown = [...wanted].filter((n) => n >= 1 && n <= total).sort((a, b) => a - b);

  const out = [];
  let previous = 0;
  for (const n of shown) {
    if (previous && n - previous > 1) out.push(null); // gap -> ellipsis
    out.push(n);
    previous = n;
  }
  return out;
}

function resultItem(result) {
  const meta = result.meta ?? {};
  const li = document.createElement("li");
  li.className = "py-3 border-bottom";

  const heading = document.createElement("h2");
  heading.className = "h6 mb-1";
  const link = document.createElement("a");
  link.href = result.url;
  link.textContent = meta.title || meta.filename || result.url;
  heading.append(link);
  li.append(heading);

  // The heading is the filename, so this line is the only place the filer's
  // name appears.  The year leads because it's the one fixed-width field, which
  // makes a column of results easy to scan by date.
  const details = [meta.year, meta.name, meta.category, meta.position, meta.agency].filter(Boolean);
  if (details.length) {
    const line = document.createElement("p");
    line.className = "small text-body-secondary mb-1";
    line.textContent = details.join(" · ");
    li.append(line);
  }

  const excerpt = document.createElement("p");
  excerpt.className = "small mb-0";
  // Pagefind escapes the page's text when it builds the excerpt and adds only
  // <mark> around the matched terms, so this is markup we generated, not the
  // OCR text.
  excerpt.innerHTML = result.excerpt;
  li.append(excerpt);

  return li;
}

// Point the menu and its button at the current selection.
function renderFilter(categories) {
  if (!toggle) return;
  for (const box of boxes) box.checked = categories.includes(box.dataset.category);
  toggleLabel.textContent =
    categories.length === 0 ? "All categories"
    : categories.length === 1 ? categories[0]
    : `${categories.length} categories`;
  // The label can be cut short on a narrow screen, so carry the full selection
  // on the button for anyone who can't see the ellipsis resolved.
  toggle.title = toggleLabel.textContent;
}

// `counts` is Pagefind's totalFilters for the current search: the number of
// results each category would give *instead of* the current selection, which is
// the number a reader is asking for when they open the menu.
function renderCounts(counts) {
  for (const box of boxes) {
    const label = box.closest("label");
    const n = counts?.[box.dataset.category];
    label.querySelector("[data-category-count]").textContent = n?.toLocaleString() ?? "";
    // A dead end stays visible but unpickable.  A checked box always stays
    // pickable, or there'd be no way to undo it.
    box.disabled = n === 0 && !box.checked;
    label.classList.toggle("opacity-50", box.disabled);
  }
}

// The control is no use with nothing to reorder, and next to the empty-state
// prompt it reads as something that ought to be doing more than it is.
function showSort(visible) {
  sortWrap?.classList.toggle("d-none", !visible);
}

function renderPager(state, totalPages) {
  const { page } = state;
  pagerEl.replaceChildren();
  if (totalPages <= 1) return;

  const list = document.createElement("ul");
  list.className = "pagination";

  const item = (label, targetPage, { disabled = false, current = false } = {}) => {
    const li = document.createElement("li");
    li.className = `page-item${disabled ? " disabled" : ""}${current ? " active" : ""}`;

    const el = document.createElement(disabled ? "span" : "a");
    el.className = "page-link";
    el.textContent = label;
    if (!disabled) {
      el.href = urlFor({ ...state, page: targetPage });
    }
    if (current) el.setAttribute("aria-current", "page");
    li.append(el);
    list.append(li);
  };

  item("Previous", page - 1, { disabled: page === 1 });
  for (const n of pageNumbers(page, totalPages)) {
    if (n === null) item("…", 0, { disabled: true });
    else item(String(n), n, { current: n === page });
  }
  item("Next", page + 1, { disabled: page === totalPages });

  pagerEl.append(list);
}

async function renderPage(state) {
  const { query, categories } = state;
  const total = cache.results.length;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  if (state.page > totalPages) {
    // ?page= past the end shows the last page; correct the URL to match, without
    // adding a history entry for a page the reader never asked for.
    state = { ...state, page: totalPages };
    history.replaceState({}, "", urlFor(state));
  }

  // Without a query the reader is browsing a category rather than searching it,
  // so the summary drops the "for ..." and reads as a count of what's there.
  const forQuery = query ? ` for “${query}”` : "";

  if (total === 0) {
    summaryEl.textContent = `No results${forQuery}${scope(categories)}.`;
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();
    showSort(false);
    return;
  }

  const first = (state.page - 1) * PAGE_SIZE;
  const stubs = cache.results.slice(first, first + PAGE_SIZE);

  const mine = token;
  const results = await Promise.all(stubs.map((stub) => stub.data()));
  if (mine !== token) return;

  summaryEl.textContent =
    `${total.toLocaleString()} ${total === 1 ? "result" : "results"}${forQuery}${scope(categories)} · ` +
    `showing ${(first + 1).toLocaleString()}–${(first + results.length).toLocaleString()}`;
  resultsEl.replaceChildren(...results.map(resultItem));
  renderPager(state, totalPages);
  showSort(true);
}

async function render() {
  const state = readUrl();
  const { query, categories, sort } = state;
  if (input && input.value !== query) input.value = query;
  renderFilter(categories);
  if (sortSelect) sortSelect.value = sort;

  if (!query && !categories.length) {
    token++;
    cache = { key: null, results: [], counts: null };
    renderCounts(baseCounts);
    showSort(false);
    summaryEl.textContent = "Search the disclosures by name, agency or any text on the form.";
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();
    return;
  }

  const key = cacheKey(state);
  if (key !== cache.key) {
    const mine = ++token;
    summaryEl.textContent = query ? `Searching for “${query}”…` : "Loading…";
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();

    let search;
    try {
      const api = await getPagefind();
      // A null term filters without searching, which is what a category on its
      // own means: browse every disclosure of that kind.
      search = await api.search(query || null, {
        filters: categories.length ? { category: { any: categories } } : {},
        sort: SORTS[sort] ?? {},
      });
    } catch (error) {
      console.error("[search] Pagefind failed to load or search", error);
      summaryEl.textContent = "Search is unavailable right now.";
      return;
    }
    if (mine !== token) return;
    // Pagefind only computes totalFilters against a search term; with a null
    // term it returns zeros.  That case needs no help though -- with nothing
    // searched, "results if this category were picked instead" is just the
    // category's share of the index, which is what baseCounts holds.
    cache = { key, results: search.results, counts: query ? search.totalFilters?.category : null };
  }

  renderCounts(cache.counts ?? baseCounts);
  await renderPage(state);
}

function go(url, { replace = false } = {}) {
  if (replace) history.replaceState({}, "", url);
  else history.pushState({}, "", url);
  return render();
}

// The state the controls are currently showing, which is what the reader has
// typed but may not have submitted -- so picking a category or a sort applies
// it to the query in the box rather than to the last one searched.  Any change
// to the result set starts again at page 1.
function pending() {
  return {
    query: input.value.trim(),
    categories: boxes.filter((box) => box.checked).map((box) => box.dataset.category),
    sort: sortSelect?.value ?? "relevance",
    page: 1,
  };
}

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  go(urlFor(pending()));
});

menu?.addEventListener("change", () => go(urlFor(pending())));

sortSelect?.addEventListener("change", () => go(urlFor(pending())));

clearButton?.addEventListener("click", () => {
  if (!boxes.some((box) => box.checked)) return;
  go(urlFor({ ...pending(), categories: [] }));
});

// Opening the menu is a request to see the counts, so load the index then if a
// search hasn't already done it.
toggle?.addEventListener("click", () => {
  getPagefind()
    .then(() => renderCounts(cache.counts ?? baseCounts))
    .catch(() => {});
});

// Warm the indexes while the user is still typing; search() then has less to
// fetch when they hit enter.
input?.addEventListener("input", () => {
  const value = input.value.trim();
  if (value) getPagefind().then((api) => api.preload(value)).catch(() => {});
});

pagerEl.addEventListener("click", (event) => {
  const link = event.target.closest("a.page-link");
  if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
  event.preventDefault();
  go(link.getAttribute("href")).then(() => {
    window.scrollTo({ top: 0 });
    resultsEl.focus();
  });
});

window.addEventListener("popstate", render);

resultsEl.tabIndex = -1;
render();
