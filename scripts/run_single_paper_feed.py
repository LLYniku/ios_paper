from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import UTC, datetime
from html import unescape
import json
import logging
import os
from pathlib import Path
import re
import sys
import time
from types import SimpleNamespace
from typing import Any

import arxiv
import dotenv
import requests
from hydra import compose, initialize_config_dir
from hydra.core.global_hydra import GlobalHydra
from loguru import logger
from omegaconf import DictConfig, OmegaConf, open_dict
from openai import OpenAI

from zotero_arxiv_daily.app_export import JSONFeedExporter
from zotero_arxiv_daily.retriever.arxiv_retriever import ArxivRetriever

ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = ROOT / "config"
ARXIV_URL_RE = re.compile(r"arxiv\.org/(?:abs|pdf|html)/([^/?#]+)", re.IGNORECASE)
ARXIV_ID_RE = re.compile(r"^\d{4}\.\d{4,5}(?:v\d+)?$")
ARXIV_HTML_TIMEOUT = (10, 30)


def configure_logging(debug: bool) -> None:
    log_level = "DEBUG" if debug else "INFO"
    logger.remove()
    logger.add(
        sys.stdout,
        level=log_level,
        format=(
            "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
            "<level>{level: <8}</level> | "
            "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - "
            "<level>{message}</level>"
        ),
    )
    for logger_name in logging.root.manager.loggerDict:
        if "zotero_arxiv_daily" in logger_name:
            continue
        logging.getLogger(logger_name).setLevel(logging.WARNING)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze one arXiv paper and prepend it to today's app feed.")
    parser.add_argument("--paper-url", required=True, help="arXiv abs/pdf/html URL or bare arXiv id.")
    parser.add_argument(
        "--config",
        default=os.getenv("CUSTOM_CONFIG"),
        help="Optional YAML config path or inline YAML/override object.",
    )
    parser.add_argument("--output-dir", default="public/data")
    parser.add_argument("--timezone", default="Asia/Taipei")
    parser.add_argument("--language", default="zh-Hans")
    return parser.parse_args()


def looks_like_inline_config(config_arg: str) -> bool:
    stripped = config_arg.strip()
    if not stripped:
        return False
    if "\n" in config_arg or "\r" in config_arg:
        return True
    if stripped.startswith(("{", "[")):
        return True
    if ": " in stripped or stripped.endswith(":"):
        return True
    return False


def load_optional_config(config_arg: str | None) -> DictConfig | None:
    if not config_arg:
        return None
    if looks_like_inline_config(config_arg):
        return OmegaConf.create(config_arg)

    config_path = Path(config_arg)
    try:
        if config_path.exists():
            return OmegaConf.load(config_path)
    except OSError:
        pass
    return OmegaConf.create(config_arg)


def hydra_compose() -> DictConfig:
    GlobalHydra.instance().clear()
    with initialize_config_dir(config_dir=str(CONFIG_DIR), version_base=None):
        return compose(config_name="default")


def build_config(args: argparse.Namespace) -> DictConfig:
    config = hydra_compose()
    extra_config = load_optional_config(args.config)
    if extra_config is not None:
        config = OmegaConf.merge(config, extra_config)
    with open_dict(config):
        config.app_export.enabled = True
        config.app_export.output_dir = args.output_dir
        config.app_export.language = args.language
        config.llm.language = "简体中文" if args.language == "zh-Hans" else args.language
    return config


def parse_arxiv_id(value: str) -> str:
    trimmed = value.strip()
    match = ARXIV_URL_RE.search(trimmed)
    if match:
        paper_id = match.group(1)
    else:
        paper_id = trimmed
    paper_id = paper_id.removesuffix(".pdf")
    if not ARXIV_ID_RE.fullmatch(paper_id):
        raise ValueError(f"Only arXiv abs/pdf/html URLs are supported for now: {value}")
    return paper_id


def strip_html_tags(value: str) -> str:
    text = re.sub(r"<[^>]+>", " ", value)
    text = unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def extract_meta_values(html: str, name: str) -> list[str]:
    pattern = re.compile(
        rf"<meta\s+[^>]*name=[\"']{re.escape(name)}[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>",
        re.IGNORECASE | re.DOTALL,
    )
    return [unescape(match).strip() for match in pattern.findall(html)]


