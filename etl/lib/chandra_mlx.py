# MLX inference backend for chandra.
#
# chandra ships `hf` (transformers) and `vllm` backends.  On Apple Silicon `hf`
# runs on MPS at ~33s/page and vLLM has no Metal support, so neither is usable
# for a 23k-page corpus.  This module adds a third backend on MLX, which reaches
# ~8s/page at 4-bit with a batch of 8.
#
# Everything except the generate step is chandra's own code: we reuse its
# prompts, its image preprocessing (scale_to_fit) and its HTML -> markdown
# output parsing, so output is byte-comparable with the `hf` backend.

from typing import List, Tuple

from chandra.model.schema import BatchInputItem, BatchOutputItem, GenerationResult
from chandra.model.util import scale_to_fit
from chandra.output import extract_images, parse_chunks, parse_html, parse_markdown
from chandra.prompts import PROMPT_MAPPING
from chandra.settings import settings


def load_mlx_model(model_path: str) -> Tuple[object, object]:
    from mlx_vlm import load

    model, processor = load(model_path)
    return model, processor


def generate_mlx(
    batch: List[BatchInputItem],
    model,
    processor,
    max_output_tokens: int | None = None,
) -> List[GenerationResult]:
    from mlx_vlm import batch_generate
    from mlx_vlm.prompt_utils import apply_chat_template

    if max_output_tokens is None:
        max_output_tokens = settings.MAX_OUTPUT_TOKENS

    # scale_to_fit is what the hf backend feeds the model; applying it here keeps
    # the two backends seeing identical pixels, and it settles most pages onto a
    # handful of distinct sizes so batch_generate's group_by_shape can pack them
    # with no padding waste.
    images = [scale_to_fit(item.image) for item in batch]
    prompts = [
        apply_chat_template(
            processor,
            model.config,
            item.prompt or PROMPT_MAPPING[item.prompt_type],
            num_images=1,
        )
        for item in batch
    ]

    resp = batch_generate(
        model,
        processor,
        images=images,
        prompts=prompts,
        max_tokens=max_output_tokens,
        verbose=False,
    )

    # BatchStats totals are per-batch, not per-page, so count each page's tokens
    # back out of its text for the per-page metadata chandra's CLI writes.
    tokenizer = getattr(processor, "tokenizer", processor)
    results = []
    for text in resp.texts:
        results.append(
            GenerationResult(
                raw=text,
                token_count=len(tokenizer.encode(text)),
                error=not text.strip(),
            )
        )
    return results


class MlxInferenceManager:
    """Mirrors chandra.model.InferenceManager for the MLX backend."""

    def __init__(self, model_path: str):
        self.model, self.processor = load_mlx_model(model_path)

    def generate(
        self,
        batch: List[BatchInputItem],
        max_output_tokens: int | None = None,
        include_images: bool = False,
        include_headers_footers: bool = True,
        bbox_scale: int = settings.BBOX_SCALE,
    ) -> List[BatchOutputItem]:
        results = generate_mlx(
            batch, self.model, self.processor, max_output_tokens=max_output_tokens
        )

        output_kwargs = {
            "include_images": include_images,
            "include_headers_footers": include_headers_footers,
        }
        output = []
        for result, item in zip(results, batch):
            chunks = parse_chunks(result.raw, item.image, bbox_scale=bbox_scale)
            output.append(
                BatchOutputItem(
                    markdown=parse_markdown(result.raw, **output_kwargs),
                    html=parse_html(result.raw, **output_kwargs),
                    chunks=chunks,
                    raw=result.raw,
                    page_box=[0, 0, item.image.width, item.image.height],
                    token_count=result.token_count,
                    images=extract_images(result.raw, chunks, item.image),
                    error=result.error,
                )
            )
        return output
