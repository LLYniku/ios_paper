from dataclasses import dataclass, field


@dataclass
class AppFeedConfig:
    categories: list[str] = field(default_factory=list)
    max_paper_num: int | None = None
    model: str | None = None


@dataclass
class AppFeedStats:
    total_candidates: int
    recommended_count: int
    llm_summary_count: int


@dataclass
class AppPaper:
    id: str
    source: str
    title: str
    authors: list[str]
    abstract: str | None
    summary_zh: str | None
    tldr: str | None
    recommendation_reason: str | None
    relevance_score: float | None
    published_at: str | None
    updated_at: str | None
    categories: list[str] = field(default_factory=list)
    keywords: list[str] = field(default_factory=list)
    affiliations: list[str] = field(default_factory=list)
    pdf_url: str | None = None
    abs_url: str | None = None
    code_url: str | None = None
    project_url: str | None = None
    doi: str | None = None


@dataclass
class AppFeed:
    schema_version: str
    generated_at: str
    recommendation_date: str
    timezone: str
    source: list[str]
    language: str
    config: AppFeedConfig
    stats: AppFeedStats
    papers: list[AppPaper] = field(default_factory=list)


@dataclass
class AppManifestEntry:
    date: str
    path: str
    paper_count: int


@dataclass
class AppFeedManifest:
    schema_version: str
    latest: str
    latest_date: str
    archive: list[AppManifestEntry] = field(default_factory=list)
