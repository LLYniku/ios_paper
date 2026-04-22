from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from html import unescape
from html.parser import HTMLParser
import hashlib
import json
from pathlib import Path
import re
from typing import Any, Callable
from urllib.parse import urlparse, urlunparse

from loguru import logger
import requests
import trafilatura
from tqdm import tqdm

from ..llm import generate_text


HEADING_RE = re.compile(r"^###\s+(?P<title>.+?)\s*$")
YEAR_RE = re.compile(r"(?<!\d)(19|20)\d{2}(?!\d)")
LINK_RE = re.compile(r"\[\[(?P<label>[^\]]+)\]\]\((?P<url>[^)]+)\)")
SCHEMA_VERSION = "1.0"
REQUEST_TIMEOUT = 20


@dataclass(slots=True)
class ClassicPaper:
    id: str
    title: str
    category: str
    publication: str
    venue: str | None
    year: int | None
    paper_url: str
    code_url: str | None = None
    project_url: str | None = None
    abstract: str | None = None
    summary_zh: str | None = None
    tldr: str | None = None
    simple_intro: str | None = None


@dataclass(slots=True)
class ClassicsFeed:
    schema_version: str
    generated_at: str
    source_title: str
    source_repo: str
    readme_path: str
    paper_count: int
    categories: list[str]
    papers: list[ClassicPaper]

    def to_dict(self) -> dict:
        data = asdict(self)
        data["papers"] = [asdict(paper) for paper in self.papers]
        return data


class _MetaTagParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.meta: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "meta":
            return
        attr_map = {key.lower(): value for key, value in attrs if value}
        content = attr_map.get("content")
        if not content:
            return
        for key in ("name", "property", "http-equiv"):
            meta_name = attr_map.get(key)
            if meta_name:
                self.meta[meta_name.lower()] = unescape(content).strip()


def parse_awesome_llm_compression_readme(
    readme_path: Path,
    *,
    source_repo: str = "Awesome-LLM-Compression-main",
    source_title: str = "Awesome LLM Compression",
) -> ClassicsFeed:
    lines = readme_path.read_text(encoding="utf-8").splitlines()
    in_papers = False
    current_category: str | None = None
    papers: list[ClassicPaper] = []
    seen_ids: set[str] = set()

    for raw_line in lines:
        line = raw_line.strip()
        if line == "## Papers":
            in_papers = True
            continue
        if not in_papers:
            continue
        if line.startswith("## ") and line != "## Papers":
            break

        heading_match = HEADING_RE.match(line)
        if heading_match:
            current_category = heading_match.group("title").strip()
            continue

        if not line.startswith("- ") or current_category is None:
            continue

        paper = _parse_paper_line(
            line[2:].strip(),
            category=current_category,
        )
        if paper is not None:
            if paper.id in seen_ids:
                continue
            seen_ids.add(paper.id)
            papers.append(paper)

    categories = sorted({paper.category for paper in papers})
    return ClassicsFeed(
        schema_version=SCHEMA_VERSION,
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        source_title=source_title,
        source_repo=source_repo,
        readme_path=str(readme_path),
        paper_count=len(papers),
        categories=categories,
        papers=papers,
    )


def enrich_classics_feed(
    feed: ClassicsFeed,
    *,
    openai_client: Any | None = None,
    llm_params: dict[str, Any] | None = None,
    cache_path: Path | None = None,
    abstract_fetcher: Callable[[ClassicPaper], str | None] | None = None,
    summary_generator: Callable[[ClassicPaper, str | None], dict[str, str | None]] | None = None,
) -> ClassicsFeed:
    cache = _load_cache(cache_path)
    model_name = _llm_model_name(llm_params)
    enriched_papers: list[ClassicPaper] = []
    abstract_fetcher = abstract_fetcher or _fetch_abstract_for_paper

    for paper in tqdm(feed.papers, desc="Enriching classics", leave=False):
        cached = cache.get(paper.id, {})
        abstract = _resolve_abstract(
            paper,
            cached=cached,
            abstract_fetcher=abstract_fetcher,
        )
        bundle = _resolve_summary_bundle(
            paper,
            abstract=abstract,
            cached=cached,
            model_name=model_name,
            openai_client=openai_client,
            llm_params=llm_params,
            summary_generator=summary_generator,
        )
        enriched = ClassicPaper(
            id=paper.id,
            title=paper.title,
            category=paper.category,
            publication=paper.publication,
            venue=paper.venue,
            year=paper.year,
            paper_url=paper.paper_url,
            code_url=paper.code_url,
            project_url=paper.project_url,
            abstract=abstract,
            summary_zh=bundle.get("summary_zh"),
            tldr=bundle.get("tldr"),
            simple_intro=bundle.get("simple_intro"),
        )
        enriched_papers.append(enriched)
        cache[paper.id] = {
            "paper_url": paper.paper_url,
            "abstract": abstract,
            "summary_model": model_name,
            "summary_zh": enriched.summary_zh,
            "tldr": enriched.tldr,
            "simple_intro": enriched.simple_intro,
        }

    _save_cache(cache_path, cache)
    return ClassicsFeed(
        schema_version=feed.schema_version,
        generated_at=feed.generated_at,
        source_title=feed.source_title,
        source_repo=feed.source_repo,
        readme_path=feed.readme_path,
        paper_count=feed.paper_count,
        categories=list(feed.categories),
        papers=enriched_papers,
    )


