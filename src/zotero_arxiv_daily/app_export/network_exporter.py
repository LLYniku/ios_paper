from __future__ import annotations

from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
from typing import Any

import feedparser
from loguru import logger
import requests
from tqdm import tqdm

from ..llm import generate_text
from ..protocol import CorpusPaper


REQUEST_TIMEOUT = 20
SCHEMA_VERSION = "1.0"


@dataclass(slots=True)
class NetworkItem:
    id: str
    platform: str
    content_type: str
    title: str
    creator: str
    source_label: str
    published_at: str | None
    url: str
    raw_excerpt: str
    summary_zh: str | None
    tldr: str | None
    recommendation_reason: str | None
    relevance_score: float | None
    tags: list[str] = field(default_factory=list)
    thumbnail_url: str | None = None
    venue: str | None = None
    year: int | None = None


@dataclass(slots=True)
class NetworkFeedStats:
    total_candidates: int
    recommended_count: int
    llm_summary_count: int


@dataclass(slots=True)
class NetworkFeedConfig:
    max_item_num: int
    summary_top_n: int
    platforms: list[str]


@dataclass(slots=True)
class NetworkFeed:
    schema_version: str
    generated_at: str
    recommendation_date: str
    timezone: str
    language: str
    config: NetworkFeedConfig
    stats: NetworkFeedStats
    items: list[NetworkItem]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "generated_at": self.generated_at,
            "recommendation_date": self.recommendation_date,
            "timezone": self.timezone,
            "language": self.language,
            "config": asdict(self.config),
            "stats": asdict(self.stats),
            "items": [asdict(item) for item in self.items],
        }


@dataclass(slots=True)
class NetworkManifestEntry:
    date: str
    path: str
    item_count: int


@dataclass(slots=True)
class NetworkManifest:
    schema_version: str
    latest: str
    latest_date: str
    archive: list[NetworkManifestEntry]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "latest": self.latest,
            "latest_date": self.latest_date,
            "archive": [asdict(entry) for entry in self.archive],
        }


@dataclass(slots=True)
class NetworkCandidate:
    id: str
    platform: str
    content_type: str
    title: str
    creator: str
    source_label: str
    url: str
    raw_excerpt: str
    tags: list[str]
    published_at: datetime | None = None
    thumbnail_url: str | None = None
    venue: str | None = None
    year: int | None = None
    score: float | None = None
    summary_zh: str | None = None
    tldr: str | None = None
    recommendation_reason: str | None = None

    def ranking_text(self) -> str:
        parts = [
            self.title,
            self.creator,
            self.source_label,
            self.venue or "",
            " ".join(self.tags),
            self.raw_excerpt,
        ]
        return "\n".join(part for part in parts if part).strip()

    def to_item(self) -> NetworkItem:
        return NetworkItem(
            id=self.id,
            platform=self.platform,
            content_type=self.content_type,
            title=self.title,
            creator=self.creator,
            source_label=self.source_label,
            published_at=_isoformat(self.published_at),
            url=self.url,
            raw_excerpt=self.raw_excerpt,
            summary_zh=self.summary_zh,
            tldr=self.tldr,
            recommendation_reason=self.recommendation_reason,
            relevance_score=round(self.score, 4) if self.score is not None else None,
            tags=list(self.tags),
            thumbnail_url=self.thumbnail_url,
            venue=self.venue,
            year=self.year,
        )


def collect_network_candidates(config: Any) -> list[NetworkCandidate]:
    seen_ids: set[str] = set()
    candidates: list[NetworkCandidate] = []
    for source_name in _source_names(config):
        fetcher = {
            "github": _fetch_github_candidates,
            "openreview": _fetch_openreview_candidates,
            "youtube": _fetch_youtube_candidates,
        }.get(source_name)
        if fetcher is None:
            logger.warning("Unknown network source '{}', skipping", source_name)
            continue
        try:
            source_items = fetcher(config)
        except Exception as exc:
            logger.warning("Network source '{}' failed: {}", source_name, exc)
            continue
        for item in source_items:
            if item.id in seen_ids:
                continue
            seen_ids.add(item.id)
            candidates.append(item)
    return candidates


