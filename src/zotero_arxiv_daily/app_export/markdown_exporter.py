from .models import AppFeed


def render_markdown_digest(feed: AppFeed) -> str:
    lines = [
        f"# 每日论文推荐 - {feed.recommendation_date}",
        "",
        f"- 更新时间: {feed.generated_at}",
        f"- 推荐数量: {feed.stats.recommended_count}",
        "",
    ]
    for index, paper in enumerate(feed.papers, start=1):
        lines.extend(
            [
                f"## {index}. {paper.title}",
                f"- TL;DR: {paper.tldr or '暂无'}",
                f"- 推荐理由: {paper.recommendation_reason or '暂无'}",
                f"- PDF: {paper.pdf_url or '暂无'}",
                "",
            ]
        )
    return "\n".join(lines)