def parse_arxiv_date(value: str | None) -> datetime | None:
    if not value:
        return None
    for fmt in ("%Y/%m/%d", "%Y-%m-%d", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            parsed = datetime.strptime(value.strip(), fmt)
            return parsed.replace(tzinfo=UTC)
        except ValueError:
            continue
    return None


def fetch_arxiv_abs_fallback(paper_id: str) -> Any:
    abs_id = re.sub(r"v\d+$", "", paper_id)
    abs_url = f"https://arxiv.org/abs/{paper_id}"
    logger.warning("Falling back to arXiv abs page metadata for {}", paper_id)
    response = requests.get(
        abs_url,
        timeout=ARXIV_HTML_TIMEOUT,
        headers={"User-Agent": "PaperDaily/1.0 (single-paper metadata fallback)"},
    )
    response.raise_for_status()
    html = response.text

    title_values = extract_meta_values(html, "citation_title")
    author_values = extract_meta_values(html, "citation_author")
    pdf_values = extract_meta_values(html, "citation_pdf_url")
    date_values = extract_meta_values(html, "citation_date")
    doi_values = extract_meta_values(html, "citation_doi")

    abstract_match = re.search(
        r"<blockquote[^>]*class=[\"'][^\"']*abstract[^\"']*[\"'][^>]*>(.*?)</blockquote>",
        html,
        re.IGNORECASE | re.DOTALL,
    )
    abstract = strip_html_tags(abstract_match.group(1)) if abstract_match else ""
    abstract = re.sub(r"^Abstract:\s*", "", abstract, flags=re.IGNORECASE).strip()

    subjects_match = re.search(
        r"<td[^>]*class=[\"']tablecell subjects[\"'][^>]*>(.*?)</td>",
        html,
        re.IGNORECASE | re.DOTALL,
    )
    categories: list[str] = []
    if subjects_match:
        subjects = strip_html_tags(subjects_match.group(1))
        categories = re.findall(r"\(([a-z-]+\.[A-Z]{2}(?:\.[A-Z]{2})?)\)", subjects)

    title = title_values[0] if title_values else f"arXiv:{paper_id}"
    authors = [SimpleNamespace(name=author) for author in author_values]
    published = parse_arxiv_date(date_values[0] if date_values else None)

    return SimpleNamespace(
        title=title,
        authors=authors,
        summary=abstract,
        pdf_url=pdf_values[0] if pdf_values else f"https://arxiv.org/pdf/{abs_id}.pdf",
        entry_id=f"https://arxiv.org/abs/{paper_id}",
        published=published,
        updated=published,
        categories=categories,
        doi=doi_values[0] if doi_values else None,
        source_url=lambda pid=paper_id: f"https://arxiv.org/e-print/{pid}",
    )


def fetch_arxiv_result(paper_id: str) -> Any:
    client = arxiv.Client(num_retries=0, delay_seconds=8)
    backoffs = (0, 15, 30, 60)
    last_error: Exception | None = None
    for attempt, backoff in enumerate(backoffs, start=1):
        if backoff:
            time.sleep(backoff)
        try:
            results = list(client.results(arxiv.Search(id_list=[paper_id])))
            if not results:
                raise ValueError(f"No arXiv paper found for {paper_id}")
            return results[0]
        except arxiv.HTTPError as exc:
            last_error = exc
            if exc.status not in {406, 429, 503} or attempt == len(backoffs):
                break
            logger.warning(
                "arXiv API returned HTTP {} for {}; retrying in {} seconds",
                exc.status,
                paper_id,
                backoffs[attempt],
            )
    if last_error is not None:
        if isinstance(last_error, arxiv.HTTPError) and last_error.status in {406, 429, 503}:
            return fetch_arxiv_abs_fallback(paper_id)
        raise last_error
    raise ValueError(f"No arXiv paper found for {paper_id}")


def make_openai_client(config: DictConfig) -> OpenAI | None:
    api_key = config.llm.api.get("key")
    if not api_key:
        logger.warning("OPENAI_API_KEY is not configured. Summary fields will use fallback text.")
        return None
    return OpenAI(api_key=api_key, base_url=config.llm.api.get("base_url"))


def build_single_paper_payload(
    config: DictConfig,
    *,
    paper_url: str,
    output_dir: Path,
    timezone_name: str,
    language: str,
    generated_at: datetime,
) -> dict[str, Any]:
    paper_id = parse_arxiv_id(paper_url)
    raw_paper = fetch_arxiv_result(paper_id)
    retriever = ArxivRetriever(config)
    paper = retriever.convert_to_paper(raw_paper)
    paper.score = 1.0

    openai_client = make_openai_client(config)
    if openai_client is not None:
        paper.generate_tldr(openai_client, config.llm)
        paper.generate_affiliations(openai_client, config.llm)
    else:
        paper.tldr = paper.abstract

    exporter = JSONFeedExporter(
        config,
        output_dir=output_dir,
        timezone_name=timezone_name,
        language=language,
        openai_client=openai_client,
    )
    summaries = exporter._build_paper_summaries([paper])
    feed = exporter._build_feed(
        [paper],
        summaries=summaries,
        total_candidates=1,
        generated_at=generated_at,
    )
    return asdict(feed)


def load_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def update_manifest(output_dir: Path, feed: dict[str, Any]) -> None:
    manifest_path = output_dir / "manifest.json"
    archive_path = f"archive/{feed['recommendation_date']}.json"
    manifest = load_json(manifest_path) or {
        "schema_version": "1.0",
        "latest": "latest.json",
        "latest_date": feed["recommendation_date"],
        "archive": [],
    }
    archive_by_date = {
        str(entry.get("date")): entry
        for entry in manifest.get("archive", [])
        if entry.get("date")
    }
    archive_by_date[feed["recommendation_date"]] = {
        "date": feed["recommendation_date"],
        "path": archive_path,
        "paper_count": len(feed.get("papers", [])),
    }
    manifest["schema_version"] = "1.0"
    manifest["latest"] = "latest.json"
    manifest["latest_date"] = feed["recommendation_date"]
    manifest["archive"] = sorted(archive_by_date.values(), key=lambda item: item["date"], reverse=True)
    write_json(manifest_path, manifest)


def prepend_to_latest(output_dir: Path, single_feed: dict[str, Any]) -> dict[str, Any]:
    latest_path = output_dir / "latest.json"
    existing_feed = load_json(latest_path)
    if existing_feed is None:
        merged_feed = single_feed
    else:
        new_paper = single_feed["papers"][0]
        existing_papers = [
            paper
            for paper in existing_feed.get("papers", [])
            if paper.get("id") != new_paper.get("id")
        ]
        merged_feed = existing_feed
        merged_feed["generated_at"] = single_feed["generated_at"]
        merged_feed["recommendation_date"] = single_feed["recommendation_date"]
        merged_feed["timezone"] = single_feed["timezone"]
        merged_feed["language"] = single_feed["language"]
        merged_feed["source"] = sorted(set(existing_feed.get("source", []) + single_feed.get("source", [])))
        merged_feed["papers"] = [new_paper, *existing_papers]
        stats = dict(merged_feed.get("stats", {}))
        stats["recommended_count"] = len(merged_feed["papers"])
        stats["llm_summary_count"] = sum(1 for paper in merged_feed["papers"] if paper.get("summary_zh"))
        stats["total_candidates"] = max(int(stats.get("total_candidates") or 0), len(merged_feed["papers"]))
        merged_feed["stats"] = stats

    archive_path = output_dir / "archive" / f"{merged_feed['recommendation_date']}.json"
    write_json(latest_path, merged_feed)
    write_json(archive_path, merged_feed)
    update_manifest(output_dir, merged_feed)
    return merged_feed


def main() -> int:
    dotenv.load_dotenv()
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    args = parse_args()
    config = build_config(args)
    configure_logging(bool(config.executor.debug))

    output_dir = ROOT / args.output_dir
    generated_at = datetime.now(UTC)
    single_feed = build_single_paper_payload(
        config,
        paper_url=args.paper_url,
        output_dir=output_dir,
        timezone_name=args.timezone,
        language=args.language,
        generated_at=generated_at,
    )
    merged_feed = prepend_to_latest(output_dir, single_feed)
    logger.info(
        "Added paper to app feed: date={}, paper={}, papers={}",
        merged_feed["recommendation_date"],
        single_feed["papers"][0]["id"],
        len(merged_feed["papers"]),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
