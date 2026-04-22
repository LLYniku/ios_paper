from __future__ import annotations

import json
from pathlib import Path

from zotero_arxiv_daily.app_export.network_exporter import NetworkCandidate, NetworkFeedExporter, rerank_network_candidates
from zotero_arxiv_daily.protocol import CorpusPaper


class StubReranker:
    def get_similarity_score(self, s1, s2):
        import numpy as np

        return np.array(
            [
                [0.9, 0.2],
                [0.1, 0.8],
            ]
        )


def test_rerank_network_candidates_scores_and_orders() -> None:
    candidates = [
        NetworkCandidate(
            id="github:a",
            platform="github",
            content_type="repository",
            title="A",
            creator="alice",
            source_label="alice/a",
            url="https://example.com/a",
            raw_excerpt="cache compression",
            tags=["cache"],
        ),
        NetworkCandidate(
            id="openreview:b",
            platform="openreview",
            content_type="paper",
            title="B",
            creator="bob",
            source_label="ICLR",
            url="https://example.com/b",
            raw_excerpt="quantization",
            tags=["quantization"],
        ),
    ]
    corpus = [
        CorpusPaper(title="newer", abstract="cache", added_date=_dt("2026-04-22T00:00:00"), paths=[]),
        CorpusPaper(title="older", abstract="quantization", added_date=_dt("2026-04-20T00:00:00"), paths=[]),
    ]

    ranked = rerank_network_candidates(candidates, corpus, StubReranker())

    assert [item.id for item in ranked] == ["github:a", "openreview:b"]
    assert ranked[0].score is not None
    assert ranked[0].score > ranked[1].score


def test_network_feed_exporter_writes_latest_archive_and_manifest(tmp_path: Path) -> None:
    config = {
        "network": {
            "max_item_num": 2,
            "summary_top_n": 1,
            "source": ["github", "openreview"],
        },
        "llm": {
            "generation_kwargs": {"model": "gpt-5.4-mini"},
        },
    }
    candidates = [
        NetworkCandidate(
            id="github:a",
            platform="github",
            content_type="repository",
            title="A",
            creator="alice",
            source_label="alice/a",
            url="https://example.com/a",
            raw_excerpt="cache compression repository",
            tags=["cache"],
            score=0.9,
        ),
        NetworkCandidate(
            id="openreview:b",
            platform="openreview",
            content_type="paper",
            title="B",
            creator="bob",
            source_label="ICLR",
            url="https://example.com/b",
            raw_excerpt="quantization paper",
            tags=["quantization"],
            score=0.8,
        ),
    ]
    exporter = NetworkFeedExporter(
        config,
        output_dir=tmp_path / "network",
        timezone_name="Asia/Shanghai",
        language="zh-Hans",
        summary_generator=lambda candidate: {
            "summary_zh": f"{candidate.title} 中文总结",
            "tldr": f"{candidate.title} TLDR",
            "recommendation_reason": f"{candidate.title} 推荐理由",
        },
    )

    feed = exporter.export(candidates)

    latest = json.loads((tmp_path / "network" / "latest.json").read_text(encoding="utf-8"))
    archive = json.loads(
        (tmp_path / "network" / "archive" / f"{feed.recommendation_date}.json").read_text(encoding="utf-8")
    )
    manifest = json.loads((tmp_path / "network" / "manifest.json").read_text(encoding="utf-8"))

    assert latest["stats"]["recommended_count"] == 2
    assert archive["items"][0]["summary_zh"] == "A 中文总结"
    assert manifest["latest"] == "latest.json"
    assert manifest["archive"][0]["item_count"] == 2


def _dt(raw: str):
    from datetime import datetime

    return datetime.fromisoformat(raw)
