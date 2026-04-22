from pathlib import Path

from zotero_arxiv_daily.app_export.classics_exporter import parse_awesome_llm_compression_readme


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