def write_classics_feed(feed: ClassicsFeed, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(feed.to_dict(), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _parse_paper_line(line: str, *, category: str) -> ClassicPaper | None:
    title, publication_and_links = _split_title_and_body(line)
    links = list(LINK_RE.finditer(publication_and_links))
    if not title or not links:
        return None

    publication = publication_and_links[:links[0].start()].strip()
    paper_url = ""
    code_url = None
    project_url = None

    for link in links:
        label = link.group("label").strip().lower()
        url = link.group("url").strip()
        if "paper" in label and not paper_url:
            paper_url = url
        elif "code" in label or "toolkit" in label:
            code_url = code_url or url
        else:
            project_url = project_url or url

    if not paper_url:
        return None

    venue, year = _parse_publication(publication)
    paper_id = _stable_id(title, paper_url)

    return ClassicPaper(
        id=paper_id,
        title=title,
        category=category,
        publication=publication,
        venue=venue,
        year=year,
        paper_url=paper_url,
        code_url=code_url,
        project_url=project_url,
    )


def _split_title_and_body(line: str) -> tuple[str, str]:
    separator = " <br> "
    if separator in line:
        title, body = line.split(separator, 1)
        return title.strip(), body.strip()
    return line.strip(), ""


def _parse_publication(publication: str) -> tuple[str | None, int | None]:
    if not publication:
        return None, None

    matches = list(YEAR_RE.finditer(publication))
    if not matches:
        return publication.strip(), None

    year_match = matches[-1]
    year = int(year_match.group())
    venue = (publication[:year_match.start()] + publication[year_match.end():]).strip()
    venue = re.sub(r"\s{2,}", " ", venue).strip(" -·,")
    return (venue or publication.strip()), year


def _stable_id(title: str, paper_url: str) -> str:
    digest = hashlib.sha1(f"{title}\n{paper_url}".encode("utf-8")).hexdigest()[:12]
    return f"classic:{digest}"


def _llm_model_name(llm_params: dict[str, Any] | None) -> str | None:
    if not llm_params:
        return None
    generation_kwargs = llm_params.get("generation_kwargs") or {}
    model = generation_kwargs.get("model")
    return str(model) if model else None


def _load_cache(cache_path: Path | None) -> dict[str, dict[str, Any]]:
    if cache_path is None or not cache_path.exists():
        return {}
    try:
        return json.loads(cache_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        logger.warning(f"Invalid classics cache found at {cache_path}. Rebuilding cache.")
        return {}


def _save_cache(cache_path: Path | None, cache: dict[str, dict[str, Any]]) -> None:
    if cache_path is None:
        return
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(
        json.dumps(cache, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _resolve_abstract(
    paper: ClassicPaper,
    *,
    cached: dict[str, Any],
    abstract_fetcher: Callable[[ClassicPaper], str | None],
) -> str | None:
    if cached.get("paper_url") == paper.paper_url:
        cached_abstract = str(cached.get("abstract") or "").strip()
        if cached_abstract:
            return cached_abstract
    try:
        return abstract_fetcher(paper)
    except Exception as exc:
        logger.warning(f"Failed to fetch abstract for {paper.title}: {exc}")
        return None


def _resolve_summary_bundle(
    paper: ClassicPaper,
    *,
    abstract: str | None,
    cached: dict[str, Any],
    model_name: str | None,
    openai_client: Any | None,
    llm_params: dict[str, Any] | None,
    summary_generator: Callable[[ClassicPaper, str | None], dict[str, str | None]] | None,
) -> dict[str, str | None]:
    if (
        cached.get("paper_url") == paper.paper_url
        and cached.get("summary_model") == model_name
        and any(cached.get(key) for key in ("summary_zh", "tldr", "simple_intro"))
    ):
        return {
            "summary_zh": _optional_text(cached.get("summary_zh")),
            "tldr": _optional_text(cached.get("tldr")),
            "simple_intro": _optional_text(cached.get("simple_intro")),
        }

    if summary_generator is not None:
        return summary_generator(paper, abstract)

    if openai_client is not None and llm_params is not None and model_name:
        return _generate_summary_bundle(paper, abstract, openai_client=openai_client, llm_params=llm_params)

    return _fallback_summary_bundle(paper, abstract)


def _optional_text(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


def _generate_summary_bundle(
    paper: ClassicPaper,
    abstract: str | None,
    *,
    openai_client: Any,
    llm_params: dict[str, Any],
) -> dict[str, str | None]:
    prompt = (
        "请根据以下经典论文信息生成一个 JSON 对象，字段必须包含 "
        "summary_zh、tldr、simple_intro。\n"
        "- summary_zh: 用简体中文写 3 到 4 句话，总结问题、方法和价值。\n"
        "- tldr: 用简体中文写一句话，适合放在列表卡片中。\n"
        "- simple_intro: 用简体中文写 1 到 2 句话，解释这篇论文为什么值得看或适合作为经典参考。\n"
        "只返回 JSON，不要附加解释。\n\n"
        f"Title: {paper.title}\n"
        f"Category: {paper.category}\n"
        f"Publication: {paper.publication}\n"
        f"Venue: {paper.venue or 'Unknown'}\n"
        f"Year: {paper.year or 'Unknown'}\n"
        f"Abstract: {abstract or 'Abstract unavailable.'}\n"
    )
    try:
        content = generate_text(
            openai_client,
            llm_params,
            system_prompt=(
                "你是科研论文整理助手，正在把经典论文清单整理成适合手机阅读的中文卡片。"
                "必须返回合法 JSON。"
            ),
            user_prompt=prompt,
        )
        payload = _extract_json_object(content)
        fallback = _fallback_summary_bundle(paper, abstract)
        return {
            "summary_zh": _optional_text(payload.get("summary_zh")) or fallback["summary_zh"],
            "tldr": _optional_text(payload.get("tldr")) or fallback["tldr"],
            "simple_intro": _optional_text(payload.get("simple_intro")) or fallback["simple_intro"],
        }
    except Exception as exc:
        logger.warning(f"Failed to generate classics summary for {paper.title}: {exc}")
        return _fallback_summary_bundle(paper, abstract)


def _extract_json_object(content: str) -> dict[str, Any]:
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", content, flags=re.DOTALL)
        if match is None:
            raise
        return json.loads(match.group(0))


def _fallback_summary_bundle(paper: ClassicPaper, abstract: str | None) -> dict[str, str | None]:
    publication_line = _publication_line(paper)
    intro = f"这是一篇发表于{publication_line}的{paper.category}方向经典论文，适合作为该主题的代表性参考。"
    if abstract:
        tldr = f"{paper.category}方向代表工作，发表于{publication_line}，适合快速建立该主题的经典论文地图。"
        summary = (
            f"{intro}"
            f" 论文主要围绕“{paper.title}”展开。"
            f" 原文摘要可帮助你快速定位方法与实验设定。"
        )
    else:
        tldr = f"{paper.category}方向经典论文：{paper.title}"
        summary = f"{intro} 当前未抓到原始摘要，建议直接打开论文原文查看方法细节。"
    return {
        "summary_zh": summary,
        "tldr": tldr,
        "simple_intro": intro,
    }


def _publication_line(paper: ClassicPaper) -> str:
    if paper.venue and paper.year:
        return f"{paper.venue} {paper.year}"
    if paper.year:
        return str(paper.year)
    if paper.venue:
        return paper.venue
    return paper.publication or "未标注来源"


def _truncate_sentence(text: str, limit: int) -> str:
    cleaned = re.sub(r"\s+", " ", text).strip()
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 1].rstrip() + "…"


def _fetch_abstract_for_paper(paper: ClassicPaper) -> str | None:
    url = _normalize_metadata_url(paper.paper_url)
    if url is None:
        return None

    response = requests.get(
        url,
        timeout=REQUEST_TIMEOUT,
        headers={"User-Agent": "PaperDaily/1.0 (+https://github.com/LLYniku/ios_paper)"},
    )
    response.raise_for_status()
    html = response.text

    abstract = _extract_meta_abstract(html)
    if abstract:
        return abstract

    extracted = trafilatura.extract(html, include_comments=False, include_tables=False)
    if extracted:
        return _truncate_sentence(extracted, 1200)
    return None


def _normalize_metadata_url(url: str) -> str | None:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        return None
    if parsed.path.lower().endswith(".pdf"):
        if "arxiv.org" in parsed.netloc:
            abs_path = parsed.path.replace("/pdf/", "/abs/").removesuffix(".pdf")
            return urlunparse(parsed._replace(path=abs_path, query="", fragment=""))
        if "aclanthology.org" in parsed.netloc:
            return urlunparse(parsed._replace(path=parsed.path.removesuffix(".pdf"), query="", fragment=""))
        return None
    return url


def _extract_meta_abstract(html: str) -> str | None:
    parser = _MetaTagParser()
    parser.feed(html)
    for key in (
        "citation_abstract",
        "dc.description",
        "dc.description.abstract",
        "description",
        "og:description",
        "twitter:description",
    ):
        value = _optional_text(parser.meta.get(key))
        if value:
            return _truncate_sentence(value, 1800)
    return None
