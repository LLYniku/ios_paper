from __future__ import annotations

import argparse
from pathlib import Path

from zotero_arxiv_daily.app_export.classics_exporter import (
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
    return parser


def main() -> int:
    args = build_parser().parse_args()
    readme_path = Path(args.readme_path)
    feed = parse_awesome_llm_compression_readme(readme_path)

    write_classics_feed(feed, Path(args.output))
    if args.bundle_output:
        write_classics_feed(feed, Path(args.bundle_output))

    print(
        "Generated classics feed:",
        f"papers={feed.paper_count}",
        f"categories={len(feed.categories)}",
        f"output={args.output}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
