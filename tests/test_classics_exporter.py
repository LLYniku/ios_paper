from pathlib import Path

from zotero_arxiv_daily.app_export.classics_exporter import enrich_classics_feed, parse_awesome_llm_compression_readme


def test_parse_classics_readme_extracts_papers() -> None:
    readme = Path("Awesome-LLM-Compression-main/README.md")

    feed = parse_awesome_llm_compression_readme(readme)

    assert feed.schema_version == "1.0"
    assert feed.paper_count > 100
    assert "Quantization" in feed.categories


def test_parse_classics_readme_extracts_known_entry() -> None:
    readme = Path("Awesome-LLM-Compression-main/README.md")

    feed = parse_awesome_llm_compression_readme(readme)

    paper = next(p for p in feed.papers if p.title == "SmoothQuant: Accurate and Efficient Post-Training Quantization for Large Language Models")
    assert paper.category == "Quantization"
    assert paper.venue == "ICML"
    assert paper.year == 2023
    assert paper.paper_url == "https://arxiv.org/abs/2211.10438"
    assert paper.code_url == "https://github.com/mit-han-lab/smoothquant"


def test_enrich_classics_feed_uses_injected_fetcher_and_summary_generator(tmp_path: Path) -> None:
    readme = Path("Awesome-LLM-Compression-main/README.md")
    feed = parse_awesome_llm_compression_readme(readme)
    subset = type(feed)(
        schema_version=feed.schema_version,
        generated_at=feed.generated_at,
        source_title=feed.source_title,
        source_repo=feed.source_repo,
        readme_path=feed.readme_path,
        paper_count=1,
        categories=feed.categories,
        papers=[feed.papers[0]],
    )

    enriched = enrich_classics_feed(
        subset,
        cache_path=tmp_path / "classics_cache.json",
        abstract_fetcher=lambda _: "An abstract about compression.",
        summary_generator=lambda paper, abstract: {
            "summary_zh": f"{paper.title} 的中文摘要",
            "tldr": "一句话摘要",
            "simple_intro": f"这是一篇关于 {paper.category} 的经典论文。",
        },
    )

    paper = enriched.papers[0]
    assert paper.abstract == "An abstract about compression."
    assert paper.summary_zh == f"{paper.title} 的中文摘要"
    assert paper.tldr == "一句话摘要"
    assert paper.simple_intro == f"这是一篇关于 {paper.category} 的经典论文。"
