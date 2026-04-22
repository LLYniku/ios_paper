from pathlib import Path

import pytest

from scripts.run_app_feed import load_optional_config, looks_like_inline_config


def test_detects_inline_yaml_with_newlines():
    inline_config = "zotero:\n  user_id: 123\n  api_key: abc\n"
    assert looks_like_inline_config(inline_config) is True


def test_load_optional_config_supports_inline_yaml_with_crlf():
    inline_config = (
        "zotero:\r\n"
        "  user_id: 123\r\n"
        "  api_key: abc\r\n"
        "executor:\r\n"
        "  source: [\"arxiv\"]\r\n"
    )
    config = load_optional_config(inline_config)
    assert config.zotero.user_id == 123
    assert config.executor.source == ["arxiv"]


def test_load_optional_config_supports_path(tmp_path: Path):
    config_path = tmp_path / "custom.yaml"
    config_path.write_text("executor:\n  debug: true\n", encoding="utf-8")
    config = load_optional_config(str(config_path))
    assert config.executor.debug is True


def test_load_optional_config_raises_for_invalid_input():
    with pytest.raises(ValueError):
        load_optional_config("not: [valid")
