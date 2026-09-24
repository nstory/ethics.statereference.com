// The search box, and -- on /search/ -- the results it produces, backed by the
// Pagefind index built from the hidden fulltext in _layouts/disclosure.html.
//
// Both pages that render the form load this.  The form behaves the same on each
// one; the difference is where a search goes.  /search/ has the results shell,
// so it answers the search itself and pushes a history entry.  The homepage has
// no shell, so the URL it builds is a real navigation to /search/.
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

const summaryEl = document.querySelector("[data-search-summary]");
const resultsEl = document.querySelector("[data-search-results]");
const pagerEl = document.querySelector("[data-search-pagination]");
const form = document.querySelector("[data-search-form]");
const input = document.querySelector("[data-search-input]");
const sortWrap = document.querySelector("[data-sort]");
const sortSelect = document.querySelector("[data-sort-select]");

// The category sidebar, which only /search/ has, rendered from
// _data/categories.yml.  Each checkbox carries the URL slug as its value and
// the exact Pagefind filter value -- the category name -- in data-category.
const filterEl = document.querySelector("[data-category-filter]");
const clearButton = document.querySelector("[data-category-clear]");
// On a phone the sidebar is a closed drawer, so the button that opens it
// carries the number ticked -- otherwise nothing on screen says a filter is on.
const badge = document.querySelector("[data-category-badge]");
const boxes = [...document.querySelectorAll("[data-category]")];

// The results shell, which only /search/ has.  Everything above is on both
// pages; these three are what let this one answer a search rather than send it.
const hasResults = Boolean(summaryEl && resultsEl && pagerEl);

// Where a search lands.  The form's action is /search/ on both pages -- which
// on /search/ is the page itself -- so urlFor builds the same string either way
// and the pager and history entries can use it too.
const target = form?.getAttribute("action") ?? location.pathname;

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
    const api = await import(form.dataset.pagefindBundle);
    await api.init();
    baseCounts = (await api.filters()).category ?? null;
    return api;
  })();
  return pagefindPromise;
}

function readUrl() {
  const params = new URLSearchParams(location.search);
  const page = parseInt(params.get("page") ?? "1", 10);
  // Selecting through the sidebar's own order drops unknown slugs and
  // duplicates, so a hand-edited URL can't produce a selection it can't show.
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
  return search ? `${target}?${search}` : target;
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

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// "2026", "Jan 2026", "Jan 4, 2026" -- as much of the date as we have, which
// can be any of the three (see etl/lib/filing.rb).  Split by hand rather than
// through Date, which reads "2026-01-04" as UTC midnight and so shows it as
// Jan 3 anywhere west of Greenwich.
function formatDate(iso) {
  const [year, month, day] = (iso ?? "").split("-");
  if (!month) return year;
  const mon = MONTHS[Number(month) - 1];
  return day ? `${mon} ${Number(day)}, ${year}` : `${mon} ${year}`;
}

// `excerpting` is off when there's no query: Pagefind falls back to the start of
// the page, which on these is the form's printed title, so every row would carry
// the same sentence.  The details line is what distinguishes them.
function resultItem(result, excerpting) {
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
  // name appears.  The date leads, so a column of results scans by date.
  const details = [formatDate(meta.date), meta.name, meta.category, meta.position, meta.agency].filter(Boolean);
  if (details.length) {
    const line = document.createElement("p");
    line.className = `small text-body-secondary ${excerpting ? "mb-1" : "mb-0"}`;
    line.textContent = details.join(" · ");
    li.append(line);
  }

  if (excerpting) {
    const excerpt = document.createElement("p");
    excerpt.className = "small mb-0";
    // Pagefind escapes the page's text when it builds the excerpt and adds only
    // <mark> around the matched terms, so this is markup we generated, not the
    // OCR text.
    excerpt.innerHTML = result.excerpt;
    li.append(excerpt);
  }

  return li;
}

// Point the sidebar at the current selection.
function renderFilter(categories) {
  for (const box of boxes) box.checked = categories.includes(box.dataset.category);
  clearButton?.classList.toggle("d-none", categories.length === 0);
  if (badge) {
    badge.textContent = String(categories.length);
    badge.hidden = categories.length === 0;
  }
}

// `counts` is Pagefind's totalFilters for the current search: the number of
// results each category would give on its own, whatever else is ticked, which
// is the number a reader is weighing when deciding what to tick.
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

  // Without a query the reader is browsing rather than searching, so the summary
  // drops the "for ..." and counts disclosures -- there was no search for them
  // to be the result of.
  const forQuery = query ? ` for “${query}”` : "";
  const noun = query ? "result" : "disclosure";

  if (total === 0) {
    summaryEl.textContent = `No ${noun}s${forQuery}${scope(categories)}.`;
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
    `${total.toLocaleString()} ${total === 1 ? noun : `${noun}s`}${forQuery}${scope(categories)} · ` +
    `showing ${(first + 1).toLocaleString()}–${(first + results.length).toLocaleString()}`;
  resultsEl.replaceChildren(...results.map((result) => resultItem(result, Boolean(query))));
  renderPager(state, totalPages);
  showSort(true);
}

async function render() {
  const state = readUrl();
  const { query, categories, sort } = state;
  if (input && input.value !== query) input.value = query;
  renderFilter(categories);
  if (sortSelect) sortSelect.value = sort;

  const key = cacheKey(state);
  if (key !== cache.key) {
    const mine = ++token;
    summaryEl.textContent = query ? `Searching for “${query}”…` : "Loading disclosures…";
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();

    let search;
    try {
      const api = await getPagefind();
      // A null term filters without searching.  With a category that means
      // browse every disclosure of that kind; with nothing at all it means
      // browse the lot, which is what /search/ opens on.
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
    // searched, a category's count is just its share of the index, which is
    // what baseCounts holds.
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
// to the result set starts again at page 1.  The homepage has no boxes, so a
// search from there starts unfiltered.
function pending() {
  return {
    query: input.value.trim(),
    categories: boxes.filter((box) => box.checked).map((box) => box.dataset.category),
    sort: sortSelect?.value ?? "relevance",
    page: 1,
  };
}

// Submitting means "show me this".  On /search/ that's a re-render in place;
// on the homepage it's the trip to /search/ the form would have made on its
// own.
function submit(url) {
  if (hasResults) return go(url);
  location.assign(url);
}

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  submit(urlFor(pending()));
});

sortSelect?.addEventListener("change", () => go(urlFor(pending())));

filterEl?.addEventListener("change", () => go(urlFor(pending())));

clearButton?.addEventListener("click", () => go(urlFor({ ...pending(), categories: [] })));

// Warm the indexes while the user is still typing; search() then has less to
// fetch when they hit enter.
input?.addEventListener("input", () => {
  const value = input.value.trim();
  if (value) getPagefind().then((api) => api.preload(value)).catch(() => {});
});

if (hasResults) {
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
}
