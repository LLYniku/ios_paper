from .base import BaseRetriever, register_retriever
import arxiv
from arxiv import Result as ArxivResult
from ..protocol import Paper
from ..utils import extract_markdown_from_pdf, extract_tex_code_from_tar
from tempfile import TemporaryDirectory
import feedparser
from tqdm import tqdm
import multiprocessing
import os
import time
from email.utils import parsedate_to_datetime
from queue import Empty
from types import SimpleNamespace
from typing import Any, Callable, TypeVar
from loguru import logger
import requests

T = TypeVar("T")

DOWNLOAD_TIMEOUT = (10, 60)
PDF_EXTRACT_TIMEOUT = 180
TAR_EXTRACT_TIMEOUT = 180
ARXIV_ID_BATCH_SIZE = 10
ARXIV_INTER_BATCH_DELAY_SECONDS = 2
ARXIV_RETRYABLE_STATUS_CODES = {429, 503}
ARXIV_BATCH_BACKOFF_SECONDS = (15, 30, 60)


def _download_file(url: str, path: str) -> None:
    with requests.get(url, stream=True, timeout=DOWNLOAD_TIMEOUT) as response:
        response.raise_for_status()
        with open(path, "wb") as file:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    file.write(chunk)


def _run_in_subprocess(
    result_queue: Any,
    func: Callable[..., T | None],
    args: tuple[Any, ...],
) -> None:
    try:
        result_queue.put(("ok", func(*args)))
    except Exception as exc:
        result_queue.put(("error", f"{type(exc).__name__}: {exc}"))


def _run_with_hard_timeout(
    func: Callable[..., T | None],
    args: tuple[Any, ...],
    *,
    timeout: float,
    operation: str,
    paper_title: str,
) -> T | None:
    start_methods = multiprocessing.get_all_start_methods()
    context = multiprocessing.get_context("fork" if "fork" in start_methods else start_methods[0])
    result_queue = context.Queue()
    process = context.Process(target=_run_in_subprocess, args=(result_queue, func, args))
    process.start()

    try:
        status, payload = result_queue.get(timeout=timeout)
    except Empty:
        if process.is_alive():
            process.kill()
        process.join(5)
        result_queue.close()
        result_queue.join_thread()
        logger.warning(f"{operation} timed out for {paper_title} after {timeout} seconds")
        return None

    process.join(5)
    result_queue.close()
    result_queue.join_thread()

    if status == "ok":
        return payload

    logger.warning(f"{operation} failed for {paper_title}: {payload}")
    return None


def _entry_value(entry: Any, key: str, default: Any = None) -> Any:
    if hasattr(entry, "get"):
        return entry.get(key, default)
    return getattr(entry, key, default)


def _parse_feed_datetime(value: str | None) -> Any:
    if not value:
        return None
    try:
        return parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None


def _build_rss_fallback_result(entry: Any) -> Any:
    paper_id = _entry_value(entry, "id", "").removeprefix("oai:arXiv.org:")
    paper_url = _entry_value(entry, "link") or f"https://arxiv.org/abs/{paper_id}"
    author_entries = _entry_value(entry, "authors", []) or []
    authors = []
    for author in author_entries:
        if hasattr(author, "get"):
            name = author.get("name")
        else:
            name = getattr(author, "name", None)
        if name:
            authors.append(SimpleNamespace(name=name))
    if not authors:
        author_line = _entry_value(entry, "author")
        if author_line:
            authors = [SimpleNamespace(name=author_line)]

    tags = _entry_value(entry, "tags", []) or []
    categories = []
    for tag in tags:
        if hasattr(tag, "get"):
            term = tag.get("term")
        else:
            term = getattr(tag, "term", None)
        if term:
            categories.append(term)

    return SimpleNamespace(
        title=_entry_value(entry, "title", "Untitled"),
        authors=authors,
        summary=_entry_value(entry, "summary", "") or _entry_value(entry, "description", ""),
        pdf_url=f"https://arxiv.org/pdf/{paper_id}.pdf" if paper_id else None,
        entry_id=paper_url,
        published=_parse_feed_datetime(_entry_value(entry, "published")),
        updated=_parse_feed_datetime(_entry_value(entry, "updated")),
        categories=categories,
        doi=_entry_value(entry, "arxiv_doi"),
        source_url=lambda pid=paper_id: f"https://arxiv.org/e-print/{pid}" if pid else None,
    )


def _fetch_arxiv_batch(client: arxiv.Client, paper_ids: list[str], fallback_entries: list[Any]) -> list[Any]:
    max_attempts = len(ARXIV_BATCH_BACKOFF_SECONDS) + 1
    for attempt in range(1, max_attempts + 1):
        try:
            search = arxiv.Search(id_list=paper_ids)
            return list(client.results(search))
        except arxiv.HTTPError as exc:
            if exc.status not in ARXIV_RETRYABLE_STATUS_CODES:
                raise
            if attempt >= max_attempts:
                break
            backoff = ARXIV_BATCH_BACKOFF_SECONDS[attempt - 1]
            logger.warning(
                f"arXiv API returned HTTP {exc.status} for batch {paper_ids[0]}..{paper_ids[-1]}; "
                f"retrying in {backoff} seconds (attempt {attempt}/{max_attempts})"
            )
            time.sleep(backoff)

    logger.warning(
        f"arXiv API remained rate-limited for batch {paper_ids[0]}..{paper_ids[-1]}; "
        "falling back to RSS metadata."
    )
    return [_build_rss_fallback_result(entry) for entry in fallback_entries]


