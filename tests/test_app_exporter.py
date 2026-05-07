from __future__ import annotations

from datetime import UTC, datetime
import json
from pathlib import Path
import shutil
import subprocess
import textwrap

from omegaconf import open_dict

from tests.canned_responses import make_sample_paper
from zotero_arxiv_daily.app_export import JSONFeedExporter, build_stable_paper_id


def _make_exporter(config, output_dir: Path) -> JSONFeedExporter:
    with open_dict(config):
        config.executor.source = ["arxiv"]
        config.app_export.summary_top_n = 0
    return JSONFeedExporter(
        config,
        output_dir=output_dir,
        timezone_name="Asia/Taipei",
        language="zh-Hans",
        openai_client=None,
    )


def test_exporter_writes_latest_archive_and_manifest(config, tmp_path):
    exporter = _make_exporter(config, tmp_path)
    generated_at = datetime(2026, 4, 22, 22, 0, tzinfo=UTC)
    papers = [
        make_sample_paper(
            url="https://arxiv.org/abs/2501.00001v2",
            pdf_url="https://arxiv.org/pdf/2501.00001.pdf",
            score=0.9234,
            affiliations=["University X"],
        )
    ]

    feed = exporter.export(papers, total_candidates=120, generated_at=generated_at)

    latest = json.loads((tmp_path / "latest.json").read_text(encoding="utf-8"))
    archive = json.loads((tmp_path / "archive" / "2026-04-23.json").read_text(encoding="utf-8"))
    manifest = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))

    assert feed.recommendation_date == "2026-04-23"
    assert latest["schema_version"] == "1.0"
    assert latest["stats"]["total_candidates"] == 120
    assert latest["papers"][0]["id"] == "arxiv:2501.00001"
    assert latest["papers"][0]["relevance_score"] == 0.9234
    assert archive["recommendation_date"] == "2026-04-23"
    assert manifest["latest"] == "latest.json"
    assert manifest["archive"][0]["path"] == "archive/2026-04-23.json"


def test_exporter_handles_optional_fields(config, tmp_path):
    exporter = _make_exporter(config, tmp_path)
    papers = [
        make_sample_paper(
            pdf_url=None,
            affiliations=None,
            categories=[],
            doi=None,
            code_url=None,
            project_url=None,
        )
    ]

    exporter.export(papers, total_candidates=1, generated_at=datetime(2026, 4, 22, tzinfo=UTC))

    latest = json.loads((tmp_path / "latest.json").read_text(encoding="utf-8"))
    item = latest["papers"][0]
    assert item["pdf_url"] is None
    assert item["doi"] is None
    assert item["affiliations"] == []
    assert item["categories"] == []


def test_exporter_handles_empty_papers(config, tmp_path):
    exporter = _make_exporter(config, tmp_path)

    exporter.export([], total_candidates=0, generated_at=datetime(2026, 4, 22, tzinfo=UTC))

    latest = json.loads((tmp_path / "latest.json").read_text(encoding="utf-8"))
    assert latest["papers"] == []
    assert latest["stats"]["recommended_count"] == 0
    assert latest["stats"]["llm_summary_count"] == 0


def test_fallback_summary_uses_chinese_tldr(config, tmp_path):
    exporter = _make_exporter(config, tmp_path)
    paper = make_sample_paper()
    paper.summary_zh = None
    paper.tldr = "这是一句中文 TL;DR，用于在 JSON 总结失败时保底展示。"

    exporter.export([paper], total_candidates=1, generated_at=datetime(2026, 4, 22, tzinfo=UTC))

    latest = json.loads((tmp_path / "latest.json").read_text(encoding="utf-8"))
    assert latest["papers"][0]["summary_zh"] == paper.tldr


def test_manifest_updates_with_new_archive_entries(config, tmp_path):
    exporter = _make_exporter(config, tmp_path)
    paper = make_sample_paper(url="https://arxiv.org/abs/2501.00001")

    exporter.export([paper], total_candidates=10, generated_at=datetime(2026, 4, 22, 22, tzinfo=UTC))
    exporter.export([paper], total_candidates=8, generated_at=datetime(2026, 4, 23, 22, tzinfo=UTC))

    manifest = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))
    archive_dates = [entry["date"] for entry in manifest["archive"]]
    assert archive_dates == ["2026-04-24", "2026-04-23"]


def test_paper_id_is_stable_for_same_source_item():
    first = make_sample_paper(url="https://arxiv.org/abs/2501.00001v3")
    second = make_sample_paper(url="https://arxiv.org/abs/2501.00001", title="Updated title")

    assert build_stable_paper_id(first) == build_stable_paper_id(second) == "arxiv:2501.00001"


def test_generated_json_can_be_decoded_by_swift_model(config, tmp_path):
    if shutil.which("swift") is None:
        return

    exporter = _make_exporter(config, tmp_path)
    exporter.export(
        [make_sample_paper(url="https://arxiv.org/abs/2501.00001")],
        total_candidates=1,
        generated_at=datetime(2026, 4, 22, 22, tzinfo=UTC),
    )

    swift_script = textwrap.dedent(
        """
        import Foundation

        struct FeedConfig: Codable {
            let categories: [String]
            let maxPaperNum: Int?
            let model: String?
            enum CodingKeys: String, CodingKey {
                case categories
                case maxPaperNum = "max_paper_num"
                case model
            }
        }

        struct FeedStats: Codable {
            let totalCandidates: Int
            let recommendedCount: Int
            let llmSummaryCount: Int
            enum CodingKeys: String, CodingKey {
                case totalCandidates = "total_candidates"
                case recommendedCount = "recommended_count"
                case llmSummaryCount = "llm_summary_count"
            }
        }

        struct PaperItem: Codable {
            let id: String
            let title: String
            let pdfURL: URL?
            enum CodingKeys: String, CodingKey {
                case id
                case title
                case pdfURL = "pdf_url"
            }
        }

        struct PaperFeed: Codable {
            let schemaVersion: String
            let generatedAt: Date
            let recommendationDate: String
            let timezone: String
            let source: [String]
            let language: String
            let config: FeedConfig
            let stats: FeedStats
            let papers: [PaperItem]
            enum CodingKeys: String, CodingKey {
                case schemaVersion = "schema_version"
                case generatedAt = "generated_at"
                case recommendationDate = "recommendation_date"
                case timezone
                case source
                case language
                case config
                case stats
                case papers
            }
        }

        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(PaperFeed.self, from: data)
        """
    )

    result = subprocess.run(
        ["swift", "-e", swift_script, str(tmp_path / "latest.json")],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
