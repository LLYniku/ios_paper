from __future__ import annotations

from dataclasses import asdict
from datetime import UTC, datetime
import hashlib
import json
from pathlib import Path
import re
from typing import Any
from zoneinfo import ZoneInfo

from loguru import logger
from omegaconf import DictConfig

from ..llm import generate_text
from ..protocol import Paper
from .models import AppFeed, AppFeedConfig, AppFeedManifest, AppFeedStats, AppManifestEntry, AppPaper

SCHEMA_VERSION = "1.0"
ARXIV_ID_RE = re.compile(r"/(?:abs|pdf)/([^/?#]+)")
DOI_RE = re.compile(r"/content/([^v?#]+)v\d+")


def build_stable_paper_id(paper: Paper) -> str:
    if paper.source == "arxiv":
        match = ARXIV_ID_RE.search(paper.url) or (ARXIV_ID_RE.search(paper.pdf_url) if paper.pdf_url else None)
        if match:
            paper_id = match.group(1).replace(".pdf", "")
            paper_id = re.sub(r"v\d+$", "", paper_id)
            return f"arxiv:{paper_id}"

    if paper.doi:
        return f"{paper.source}:{paper.doi.lower()}"

    doi_match = DOI_RE.search(paper.url)
    if doi_match:
        return f"{paper.source}:{doi_match.group(1).lower()}"

    fingerprint = hashlib.sha1(
        f"{paper.source}|{paper.url}|{paper.title}".encode("utf-8")
    ).hexdigest()[:16]
    return f"{paper.source}:{fingerprint}"


