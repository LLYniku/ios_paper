from __future__ import annotations

from collections.abc import Mapping
from typing import Any


def _as_mapping(config: Any) -> Mapping[str, Any]:
    if isinstance(config, Mapping):
        return config
    return {}


def get_wire_api(llm_params: Any) -> str:
    api_config = _as_mapping(_as_mapping(llm_params).get("api"))
    wire_api = str(api_config.get("wire_api", "chat_completions") or "chat_completions")
    return wire_api.lower()


def _generation_kwargs(llm_params: Any, *, for_responses: bool) -> dict[str, Any]:
    params = dict(_as_mapping(_as_mapping(llm_params).get("generation_kwargs")))
    if for_responses and "max_tokens" in params and "max_output_tokens" not in params:
        params["max_output_tokens"] = params.pop("max_tokens")
    return params


def generate_text(
    openai_client: Any,
    llm_params: Any,
    *,
    system_prompt: str,
    user_prompt: str,
) -> str:
    wire_api = get_wire_api(llm_params)
    if wire_api == "responses":
        params = _generation_kwargs(llm_params, for_responses=True)
        api_config = _as_mapping(_as_mapping(llm_params).get("api"))
        if api_config.get("disable_response_storage", False):
            params.setdefault("store", False)
        response = openai_client.responses.create(
            instructions=system_prompt,
            input=user_prompt,
            **params,
        )
        return str(getattr(response, "output_text", "") or "")

    params = _generation_kwargs(llm_params, for_responses=False)
    response = openai_client.chat.completions.create(
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        **params,
    )
    return str(response.choices[0].message.content or "")