def rerank_network_candidates(
    candidates: Sequence[NetworkCandidate],
    corpus: Sequence[CorpusPaper],
    reranker: Any,
) -> list[NetworkCandidate]:
    if not candidates or not corpus:
        return []

    corpus_sorted = sorted(corpus, key=lambda item: item.added_date, reverse=True)
    import numpy as np

    time_decay_weight = 1 / (1 + np.log10(np.arange(len(corpus_sorted)) + 1))
    time_decay_weight = time_decay_weight / time_decay_weight.sum()
    similarity = reranker.get_similarity_score(
        [candidate.ranking_text() for candidate in candidates],
        [paper.abstract for paper in corpus_sorted],
    )
    scores = (similarity * time_decay_weight).sum(axis=1) * 10

    ranked: list[NetworkCandidate] = []
    for score, candidate in zip(scores, candidates):
        ranked.append(
            NetworkCandidate(
                id=candidate.id,
                platform=candidate.platform,
                content_type=candidate.content_type,
                title=candidate.title,
                creator=candidate.creator,
                source_label=candidate.source_label,
                url=candidate.url,
                raw_excerpt=candidate.raw_excerpt,
                tags=list(candidate.tags),
                published_at=candidate.published_at,
                thumbnail_url=candidate.thumbnail_url,
                venue=candidate.venue,
                year=candidate.year,
                score=float(score),
                summary_zh=candidate.summary_zh,
                tldr=candidate.tldr,
                recommendation_reason=candidate.recommendation_reason,
            )
        )
    return sorted(ranked, key=lambda item: item.score or 0, reverse=True)


