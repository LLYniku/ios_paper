from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Any

from openai import OpenAI

from zotero_arxiv_daily.app_export.classics_exporter import (
    enrich_classics_feed,
    parse_awesome_llm_compression_readme,
    write_classics_feed,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate classics feed JSON from awesome-paper README.")
    parser.add_argument(
        "--readme-path",
        default="Awesome-LLM-Compression-main/README.md",
        help="Path to the awesome list README.",
    )
    parser.add_argument(
        "--output",
        default="public/data/classics.json",
        help="Output path for the generated classics JSON feed.",
    )
    parser.add_argument(
        "--bundle-output",
        default="ios/PaperDaily/PaperDaily/Resources/sample_classics.json",
        help="Optional iOS bundled sample output path.",
    )
    parser.add_argument(
        "--cache-path",
        default="public/data/cache/classics_summaries.json",
        help="Cache path for fetched abstracts and generated summaries.",
    )
    return parser


def build_llm_components() -> tuple[OpenAI | None, dict[str, Any] | None]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return None, None

    base_url = os.getenv("OPENAI_API_BASE") or None
    model = os.getenv("OPENAI_MODEL") or "gpt-5.4-mini"
    wire_api = os.getenv("OPENAI_WIRE_API") or "responses"
    disable_storage = (os.getenv("OPENAI_DISABLE_RESPONSE_STORAGE") or "true").lower() == "true"

    llm_params = {
        "api": {
            "wire_api": wire_api,
            "disable_response_storage": disable_storage,
        },
        "generation_kwargs": {
            "model": model,
            "max_output_tokens": 500,
            "temperature": 0.2,
        },
        "language": "简体中文",
    }
    return OpenAI(api_key=api_key, base_url=base_url), llm_params


def main() -> int:
    args = build_parser().parse_args()
    readme_path = Path(args.readme_path)
    feed = parse_awesome_llm_compression_readme(readme_path)

    openai_client, llm_params = build_llm_components()
    enriched_feed = enrich_classics_feed(
        feed,
        openai_client=openai_client,
        llm_params=llm_params,
        cache_path=Path(args.cache_path) if args.cache_path else None,
    )

    write_classics_feed(enriched_feed, Path(args.output))
    if args.bundle_output:
        write_classics_feed(enriched_feed, Path(args.bundle_output))

    summary_count = sum(1 for paper in enriched_feed.papers if paper.summary_zh)
    print(
        "Generated classics feed:",
        f"papers={enriched_feed.paper_count}",
        f"categories={len(enriched_feed.categories)}",
        f"summaries={summary_count}",
        f"output={args.output}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