def _format_datetime(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _extract_config_categories(config: DictConfig) -> list[str]:
    categories: list[str] = []
    for source_name in config.executor.source:
        source_config = config.source.get(source_name)
        if source_config is None:
            continue
        source_categories = source_config.get("category")
        if source_categories is None:
            continue
        for category in source_categories:
            if category not in categories:
                categories.append(str(category))
    return categories


def _language_label(language_code: str) -> str:
    if language_code == "zh-Hans":
        return "简体中文"
    if language_code == "zh-Hant":
        return "繁體中文"
    return language_code


class JSONFeedExporter:
    def __init__(
        self,
        config: DictConfig,
        output_dir: str | Path,
        timezone_name: str,
        language: str,
        *,
        openai_client: Any | None = None,
    ) -> None:
        self.config = config
        self.output_dir = Path(output_dir)
        self.timezone_name = timezone_name
        self.language = language
        self.openai_client = openai_client
        self.summary_top_n = int(self.config.app_export.get("summary_top_n", 20))
        self.cache_path = self.output_dir / "cache" / "llm_summaries.json"

    def export(
        self,
        papers: list[Paper],
        *,
        total_candidates: int,
        generated_at: datetime | None = None,
    ) -> AppFeed:
        generated_at = generated_at or datetime.now(UTC)
        summaries = self._build_paper_summaries(papers)
        feed = self._build_feed(
            papers,
            summaries=summaries,
            total_candidates=total_candidates,
            generated_at=generated_at,
        )
        self._write_feed_bundle(feed)
        return feed

    def _build_paper_summaries(self, papers: list[Paper]) -> dict[str, dict[str, Any]]:
        cache = self._load_cache()
        summary_model = self.config.llm.generation_kwargs.get("model")
        summaries: dict[str, dict[str, Any]] = {}
        for index, paper in enumerate(papers):
            paper_id = build_stable_paper_id(paper)
            cache_key = self._summary_cache_key(paper, paper_id, summary_model)
            if index < self.summary_top_n and self.openai_client is not None and summary_model:
                if cache_key not in cache:
                    cache[cache_key] = self._generate_summary_bundle(paper)
                summaries[paper_id] = cache[cache_key]
            else:
                summaries[paper_id] = self._fallback_summary_bundle(paper)
        self._save_cache(cache)
        return summaries

    def _summary_cache_key(self, paper: Paper, paper_id: str, model: str | None) -> str:
        abstract_hash = hashlib.sha1((paper.abstract or "").encode("utf-8")).hexdigest()
        return "|".join([paper_id, abstract_hash, model or "no-model", self.language])

    def _load_cache(self) -> dict[str, dict[str, Any]]:
        if not self.cache_path.exists():
            return {}
        try:
            return json.loads(self.cache_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            logger.warning(f"Invalid summary cache found at {self.cache_path}. Rebuilding cache.")
            return {}

    def _save_cache(self, cache: dict[str, dict[str, Any]]) -> None:
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        self.cache_path.write_text(
            json.dumps(cache, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _generate_summary_bundle(self, paper: Paper) -> dict[str, Any]:
        prompt = (
            "请根据以下论文信息生成一个 JSON 对象，字段必须包含 "
            "summary_zh、tldr、recommendation_reason、keywords。\n"
            "- summary_zh: 用简体中文写 3 到 5 句话。\n"
            "- tldr: 用简体中文写一句话。\n"
            "- recommendation_reason: 只概括研究主题相似性，不要提及任何用户私人文献标题。\n"
            "- keywords: 输出 3 到 6 个关键词数组。\n"
            "只返回 JSON，不要附加解释。\n\n"
            f"Title: {paper.title}\n"
            f"Authors: {', '.join(paper.authors)}\n"
            f"Source: {paper.source}\n"
            f"Categories: {', '.join(paper.categories)}\n"
            f"Abstract: {paper.abstract}\n"
        )
        try:
            content = generate_text(
                self.openai_client,
                self.config.llm,
                system_prompt=(
                    f"你是科研论文推荐助手。输出语言为{_language_label(self.language)}。"
                    "必须返回合法 JSON。"
                ),
                user_prompt=prompt,
            )
            payload = self._extract_json_object(content)
            summary = str(payload.get("summary_zh") or "").strip() or None
            tldr = str(payload.get("tldr") or "").strip() or paper.tldr or None
            recommendation_reason = str(payload.get("recommendation_reason") or "").strip() or None
            keywords = payload.get("keywords") or []
            if not isinstance(keywords, list):
                keywords = []
            keywords = [str(keyword).strip() for keyword in keywords if str(keyword).strip()]
            return {
                "summary_zh": summary,
                "tldr": tldr,
                "recommendation_reason": recommendation_reason,
                "keywords": keywords[:6],
            }
        except Exception as exc:
            logger.warning(f"Failed to generate app summary for {paper.title}: {exc}")
            return self._fallback_summary_bundle(paper)

    def _extract_json_object(self, content: str) -> dict[str, Any]:
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", content, flags=re.DOTALL)
            if match is None:
                raise
            return json.loads(match.group(0))

    def _fallback_summary_bundle(self, paper: Paper) -> dict[str, Any]:
        keywords = [keyword for keyword in paper.keywords if keyword]
        if not keywords:
            keywords = list(paper.categories[:4])
        if not keywords:
            words = re.findall(r"[A-Za-z][A-Za-z0-9.+-]{2,}", paper.title)
            keywords = words[:4]
        focus = "、".join((paper.categories or [paper.source])[:2])
        recommendation_reason = f"推荐理由：这篇论文与您近期关注的{focus}主题相近，且在今日候选中相关性较高。"
        return {
            "summary_zh": paper.summary_zh,
            "tldr": paper.tldr or (paper.abstract[:160] if paper.abstract else None),
            "recommendation_reason": paper.recommendation_reason or recommendation_reason,
            "keywords": keywords,
        }

    def _build_feed(
        self,
        papers: list[Paper],
        *,
        summaries: dict[str, dict[str, Any]],
        total_candidates: int,
        generated_at: datetime,
    ) -> AppFeed:
        zone = ZoneInfo(self.timezone_name)
        recommendation_date = generated_at.astimezone(zone).date().isoformat()
        items: list[AppPaper] = []
        llm_summary_count = 0
        for paper in papers:
            paper_id = build_stable_paper_id(paper)
            summary_bundle = summaries.get(paper_id, self._fallback_summary_bundle(paper))
            summary_text = summary_bundle.get("summary_zh")
            if summary_text:
                llm_summary_count += 1
            items.append(
                AppPaper(
                    id=paper_id,
                    source=paper.source,
                    title=paper.title,
                    authors=list(paper.authors),
                    abstract=paper.abstract or None,
                    summary_zh=summary_text,
                    tldr=summary_bundle.get("tldr"),
                    recommendation_reason=summary_bundle.get("recommendation_reason"),
                    relevance_score=round(paper.score, 4) if paper.score is not None else None,
                    published_at=_format_datetime(paper.published_at),
                    updated_at=_format_datetime(paper.updated_at),
                    categories=list(paper.categories),
                    keywords=list(summary_bundle.get("keywords") or paper.keywords),
                    affiliations=list(paper.affiliations or []),
                    pdf_url=paper.pdf_url,
                    abs_url=paper.url,
                    code_url=paper.code_url,
                    project_url=paper.project_url,
                    doi=paper.doi,
                )
            )

        feed_config = AppFeedConfig(
            categories=_extract_config_categories(self.config),
            max_paper_num=int(self.config.executor.max_paper_num),
            model=self.config.llm.generation_kwargs.get("model") or "disabled",
        )
        return AppFeed(
            schema_version=SCHEMA_VERSION,
            generated_at=_format_datetime(generated_at),
            recommendation_date=recommendation_date,
            timezone=self.timezone_name,
            source=sorted({paper.source for paper in papers}) or list(self.config.executor.source),
            language=self.language,
            config=feed_config,
            stats=AppFeedStats(
                total_candidates=total_candidates,
                recommended_count=len(items),
                llm_summary_count=llm_summary_count,
            ),
            papers=items,
        )

    def _write_feed_bundle(self, feed: AppFeed) -> None:
        self.output_dir.mkdir(parents=True, exist_ok=True)
        archive_dir = self.output_dir / "archive"
        archive_dir.mkdir(parents=True, exist_ok=True)

        latest_path = self.output_dir / "latest.json"
        archive_relative_path = Path("archive") / f"{feed.recommendation_date}.json"
        archive_path = self.output_dir / archive_relative_path

        self._write_json(latest_path, feed)
        self._write_json(archive_path, feed)

        manifest = self._build_manifest(feed, archive_relative_path.as_posix())
        self._write_json(self.output_dir / "manifest.json", manifest)

    def _build_manifest(self, feed: AppFeed, archive_path: str) -> AppFeedManifest:
        manifest_path = self.output_dir / "manifest.json"
        archive_entries: dict[str, AppManifestEntry] = {}
        if manifest_path.exists():
            try:
                previous_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                for entry in previous_manifest.get("archive", []):
                    archive_entries[entry["date"]] = AppManifestEntry(
                        date=entry["date"],
                        path=entry["path"],
                        paper_count=int(entry["paper_count"]),
                    )
            except json.JSONDecodeError:
                logger.warning(f"Invalid manifest at {manifest_path}; recreating it.")
        archive_entries[feed.recommendation_date] = AppManifestEntry(
            date=feed.recommendation_date,
            path=archive_path,
            paper_count=feed.stats.recommended_count,
        )
        sorted_archive = sorted(archive_entries.values(), key=lambda entry: entry.date, reverse=True)
        return AppFeedManifest(
            schema_version=SCHEMA_VERSION,
            latest="latest.json",
            latest_date=feed.recommendation_date,
            archive=sorted_archive,
        )

    def _write_json(self, path: Path, payload: Any) -> None:
        path.write_text(
            json.dumps(asdict(payload), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
