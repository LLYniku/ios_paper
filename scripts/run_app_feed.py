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

from zotero_arxiv_daily.app_export import JSONFeedExporter
from zotero_arxiv_daily.executor import Executor

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
    parser = argparse.ArgumentParser(description="Generate app-facing paper recommendation JSON feed.")
    parser.add_argument(
        "--config",
        default=os.getenv("CUSTOM_CONFIG"),
        help="Optional YAML config path or inline YAML/override object.",
    )
    parser.add_argument(
        "--output-dir",
        default="public/data",
        help="Directory where latest.json, archive, and manifest will be written.",
    )
    parser.add_argument(
        "--timezone",
        default="Asia/Taipei",
        help="IANA timezone name used for recommendation_date.",
    )
    parser.add_argument(
        "--language",
        default="zh-Hans",
        help="Language code for app summaries.",
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
        try:
            return OmegaConf.create(config_arg)
        except Exception as exc:
            raise ValueError(f"Unable to parse --config value as inline config: {config_arg}") from exc

    config_path = Path(config_arg)
    try:
        if config_path.exists():
            return OmegaConf.load(config_path)
    except OSError:
        pass
    try:
        return OmegaConf.create(config_arg)
    except Exception as exc:
        raise ValueError(f"Unable to parse --config value as a file path or inline config: {config_arg}") from exc


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


def main() -> int:
    dotenv.load_dotenv()
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    args = parse_args()
    config = build_config(args)
    configure_logging(bool(config.executor.debug))

    executor = Executor(config)
    result = executor.collect_recommendations(enrich_with_llm=True, include_affiliations=True)

    exporter = JSONFeedExporter(
        config,
        output_dir=ROOT / args.output_dir,
        timezone_name=args.timezone,
        language=args.language,
        openai_client=executor.openai_client,
    )
    feed = exporter.export(result.papers, total_candidates=result.total_candidates)
    logger.info(
        "Generated app feed: date={}, papers={}, candidates={}, llm_summaries={}",
        feed.recommendation_date,
        feed.stats.recommended_count,
        feed.stats.total_candidates,
        feed.stats.llm_summary_count,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
