# /// script
# requires-python = ">=3.12"
# dependencies = ["chandra-ocr", "mlx-vlm"]
# ///
#
# OCR a manifest of PDFs with chandra on MLX.
#
# Reads a JSON manifest of {pdf, dest_dir, stem} jobs and writes chandra's usual
# three outputs (<stem>.md, <stem>.html, <stem>_metadata.json) into each job's
# dest_dir.  ocr.rb decides what still needs doing and builds the manifest;
# this script just does the inference.
#
# chandra's own CLI batches pages within a single document, which is no help
# here: the corpus averages 3.5 pages per PDF, so a batch of 8 would almost
# never fill.  We keep one queue of pages drawn from as many documents as it
# takes to fill a batch, and write each document out once its last page lands.

import argparse
import json
import sys
import time
from pathlib import Path

from chandra.input import load_file
from chandra.model.schema import BatchInputItem

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chandra_mlx import MlxInferenceManager  # noqa: E402


def save_document(dest_dir: Path, stem: str, results: list, save_images: bool) -> None:
    """Write one document's pages out in chandra's CLI output layout."""
    dest_dir.mkdir(parents=True, exist_ok=True)

    markdown = "".join(r.markdown for r in results)
    html = "".join(r.html for r in results)
    metadata = {
        "file_name": f"{stem}.pdf",
        "num_pages": len(results),
        "total_token_count": sum(r.token_count for r in results),
        "total_chunks": sum(len(r.chunks) for r in results),
        "total_images": sum(len(r.images) for r in results),
        "pages": [
            {
                "page_num": i,
                "page_box": r.page_box,
                "token_count": r.token_count,
                "num_chunks": len(r.chunks),
                "num_images": len(r.images),
            }
            for i, r in enumerate(results)
        ],
    }

    if save_images:
        for r in results:
            for img_name, pil_image in r.images.items():
                pil_image.save(dest_dir / img_name)

    # Write the markdown last: ocr.rb treats an existing .md as "done", so it
    # must not appear until its siblings are on disk.
    (dest_dir / f"{stem}.html").write_text(html, encoding="utf-8")
    (dest_dir / f"{stem}_metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8"
    )
    (dest_dir / f"{stem}.md").write_text(markdown, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", help="JSON file of {pdf, dest_dir, stem} jobs")
    ap.add_argument("--model", required=True, help="path to the converted MLX model")
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--max-output-tokens", type=int, default=None)
    ap.add_argument(
        "--include-images", action="store_true", help="save cropped figures too"
    )
    args = ap.parse_args()

    jobs = json.loads(Path(args.manifest).read_text())
    if not jobs:
        print("nothing to do")
        return 0

    print(f"loading {args.model}", flush=True)
    t0 = time.time()
    manager = MlxInferenceManager(args.model)
    print(f"model loaded in {time.time() - t0:.1f}s", flush=True)

    # Per-document state: how many pages we expect, and the results so far.
    expected: dict[int, int] = {}
    collected: dict[int, dict[int, object]] = {}
    abandoned: set[int] = set()
    failed: list[str] = []
    done = 0
    pages_done = 0
    started = time.time()

    def flush(queue: list) -> None:
        """Run one batch and file any documents it completes."""
        nonlocal done, pages_done
        batch = [BatchInputItem(image=img, prompt_type="ocr_layout") for _, _, img in queue]

        # One malformed page shouldn't end a run that has hours of work behind
        # it, so a failed batch only costs the documents it touched.  They keep
        # no output, stay pending, and come back on the next invocation.
        try:
            results = manager.generate(batch, max_output_tokens=args.max_output_tokens)
        except Exception as exc:  # noqa: BLE001
            print(f"  batch of {len(queue)} page(s) failed: {exc}", file=sys.stderr)
            results = []

        if len(results) != len(queue):
            for job_idx in {j for j, _, _ in queue}:
                if job_idx in abandoned:
                    continue
                abandoned.add(job_idx)
                failed.append(jobs[job_idx]["pdf"])
                collected.pop(job_idx, None)
            pages_done += len(queue)
            return

        for (job_idx, page_idx, _), result in zip(queue, results):
            if job_idx not in abandoned:
                collected[job_idx][page_idx] = result
        pages_done += len(queue)

        for job_idx in {j for j, _, _ in queue}:
            if job_idx in abandoned:
                continue
            if len(collected[job_idx]) != expected[job_idx]:
                continue
            job = jobs[job_idx]
            ordered = [collected[job_idx][i] for i in range(expected[job_idx])]
            try:
                save_document(
                    Path(job["dest_dir"]), job["stem"], ordered, args.include_images
                )
                done += 1
            except Exception as exc:  # noqa: BLE001
                print(f"  write failed for {job['pdf']}: {exc}", file=sys.stderr)
                failed.append(job["pdf"])
            del collected[job_idx]

        rate = (time.time() - started) / max(pages_done, 1)
        print(
            f"  {done}/{len(jobs)} docs, {pages_done} pages, {rate:.1f}s/page",
            flush=True,
        )

    queue: list = []
    for job_idx, job in enumerate(jobs):
        try:
            images = load_file(job["pdf"], {})
        except Exception as exc:  # noqa: BLE001
            print(f"  render failed for {job['pdf']}: {exc}", file=sys.stderr)
            failed.append(job["pdf"])
            continue

        if not images:
            print(f"  no pages in {job['pdf']}", file=sys.stderr)
            failed.append(job["pdf"])
            continue

        expected[job_idx] = len(images)
        collected[job_idx] = {}
        for page_idx, image in enumerate(images):
            queue.append((job_idx, page_idx, image))
            if len(queue) >= args.batch_size:
                flush(queue[: args.batch_size])
                del queue[: args.batch_size]

    while queue:
        flush(queue[: args.batch_size])
        del queue[: args.batch_size]

    elapsed = time.time() - started
    print(
        f"OCRed {done} doc(s), {pages_done} page(s) in {elapsed / 60:.1f} min "
        f"({elapsed / max(pages_done, 1):.1f}s/page)"
    )
    if failed:
        print(f"{len(failed)} PDF(s) produced no output:", file=sys.stderr)
        for path in failed[:20]:
            print(f"  {path}", file=sys.stderr)
        if len(failed) > 20:
            print(f"  ...and {len(failed) - 20} more", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