class NetworkFeedExporter:
    def __init__(
        self,
        config: Any,
        *,
        output_dir: Path,
        timezone_name: str,
        language: str,
        openai_client: Any | None = None,
        cache_path: Path | None = None,
        summary_generator: Callable[[NetworkCandidate], dict[str, str | None]] | None = None,
    ) -> None:
        self.config = config
        self.output_dir = output_dir
        self.timezone_name = timezone_name
        self.language = language
        self.openai_client = openai_client
        self.cache_path = cache_path
        self.summary_generator = summary_generator

    def export(self, candidates: Sequence[NetworkCandidate]) -> NetworkFeed:
        now_utc = datetime.now(UTC).replace(microsecond=0)
        recommendation_date = _recommendation_date(now_utc, self.timezone_name)
        max_item_num = int(_network_config(self.config).get("max_item_num", 30))
        summary_top_n = int(_network_config(self.config).get("summary_top_n", 20))
        selected = [self._clone_candidate(candidate) for candidate in candidates[:max_item_num]]
        self._enrich_candidates(selected[:summary_top_n])

        llm_summary_count = sum(1 for candidate in selected if candidate.summary_zh)
        feed = NetworkFeed(
            schema_version=SCHEMA_VERSION,
            generated_at=_isoformat(now_utc),
            recommendation_date=recommendation_date,
            timezone=self.timezone_name,
            language=self.language,
            config=NetworkFeedConfig(
                max_item_num=max_item_num,
                summary_top_n=summary_top_n,
                platforms=sorted({candidate.platform for candidate in candidates}),
            ),
            stats=NetworkFeedStats(
                total_candidates=len(candidates),
                recommended_count=len(selected),
                llm_summary_count=llm_summary_count,
            ),
            items=[candidate.to_item() for candidate in selected],
        )
        self._write_feed(feed)
        return feed

    def _enrich_candidates(self, candidates: Sequence[NetworkCandidate]) -> None:
        cache = _load_cache(self.cache_path)
        model_name = _llm_model_name(_mapping_get(self.config, "llm", "generation_kwargs"))
        for candidate in tqdm(candidates, desc="Summarizing network items", leave=False):
            fingerprint = _summary_fingerprint(candidate, model_name)
            cached = cache.get(candidate.id)
            if cached and cached.get("fingerprint") == fingerprint:
                candidate.summary_zh = cached.get("summary_zh")
                candidate.tldr = cached.get("tldr")
                candidate.recommendation_reason = cached.get("recommendation_reason")
                continue

            bundle = self._generate_summary_bundle(candidate)
            candidate.summary_zh = bundle.get("summary_zh")
            candidate.tldr = bundle.get("tldr")
            candidate.recommendation_reason = bundle.get("recommendation_reason")
            cache[candidate.id] = {
                "fingerprint": fingerprint,
                "summary_zh": candidate.summary_zh,
                "tldr": candidate.tldr,
                "recommendation_reason": candidate.recommendation_reason,
            }
        _save_cache(self.cache_path, cache)

    def _generate_summary_bundle(self, candidate: NetworkCandidate) -> dict[str, str | None]:
        if self.summary_generator is not None:
            return self.summary_generator(candidate)
        if self.openai_client is None:
            return _fallback_summary_bundle(candidate)

        llm_params = _mapping_get(self.config, "llm")
        excerpt = candidate.raw_excerpt.strip() or candidate.title
        user_prompt = (
            f"平台: {candidate.platform}\n"
            f"类型: {candidate.content_type}\n"
            f"标题: {candidate.title}\n"
            f"作者/发布者: {candidate.creator}\n"
            f"来源: {candidate.source_label}\n"
            f"标签: {', '.join(candidate.tags)}\n"
            f"原文链接: {candidate.url}\n"
            f"原始内容摘录:\n{excerpt}\n\n"
            "请输出一个 JSON 对象，字段严格为 summary_zh、tldr、recommendation_reason。"
        )
        raw = generate_text(
            self.openai_client,
            llm_params,
            system_prompt=(
                "你是一个帮助研究者筛选网络内容的助手。"
                "请用简体中文输出合法 JSON，不要使用 Markdown 代码块。"
                "summary_zh 用 3-4 句话概括核心信息；"
                "tldr 用 1 句话总结；"
                "recommendation_reason 用 1 句话说明它为什么与科研主题相关，"
                "不要暴露任何私人文献标题或私人信息。"
            ),
            user_prompt=user_prompt,
        )
        return _parse_summary_json(raw, fallback=_fallback_summary_bundle(candidate))

    def _write_feed(self, feed: NetworkFeed) -> None:
        archive_dir = self.output_dir / "archive"
        latest_path = self.output_dir / "latest.json"
        archive_path = archive_dir / f"{feed.recommendation_date}.json"
        manifest_path = self.output_dir / "manifest.json"

        self.output_dir.mkdir(parents=True, exist_ok=True)
        archive_dir.mkdir(parents=True, exist_ok=True)
        serialized = json.dumps(feed.to_dict(), ensure_ascii=False, indent=2) + "\n"
        latest_path.write_text(serialized, encoding="utf-8")
        archive_path.write_text(serialized, encoding="utf-8")

        archive_entries = _existing_manifest_entries(manifest_path)
        entry = NetworkManifestEntry(
            date=feed.recommendation_date,
            path=f"archive/{feed.recommendation_date}.json",
            item_count=feed.stats.recommended_count,
        )
        updated = [existing for existing in archive_entries if existing.date != entry.date]
        updated.insert(0, entry)
        updated.sort(key=lambda item: item.date, reverse=True)
        manifest = NetworkManifest(
            schema_version=SCHEMA_VERSION,
            latest="latest.json",
            latest_date=feed.recommendation_date,
            archive=updated,
        )
        manifest_path.write_text(
            json.dumps(manifest.to_dict(), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    @staticmethod
    def _clone_candidate(candidate: NetworkCandidate) -> NetworkCandidate:
        return NetworkCandidate(
            id=candidate.id,
            platform=candidate.platform,
            content_type=candidate.content_type,
            title=candidate.title,
            creator=candidate.creator,
            source_label=candidate.source_label,
            url=candidate.url,
            raw_excerpt=candidate.raw_excerpt,
            tags=list(candidate.tags),
            published_at=candidate.published_at,
            thumbnail_url=candidate.thumbnail_url,
            venue=candidate.venue,
            year=candidate.year,
            score=candidate.score,
        )


def _fetch_github_candidates(config: Any) -> list[NetworkCandidate]:
    github_config = _mapping_get(_network_config(config), "github")
    queries = _string_list(github_config.get("queries"))
    per_query = int(github_config.get("per_query", 20))
    search_days = int(github_config.get("search_days", 14))
    if not queries:
        return []

    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "paperdaily-network-feed",
    }
    token = (
        github_config.get("token")
        or os.getenv("GITHUB_TOKEN")
        or os.getenv("GH_TOKEN")
    )
    if token:
        headers["Authorization"] = f"Bearer {token}"

    cutoff = (datetime.now(UTC) - timedelta(days=search_days)).date().isoformat()
    session = requests.Session()
    candidates: list[NetworkCandidate] = []
    for query in queries:
        response = session.get(
            "https://api.github.com/search/repositories",
            headers=headers,
            params={
                "q": f"{query} in:name,description,readme pushed:>{cutoff}",
                "sort": "updated",
                "order": "desc",
                "per_page": per_query,
            },
            timeout=REQUEST_TIMEOUT,
        )
        response.raise_for_status()
        payload = response.json()
        for item in payload.get("items", []):
            topics = [topic for topic in item.get("topics", []) if isinstance(topic, str)]
            language = item.get("language")
            description = item.get("description") or ""
            repo_tags = list(topics)
            if language:
                repo_tags.append(str(language))
            excerpt_parts = [
                description,
                f"Topics: {', '.join(topics)}" if topics else "",
                f"Language: {language}" if language else "",
                f"Stars: {item.get('stargazers_count', 0)}",
            ]
            owner = item.get("owner", {}) or {}
            candidates.append(
                NetworkCandidate(
                    id=f"github:repo:{str(item.get('full_name', '')).lower()}",
                    platform="github",
                    content_type="repository",
                    title=str(item.get("name") or item.get("full_name") or "Untitled Repository"),
                    creator=str(owner.get("login") or "GitHub"),
                    source_label=str(item.get("full_name") or item.get("html_url") or "GitHub"),
                    url=str(item.get("html_url") or ""),
                    raw_excerpt="\n".join(part for part in excerpt_parts if part).strip(),
                    tags=repo_tags,
                    published_at=_parse_iso_datetime(item.get("pushed_at") or item.get("updated_at")),
                    thumbnail_url=str(owner.get("avatar_url")) if owner.get("avatar_url") else None,
                )
            )
    return candidates


def _fetch_openreview_candidates(config: Any) -> list[NetworkCandidate]:
    source_config = _mapping_get(_network_config(config), "openreview")
    venues = _string_list(source_config.get("venues"))
    per_venue = int(source_config.get("per_venue", 25))
    if not venues:
        return []

    session = requests.Session()
    candidates: list[NetworkCandidate] = []
    for venue in venues:
        response = session.get(
            "https://api2.openreview.net/notes",
            params={
                "content.venueid": venue,
                "limit": per_venue,
            },
            timeout=REQUEST_TIMEOUT,
        )
        response.raise_for_status()
        for note in response.json().get("notes", []):
            content = note.get("content", {}) or {}
            title = _openreview_value(content.get("title"))
            abstract = _openreview_value(content.get("abstract"))
            tldr = _openreview_value(content.get("TLDR"))
            keywords = _string_list(_openreview_value(content.get("keywords")))
            authors = _string_list(_openreview_value(content.get("authors")))
            forum_id = note.get("forum") or note.get("id")
            note_id = str(note.get("id") or forum_id or hashlib.sha1(title.encode("utf-8")).hexdigest()[:12])
            candidates.append(
                NetworkCandidate(
                    id=f"openreview:{note_id}",
                    platform="openreview",
                    content_type="paper",
                    title=title or "Untitled OpenReview Paper",
                    creator=", ".join(authors[:3]) if authors else "OpenReview",
                    source_label=venue,
                    url=f"https://openreview.net/forum?id={forum_id}",
                    raw_excerpt="\n".join(part for part in [tldr or "", abstract or ""] if part).strip(),
                    tags=keywords,
                    published_at=_parse_openreview_datetime(note),
                    venue=venue,
                    year=_extract_year(venue),
                )
            )
    return candidates


def _fetch_youtube_candidates(config: Any) -> list[NetworkCandidate]:
    youtube_config = _mapping_get(_network_config(config), "youtube")
    channels = youtube_config.get("channels") or []
    per_channel = int(youtube_config.get("per_channel", 10))
    if not channels:
        return []

    candidates: list[NetworkCandidate] = []
    for channel in channels:
        channel_id, channel_name = _parse_youtube_channel(channel)
        if not channel_id:
            continue
        feed = feedparser.parse(f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}")
        resolved_name = channel_name or str(feed.feed.get("title") or "YouTube")
        for entry in list(feed.entries)[:per_channel]:
            tags = [str(tag.term) for tag in entry.get("tags", []) if getattr(tag, "term", None)]
            summary = str(
                entry.get("summary")
                or entry.get("media_description")
                or entry.get("subtitle")
                or ""
            ).strip()
            video_id = (
                entry.get("yt_videoid")
                or entry.get("id")
                or hashlib.sha1(str(entry.get("link")).encode("utf-8")).hexdigest()[:12]
            )
            thumbnail_url = None
            media_thumbnail = entry.get("media_thumbnail") or []
            if media_thumbnail and isinstance(media_thumbnail, list):
                thumbnail_url = media_thumbnail[0].get("url")
            candidates.append(
                NetworkCandidate(
                    id=f"youtube:{video_id}",
                    platform="youtube",
                    content_type="video",
                    title=str(entry.get("title") or "Untitled Video"),
                    creator=str(entry.get("author") or resolved_name),
                    source_label=resolved_name,
                    url=str(entry.get("link") or ""),
                    raw_excerpt=summary,
                    tags=tags,
                    published_at=_parse_iso_datetime(entry.get("published") or entry.get("updated")),
                    thumbnail_url=thumbnail_url,
                )
            )
    return candidates


def _network_config(config: Any) -> Mapping[str, Any]:
    if isinstance(config, Mapping):
        return config.get("network", {}) or {}
    return getattr(config, "network", {}) or {}


def _source_names(config: Any) -> list[str]:
    return [str(value) for value in _network_config(config).get("source", []) or []]


def _mapping_get(data: Any, *keys: str) -> Mapping[str, Any]:
    current = data
    for key in keys:
        if isinstance(current, Mapping):
            current = current.get(key, {})
        else:
            current = getattr(current, key, {})
    if isinstance(current, Mapping):
        return current
    try:
        return {str(key): current[key] for key in current.keys()}
    except Exception:
        return {}


def _string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, Iterable):
        return [str(item) for item in value if str(item).strip()]
    return []


