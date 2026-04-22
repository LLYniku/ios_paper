from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path
import sys

import dotenv
from hydra import compose, initialize_config_dir
from hydra.core.global_hydra import GlobalHydra
from loguru import logger
from omegaconf import DictConfig, OmegaConf, open_dict

from zotero_arxiv_daily.app_export.network_exporter import (
    NetworkFeedExporter,
    collect_network_candidates,
    rerank_network_candidates,
)
from zotero_arxiv_daily.executor import Executor, normalize_path_patterns


ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = ROOT / "config"


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
    parser = argparse.ArgumentParser(description="Generate app-facing network recommendation JSON feed.")
    parser.add_argument(
        "--config",
        default=os.getenv("CUSTOM_CONFIG"),
        help="Optional YAML config path or inline YAML/override object.",
    )
    parser.add_argument(
        "--output-dir",
        default="public/data/network",
        help="Directory where latest.json, archive, and manifest will be written.",
    )
    parser.add_argument(
        "--bundle-output",
        default="ios/PaperDaily/PaperDaily/Resources/sample_network.json",
        help="Optional iOS bundled sample output path.",
    )
    parser.add_argument(
        "--cache-path",
        default="public/data/cache/network_summaries.json",
        help="Cache path for generated network summaries.",
    )
    parser.add_argument(
        "--timezone",
        default="Asia/Shanghai",
        help="IANA timezone name used for recommendation_date.",
    )
    parser.add_argument(
        "--language",
        default="zh-Hans",
        help="Language code for network summaries.",
    )
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
        config.executor.source = []
        config.network.output_dir = args.output_dir
        config.network.language = args.language
        config.llm.language = "简体中文" if args.language == "zh-Hans" else args.language
    return config


def main() -> int:
    dotenv.load_dotenv()
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    args = parse_args()
    config = build_config(args)
    configure_logging(bool(config.executor.debug))

    executor = Executor(config)
    corpus = executor.fetch_zotero_corpus()
    include_patterns = normalize_path_patterns(config.zotero.include_path, "include_path")
    ignore_patterns = normalize_path_patterns(config.zotero.ignore_path, "ignore_path")
    executor.include_path_patterns = include_patterns
    executor.ignore_path_patterns = ignore_patterns
    corpus = executor.filter_corpus(corpus)

    candidates = collect_network_candidates(config)
    reranked = rerank_network_candidates(candidates, corpus, executor.reranker)

    exporter = NetworkFeedExporter(
        config,
        output_dir=ROOT / args.output_dir,
        timezone_name=args.timezone,
        language=args.language,
        openai_client=executor.openai_client,
        cache_path=ROOT / args.cache_path if args.cache_path else None,
    )
    feed = exporter.export(reranked)

    if args.bundle_output:
        Path(args.bundle_output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.bundle_output).write_text(
            (ROOT / args.output_dir / "latest.json").read_text(encoding="utf-8"),
            encoding="utf-8",
        )

    logger.info(
        "Generated network feed: date={}, items={}, candidates={}, llm_summaries={}",
        feed.recommendation_date,
        feed.stats.recommended_count,
        feed.stats.total_candidates,
        feed.stats.llm_summary_count,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
