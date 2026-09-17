// Search results for /search, backed by the Pagefind index built from the
// hidden fulltext in _layouts/disclosure.html.
//
// Pagefind returns the whole result set from one search() call, as stubs whose
// data() is fetched lazily.  Paging is therefore just a slice of that array --
// no re-querying, and results.length is an exact total rather than an estimate.

const PAGE_SIZE = 20;
const PAGE_WINDOW = 2; // page links shown either side of the current one

const main = document.querySelector("[data-pagefind-bundle]");
const summaryEl = document.querySelector("[data-search-summary]");
const resultsEl = document.querySelector("[data-search-results]");
const pagerEl = document.querySelector("[data-search-pagination]");
const form = document.querySelector("[data-search-form]");
const input = document.querySelector("[data-search-input]");

let pagefind = null;
let cache = { query: null, results: [] };
// Bumped on every new search so a slow one that lands after a newer one can
// tell it's stale and bail out instead of overwriting the newer results.
let token = 0;

async function getPagefind() {
  if (!pagefind) {
    pagefind = await import(main.dataset.pagefindBundle);
    await pagefind.init();
  }
  return pagefind;
}

function readUrl() {
  const params = new URLSearchParams(location.search);
  const page = parseInt(params.get("page") ?? "1", 10);
  return {
    query: (params.get("q") ?? "").trim(),
    page: Number.isFinite(page) && page > 0 ? page : 1,
  };
}

function urlFor(query, page) {
  const params = new URLSearchParams();
  if (query) params.set("q", query);
  if (page > 1) params.set("page", String(page));
  const search = params.toString();
  return search ? `${location.pathname}?${search}` : location.pathname;
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
  // name appears.
  const details = [meta.name, meta.category, meta.position, meta.agency].filter(Boolean);
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

function renderPager(query, page, totalPages) {
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
      el.href = urlFor(query, targetPage);
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

async function renderPage(query, page) {
  const total = cache.results.length;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  if (page > totalPages) {
    // ?page= past the end shows the last page; correct the URL to match, without
    // adding a history entry for a page the reader never asked for.
    page = totalPages;
    history.replaceState({}, "", urlFor(query, page));
  }

  if (total === 0) {
    summaryEl.textContent = `No results for “${query}”.`;
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();
    return;
  }

  const first = (page - 1) * PAGE_SIZE;
  const stubs = cache.results.slice(first, first + PAGE_SIZE);

  const mine = token;
  const results = await Promise.all(stubs.map((stub) => stub.data()));
  if (mine !== token) return;

  summaryEl.textContent =
    `${total.toLocaleString()} ${total === 1 ? "result" : "results"} for “${query}” · ` +
    `showing ${(first + 1).toLocaleString()}–${(first + results.length).toLocaleString()}`;
  resultsEl.replaceChildren(...results.map(resultItem));
  renderPager(query, page, totalPages);
}

async function render() {
  const { query, page } = readUrl();
  if (input && input.value !== query) input.value = query;

  if (!query) {
    token++;
    cache = { query: null, results: [] };
    summaryEl.textContent = "Search the disclosures by name, agency or any text on the form.";
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();
    return;
  }

  if (query !== cache.query) {
    const mine = ++token;
    summaryEl.textContent = `Searching for “${query}”…`;
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();

    let search;
    try {
      const api = await getPagefind();
      search = await api.search(query);
    } catch (error) {
      console.error("[search] Pagefind failed to load or search", error);
      summaryEl.textContent = "Search is unavailable right now.";
      return;
    }
    if (mine !== token) return;
    cache = { query, results: search.results };
  }

  await renderPage(query, page);
}

function go(url, { replace = false } = {}) {
  if (replace) history.replaceState({}, "", url);
  else history.pushState({}, "", url);
  return render();
}

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  go(urlFor(input.value.trim(), 1));
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
