// Builds the Pagefind index straight from etl/output/pdfs.jsonl, one record
// per PDF, and writes the bundle to _site/pagefind.  There are no pages to
// crawl: each record's url is the PDF itself in the R2 bucket, so a search
// result links directly to it.
//
//   node index.mjs <files_url>
//
// files_url is _config.yml's, passed in by the Makefile so this needs no YAML
// parser of its own.
//
// Every field search.js displays is in meta.  category is also the only
// filter, and date the only sort key.  Most dates are a full ISO date, but some
// are only a year and month or a bare year, and Pagefind compares a sort key as
// text unless every value is numeric -- so the short ones sort to the edge of
// their year rather than out of it, which is as good as the date we have.
// search.js shows each at the precision it has.

import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import * as pagefind from "pagefind";

const [filesUrl] = process.argv.slice(2);
if (!filesUrl) {
  console.error("usage: node index.mjs <files_url>");
  process.exit(1);
}
const base = `${filesUrl.replace(/\/$/, "")}/disclosures`;

const { index, errors: createErrors } = await pagefind.createIndex();
if (!index) throw new Error(`pagefind: ${createErrors.join("; ")}`);

// Pagefind drops an empty meta or sort value rather than storing "", and a
// missing one is what search.js already expects of a field we don't have.
function present(fields) {
  return Object.fromEntries(Object.entries(fields).filter(([, v]) => v != null && v !== ""));
}

const lines = createInterface({ input: createReadStream("../etl/output/pdfs.jsonl") });
let count = 0;
for await (const line of lines) {
  const disclosure = JSON.parse(line);
  // The longest original filename, which is the one `filename` itself is
  // derived from, so the title and the URL describe the same file.
  const title = disclosure.original_filenames.reduce(
    (longest, name) => (name.length > longest.length ? name : longest),
    "",
  ) || disclosure.filename;

  const { errors } = await index.addCustomRecord({
    url: `${base}/${disclosure.filename}`,
    content: disclosure.fulltext ?? "",
    language: "en",
    meta: present({
      title,
      name: disclosure.name,
      position: disclosure.title,
      agency: disclosure.agency,
      filename: disclosure.filename,
      category: disclosure.category,
      date: disclosure.date,
    }),
    filters: { category: [disclosure.category] },
    sort: present({ date: disclosure.date }),
  });
  if (errors.length) throw new Error(`pagefind: ${disclosure.filename}: ${errors.join("; ")}`);
  count++;
}

const { errors } = await index.writeFiles({ outputPath: "_site/pagefind" });
if (errors.length) throw new Error(`pagefind: ${errors.join("; ")}`);
await pagefind.close();
console.log(`Indexed ${count} disclosures into _site/pagefind`);