def _extract_text_from_pdf_worker(pdf_url: str) -> str:
    with TemporaryDirectory() as temp_dir:
        path = os.path.join(temp_dir, "paper.pdf")
        _download_file(pdf_url, path)
        return extract_markdown_from_pdf(path)


def _extract_text_from_html_worker(html_url: str) -> str | None:
    import trafilatura

    downloaded = trafilatura.fetch_url(html_url)
    if downloaded is None:
        raise ValueError(f"Failed to download HTML from {html_url}")
    text = trafilatura.extract(downloaded, include_comments=False, include_tables=False)
    if not text:
        raise ValueError(f"No text extracted from {html_url}")
    return text


def _extract_text_from_tar_worker(source_url: str, paper_id: str, paper_title: str | None = None) -> str | None:
    with TemporaryDirectory() as temp_dir:
        path = os.path.join(temp_dir, "paper.tar.gz")
        _download_file(source_url, path)
        file_contents = extract_tex_code_from_tar(path, paper_id, paper_title=paper_title)
        if not file_contents or "all" not in file_contents:
            raise ValueError("Main tex file not found.")
        return file_contents["all"]


@register_retriever("arxiv")
class ArxivRetriever(BaseRetriever):
    def __init__(self, config):
        super().__init__(config)
        if self.config.source.arxiv.category is None:
            raise ValueError("category must be specified for arxiv.")

    def _retrieve_raw_papers(self) -> list[ArxivResult]:
        client = arxiv.Client(num_retries=0, delay_seconds=ARXIV_INTER_BATCH_DELAY_SECONDS)
        query = '+'.join(self.config.source.arxiv.category)
        include_cross_list = self.config.source.arxiv.get("include_cross_list", False)
        # Get the latest paper from arxiv rss feed
        feed = feedparser.parse(f"https://rss.arxiv.org/atom/{query}")
        if 'Feed error for query' in feed.feed.title:
            raise Exception(f"Invalid ARXIV_QUERY: {query}.")
        raw_papers = []
        allowed_announce_types = {"new", "cross"} if include_cross_list else {"new"}
        selected_entries = [
            i for i in feed.entries
            if i.get("arxiv_announce_type", "new") in allowed_announce_types
        ]
        all_paper_ids = [i.id.removeprefix("oai:arXiv.org:") for i in selected_entries]
        entry_by_id = {i.id.removeprefix("oai:arXiv.org:"): i for i in selected_entries}
        if self.config.executor.debug:
            all_paper_ids = all_paper_ids[:10]

        # Get full information of each paper from arxiv api
        bar = tqdm(total=len(all_paper_ids))
        for i in range(0, len(all_paper_ids), ARXIV_ID_BATCH_SIZE):
            batch_ids = all_paper_ids[i:i + ARXIV_ID_BATCH_SIZE]
            fallback_entries = [entry_by_id[paper_id] for paper_id in batch_ids if paper_id in entry_by_id]
            batch = _fetch_arxiv_batch(client, batch_ids, fallback_entries)
            bar.update(len(batch_ids))
            raw_papers.extend(batch)
            if i + ARXIV_ID_BATCH_SIZE < len(all_paper_ids):
                time.sleep(ARXIV_INTER_BATCH_DELAY_SECONDS)
        bar.close()

        return raw_papers

    def convert_to_paper(self, raw_paper: ArxivResult) -> Paper:
        title = raw_paper.title
        authors = [a.name for a in raw_paper.authors]
        abstract = raw_paper.summary
        pdf_url = raw_paper.pdf_url
        full_text = extract_text_from_tar(raw_paper)
        if full_text is None:
            full_text = extract_text_from_html(raw_paper)
        if full_text is None:
            full_text = extract_text_from_pdf(raw_paper)
        return Paper(
            source=self.name,
            title=title,
            authors=authors,
            abstract=abstract,
            url=raw_paper.entry_id,
            pdf_url=pdf_url,
            full_text=full_text,
            published_at=getattr(raw_paper, "published", None),
            updated_at=getattr(raw_paper, "updated", None),
            categories=list(getattr(raw_paper, "categories", []) or []),
            doi=getattr(raw_paper, "doi", None),
        )


def extract_text_from_html(paper: ArxivResult) -> str | None:
    html_url = paper.entry_id.replace("/abs/", "/html/")
    try:
        return _extract_text_from_html_worker(html_url)
    except Exception as exc:
        logger.warning(f"HTML extraction failed for {paper.title}: {exc}")
        return None


def extract_text_from_pdf(paper: ArxivResult) -> str | None:
    if paper.pdf_url is None:
        logger.warning(f"No PDF URL available for {paper.title}")
        return None
    return _run_with_hard_timeout(
        _extract_text_from_pdf_worker,
        (paper.pdf_url,),
        timeout=PDF_EXTRACT_TIMEOUT,
        operation="PDF extraction",
        paper_title=paper.title,
    )


def extract_text_from_tar(paper: ArxivResult) -> str | None:
    source_url = paper.source_url()
    if source_url is None:
        logger.warning(f"No source URL available for {paper.title}")
        return None
    return _run_with_hard_timeout(
        _extract_text_from_tar_worker,
        (source_url, paper.entry_id, paper.title),
        timeout=TAR_EXTRACT_TIMEOUT,
        operation="Tar extraction",
        paper_title=paper.title,
    )