def _recommendation_date(now_utc: datetime, timezone_name: str) -> str:
    from zoneinfo import ZoneInfo

    return now_utc.astimezone(ZoneInfo(timezone_name)).date().isoformat()


def _isoformat(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _parse_iso_datetime(raw_value: Any) -> datetime | None:
    if not raw_value:
        return None
    try:
        return datetime.fromisoformat(str(raw_value).replace("Z", "+00:00")).astimezone(UTC)
    except ValueError:
        return None


def _parse_openreview_datetime(note: Mapping[str, Any]) -> datetime | None:
    for key in ("pdate", "cdate", "tcdate", "tmdate"):
        value = note.get(key)
        if value is None:
            continue
        try:
            return datetime.fromtimestamp(int(value) / 1000, tz=UTC)
        except (TypeError, ValueError, OSError):
            continue
    return None


def _openreview_value(value: Any) -> Any:
    if isinstance(value, Mapping) and "value" in value:
        return value["value"]
    return value


def _extract_year(value: str | None) -> int | None:
    if not value:
        return None
    match = re.search(r"(19|20)\d{2}", value)
    if not match:
        return None
    return int(match.group(0))


def _parse_youtube_channel(raw_value: Any) -> tuple[str | None, str | None]:
    if isinstance(raw_value, Mapping):
        channel_id = raw_value.get("channel_id") or raw_value.get("id")
        title = raw_value.get("title") or raw_value.get("name")
        return (str(channel_id) if channel_id else None, str(title) if title else None)
    text = str(raw_value).strip()
    if not text:
        return None, None
    return text, None


def _llm_model_name(params: Mapping[str, Any]) -> str:
    return str(params.get("model") or "unknown-model")


def _summary_fingerprint(candidate: NetworkCandidate, model_name: str) -> str:
    payload = json.dumps(
        {
            "title": candidate.title,
            "raw_excerpt": candidate.raw_excerpt,
            "platform": candidate.platform,
            "model": model_name,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()


def _fallback_summary_bundle(candidate: NetworkCandidate) -> dict[str, str]:
    summary = candidate.raw_excerpt.strip() or candidate.title
    condensed = re.sub(r"\s+", " ", summary)
    condensed = condensed[:180].strip()
    tag_hint = candidate.tags[0] if candidate.tags else candidate.platform
    return {
        "summary_zh": condensed or "暂无中文总结",
        "tldr": condensed[:80] if condensed else candidate.title,
        "recommendation_reason": f"与当前研究兴趣中的 {tag_hint} 主题相近。",
    }


def _parse_summary_json(raw_text: str, *, fallback: dict[str, str]) -> dict[str, str | None]:
    candidate = raw_text.strip()
    if candidate.startswith("```"):
        candidate = re.sub(r"^```(?:json)?|```$", "", candidate, flags=re.MULTILINE).strip()
    try:
        payload = json.loads(candidate)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", candidate, flags=re.DOTALL)
        if match is None:
            return fallback
        try:
            payload = json.loads(match.group(0))
        except json.JSONDecodeError:
            return fallback
    return {
        "summary_zh": str(payload.get("summary_zh") or fallback["summary_zh"]).strip(),
        "tldr": str(payload.get("tldr") or fallback["tldr"]).strip(),
        "recommendation_reason": str(
            payload.get("recommendation_reason") or fallback["recommendation_reason"]
        ).strip(),
    }


def _existing_manifest_entries(path: Path) -> list[NetworkManifestEntry]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    entries: list[NetworkManifestEntry] = []
    for item in data.get("archive", []):
        try:
            entries.append(
                NetworkManifestEntry(
                    date=str(item["date"]),
                    path=str(item["path"]),
                    item_count=int(item.get("item_count", item.get("paper_count", 0))),
                )
            )
        except Exception:
            continue
    return entries


def _load_cache(path: Path | None) -> dict[str, dict[str, Any]]:
    if path is None or not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        logger.warning("Network summary cache is invalid JSON: {}", path)
        return {}


def _save_cache(path: Path | None, cache: dict[str, dict[str, Any]]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cache, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
