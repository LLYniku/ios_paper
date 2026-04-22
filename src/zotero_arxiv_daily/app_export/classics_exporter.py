from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import re
from typing import Iterable
import json


HEADING_RE = re.compile(r"^###\s+(?P<title>.+?)\s*$")
YEAR_RE = re.compile(r"(?<!\d)(19|20)\d{2}(?!\d)")
LINK_RE = re.compile(r"\[\[(?P<label>[^\]]+)\]\]\((?P<url>[^)]+)\)")


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
            papers.append(paper)

    categories = sorted({paper.category for paper in papers})
    return ClassicsFeed(
        schema_version="1.0",
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        source_title=source_title,
        source_repo=source_repo,
        readme_path=str(readme_path),
        paper_count=len(papers),
        categories=categories,
        papers=papers,
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
