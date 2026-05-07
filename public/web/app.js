const DATA_URLS = {
  today: "../data/latest.json",
  classic: "../data/classics.json",
  network: "../data/network/latest.json",
};

const STORAGE_KEY = "paperdaily.web.v1";
const state = {
  tab: "today",
  query: "",
  filter: "all",
  feeds: { today: null, classic: null, network: null },
  loading: false,
  message: "",
  library: loadLibrary(),
};

const els = {
  title: document.querySelector("#page-title"),
  refresh: document.querySelector("#refresh-button"),
  summary: document.querySelector("#summary-card"),
  search: document.querySelector("#search-input"),
  filters: document.querySelector("#filter-row"),
  status: document.querySelector("#status-line"),
  list: document.querySelector("#content-list"),
  dialog: document.querySelector("#detail-dialog"),
  detail: document.querySelector("#detail-content"),
};

function loadLibrary() {
  const fallback = { favorites: {}, read: {}, ratings: {} };
  try {
    return { ...fallback, ...JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}") };
  } catch {
    return fallback;
  }
}

function saveLibrary() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state.library));
}

function cacheKey(kind) {
  return `paperdaily.feed.${kind}`;
}

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatDate(value) {
  if (!value) return "未知";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value).slice(0, 10);
  return date.toLocaleString("zh-CN", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function shortDate(value) {
  if (!value) return "未知日期";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value).slice(0, 10);
  return date.toLocaleDateString("zh-CN", { year: "numeric", month: "2-digit", day: "2-digit" });
}

function scoreText(item) {
  const value = item.relevance_score;
  if (typeof value !== "number") return "";
  return value > 5 ? value.toFixed(1) : value.toFixed(2);
}

function normalizeToday(item) {
  return {
    kind: "today",
    id: item.id,
    title: item.title,
    summary: item.summary_zh || item.tldr || item.abstract || "暂无摘要",
    tldr: item.tldr,
    reason: item.recommendation_reason,
    abstract: item.abstract,
    authors: item.authors || [],
    tags: item.categories?.length ? item.categories : item.keywords || [],
    date: item.published_at || item.updated_at,
    sourceDate: state.feeds.today?.recommendation_date,
    score: scoreText(item),
    primaryURL: item.abs_url || item.pdf_url,
    pdfURL: item.pdf_url,
    codeURL: item.code_url,
    raw: item,
  };
}

function normalizeClassic(item) {
  return {
    kind: "classic",
    id: item.id,
    title: item.title,
    summary: item.summary_zh || item.simple_intro || item.abstract || "暂无摘要",
    tldr: item.tldr || item.simple_intro,
    reason: item.simple_intro,
    abstract: item.abstract,
    authors: [],
    tags: [item.category, item.venue, item.year].filter(Boolean),
    date: item.year ? `${item.year}` : "",
    sourceDate: item.year ? `${item.year}` : "经典论文",
    score: item.year || "",
    primaryURL: item.paper_url,
    pdfURL: item.paper_url?.includes("arxiv.org/abs/") ? item.paper_url.replace("/abs/", "/pdf/") : item.paper_url,
    codeURL: item.code_url || item.project_url,
    raw: item,
  };
}

function normalizeNetwork(item) {
  return {
    kind: "network",
    id: item.id,
    title: item.title,
    summary: item.summary_zh || item.tldr || item.raw_excerpt || "暂无摘要",
    tldr: item.tldr,
    reason: item.recommendation_reason,
    abstract: item.raw_excerpt,
    authors: [item.creator].filter(Boolean),
    tags: [item.platform, ...(item.tags || [])].filter(Boolean),
    date: item.published_at,
    sourceDate: shortDate(item.published_at),
    score: scoreText(item),
    primaryURL: item.url,
    pdfURL: null,
    codeURL: item.url,
    raw: item,
  };
}

function itemsFor(kind) {
  if (kind === "today") return (state.feeds.today?.papers || []).map(normalizeToday);
  if (kind === "classic") return (state.feeds.classic?.papers || []).map(normalizeClassic);
  if (kind === "network") return (state.feeds.network?.items || []).map(normalizeNetwork);
  return [];
}

function currentItems() {
  if (state.tab === "favorites") {
    return Object.values(state.library.favorites)
      .map((entry) => entry.item)
      .sort((a, b) => {
        const ar = state.library.ratings[a.id] || 0;
        const br = state.library.ratings[b.id] || 0;
        if (ar !== br) return br - ar;
        return String(b.savedAt || "").localeCompare(String(a.savedAt || ""));
      });
  }

  let items = itemsFor(state.tab);
  if (state.filter === "unread") items = items.filter((item) => !state.library.read[item.id]);
  if (state.filter === "favorite") items = items.filter((item) => state.library.favorites[item.id]);
  if (state.filter !== "all" && state.filter !== "unread" && state.filter !== "favorite") {
    items = items.filter((item) => item.tags.includes(state.filter));
  }
  return filterByQuery(items);
}

function filterByQuery(items) {
  const query = state.query.trim().toLowerCase();
  if (!query) return items;
  return items.filter((item) => {
    const haystack = [
      item.title,
      item.summary,
      item.tldr,
      item.reason,
      item.abstract,
      item.authors.join(" "),
      item.tags.join(" "),
    ].join(" ").toLowerCase();
    return haystack.includes(query);
  });
}

async function fetchFeed(kind, { force = false } = {}) {
  const cached = localStorage.getItem(cacheKey(kind));
  if (cached && !force) {
    try {
      state.feeds[kind] = JSON.parse(cached);
    } catch {
      localStorage.removeItem(cacheKey(kind));
    }
  }

  const bust = force ? `?t=${Date.now()}` : "";
  const response = await fetch(`${DATA_URLS[kind]}${bust}`, { cache: "no-store" });
  if (!response.ok) throw new Error(`${kind} 数据源返回 ${response.status}`);
  const payload = await response.json();
  state.feeds[kind] = payload;
  localStorage.setItem(cacheKey(kind), JSON.stringify(payload));
}

async function refreshAll({ force = false } = {}) {
  state.loading = true;
  state.message = force ? "正在刷新远端数据..." : "正在载入数据...";
  render();
  try {
    await Promise.allSettled(["today", "classic", "network"].map((kind) => fetchFeed(kind, { force })));
    state.message = force ? "刷新完成。" : "";
  } catch (error) {
    state.message = `刷新失败：${error.message}`;
  } finally {
    state.loading = false;
    render();
  }
}

function isFavorite(id) {
  return Boolean(state.library.favorites[id]);
}

function toggleFavorite(item) {
  if (isFavorite(item.id)) {
    delete state.library.favorites[item.id];
  } else {
    state.library.favorites[item.id] = { item: { ...item, savedAt: new Date().toISOString() } };
  }
  saveLibrary();
  render();
}

function toggleRead(id) {
  if (state.library.read[id]) delete state.library.read[id];
  else state.library.read[id] = new Date().toISOString();
  saveLibrary();
  render();
}

function setRating(id, rating) {
  state.library.ratings[id] = rating;
  saveLibrary();
  render();
}

function openURL(url) {
  if (!url) return;
  window.open(url, "_blank", "noopener,noreferrer");
}

function renderSummary() {
  if (state.tab === "settings") {
    els.summary.innerHTML = `
      <h2>Web App 模式</h2>
      <div class="meta-grid">
        <span>无需 iOS 签名</span><span>可添加到主屏幕</span>
        <span>数据源</span><span>GitHub Pages JSON</span>
      </div>`;
    return;
  }

  if (state.tab === "favorites") {
    const favs = Object.values(state.library.favorites).map((x) => x.item);
    const today = favs.filter((x) => x.kind === "today").length;
    const classic = favs.filter((x) => x.kind === "classic").length;
    const network = favs.filter((x) => x.kind === "network").length;
    els.summary.innerHTML = `
      <h2>长期收藏</h2>
      <div class="meta-grid">
        <span>今日 ${today}</span><span>经典 ${classic}</span>
        <span>网络 ${network}</span><span>总计 ${favs.length}</span>
      </div>`;
    return;
  }

  const feed = state.feeds[state.tab];
  const map = {
    today: ["今日推荐", feed?.recommendation_date, feed?.generated_at, feed?.stats?.recommended_count || feed?.papers?.length || 0],
    classic: ["经典论文", feed?.source_title, feed?.generated_at, feed?.paper_count || feed?.papers?.length || 0],
    network: ["网络内容", feed?.recommendation_date, feed?.generated_at, feed?.stats?.recommended_count || feed?.items?.length || 0],
  };
  const [title, subtitle, generated, count] = map[state.tab];
  const readCount = itemsFor(state.tab).filter((item) => state.library.read[item.id]).length;
  els.summary.innerHTML = `
    <h2>${escapeHTML(title)}</h2>
    <div class="meta-grid">
      <span>${escapeHTML(subtitle || "未载入")}</span><span>数量 ${count}</span>
      <span>已读 ${readCount}</span><span>更新 ${escapeHTML(formatDate(generated))}</span>
    </div>`;
}

function filterOptions() {
  if (state.tab === "settings") return [];
  if (state.tab === "favorites") return ["all", "today", "classic", "network"];
  const tags = [...new Set(itemsFor(state.tab).flatMap((item) => item.tags).filter(Boolean))].slice(0, 18);
  return ["all", "unread", "favorite", ...tags];
}

function filterTitle(value) {
  return { all: "全部", unread: "未读", favorite: "收藏", today: "今日", classic: "经典", network: "网络" }[value] || value;
}

function renderFilters() {
  const options = filterOptions();
  els.filters.innerHTML = options.map((option) => (
    `<button class="chip ${state.filter === option ? "active" : ""}" data-filter="${escapeHTML(option)}">${escapeHTML(filterTitle(option))}</button>`
  )).join("");
}

function cardHTML(item) {
  const fav = isFavorite(item.id);
  const read = Boolean(state.library.read[item.id]);
  const rating = state.library.ratings[item.id] || 0;
  return `
    <article class="paper-card" data-open="${escapeHTML(item.id)}">
      <div class="card-head">
        <h2 class="paper-title">${escapeHTML(item.title)}</h2>
        ${item.score ? `<span class="score">${escapeHTML(item.score)}</span>` : ""}
      </div>
      <p class="summary">${escapeHTML(item.summary)}</p>
      <p class="byline">${escapeHTML([item.authors.slice(0, 3).join(", "), item.sourceDate].filter(Boolean).join(" · "))}</p>
      <div class="tag-row">${item.tags.slice(0, 5).map((tag) => `<span class="tag">${escapeHTML(tag)}</span>`).join("")}</div>
      ${fav ? starsHTML(item.id, rating) : ""}
      <div class="action-row">
        <button class="action ${fav ? "on" : ""}" data-favorite="${escapeHTML(item.id)}">${fav ? "已收藏" : "收藏"}</button>
        <button class="action ${read ? "on" : ""}" data-read="${escapeHTML(item.id)}">${read ? "已读" : "标已读"}</button>
        ${item.primaryURL ? `<button class="action" data-link="${escapeHTML(item.primaryURL)}">链接</button>` : ""}
        <button class="action primary" data-open="${escapeHTML(item.id)}">详情</button>
      </div>
    </article>`;
}

function starsHTML(id, rating) {
  return `<div class="stars" aria-label="星级评分">
    ${[1, 2, 3, 4, 5].map((n) => `<button class="star" data-rate="${id}:${n}">${n <= rating ? "★" : "☆"}</button>`).join("")}
  </div>`;
}

function renderList() {
  if (state.tab === "settings") {
    els.list.innerHTML = settingsHTML();
    return;
  }
  let items = currentItems();
  if (state.tab === "favorites" && state.filter !== "all") {
    items = items.filter((item) => item.kind === state.filter);
  }
  if (!items.length) {
    els.list.innerHTML = `<article class="empty-card"><h2>暂无内容</h2><p>可以刷新数据，或者调整搜索和筛选条件。</p></article>`;
    return;
  }
  els.list.innerHTML = items.map(cardHTML).join("");
}

function settingsHTML() {
  return `
    <article class="settings-card">
      <h2>如何长期使用</h2>
      <p>在 iPhone Safari 打开当前页面，点击分享按钮，然后选择“添加到主屏幕”。之后它会像普通 App 一样从桌面打开，不受 iOS 开发签名 7 天限制影响。</p>
      <div class="setting-row"><b>今日数据</b><span class="small">${DATA_URLS.today}</span></div>
      <div class="setting-row"><b>经典数据</b><span class="small">${DATA_URLS.classic}</span></div>
      <div class="setting-row"><b>网络数据</b><span class="small">${DATA_URLS.network}</span></div>
      <div class="setting-row"><b>本地收藏</b><span class="small">${Object.keys(state.library.favorites).length} 条</span></div>
      <button class="action primary" data-refresh-all="1">立即刷新</button>
      <button class="action" data-export="1">导出收藏</button>
    </article>`;
}

function showDetail(item) {
  const fav = isFavorite(item.id);
  els.detail.innerHTML = `
    <h2>${escapeHTML(item.title)}</h2>
    <p class="byline">${escapeHTML([item.authors.join(", "), item.sourceDate].filter(Boolean).join(" · "))}</p>
    <div class="tag-row">${item.tags.slice(0, 12).map((tag) => `<span class="tag">${escapeHTML(tag)}</span>`).join("")}</div>
    <div class="detail-section"><h3>一句话</h3><p>${escapeHTML(item.tldr || item.summary)}</p></div>
    <div class="detail-section"><h3>中文总结</h3><p>${escapeHTML(item.summary)}</p></div>
    ${item.reason ? `<div class="detail-section"><h3>推荐理由</h3><p>${escapeHTML(item.reason)}</p></div>` : ""}
    ${item.abstract ? `<div class="detail-section"><h3>原始摘要/摘录</h3><p>${escapeHTML(item.abstract)}</p></div>` : ""}
    <div class="action-row">
      <button class="action ${fav ? "on" : ""}" data-favorite="${escapeHTML(item.id)}">${fav ? "已收藏" : "收藏"}</button>
      ${item.primaryURL ? `<button class="action primary" data-link="${escapeHTML(item.primaryURL)}">打开链接</button>` : ""}
      ${item.pdfURL ? `<button class="action" data-link="${escapeHTML(item.pdfURL)}">PDF</button>` : ""}
      ${item.codeURL ? `<button class="action" data-link="${escapeHTML(item.codeURL)}">代码/项目</button>` : ""}
    </div>`;
  if (typeof els.dialog.showModal === "function") els.dialog.showModal();
}

function render() {
  const titles = { today: "今日", classic: "经典", network: "网络", favorites: "收藏", settings: "设置" };
  els.title.textContent = titles[state.tab];
  document.querySelectorAll(".tab").forEach((tab) => tab.classList.toggle("active", tab.dataset.tab === state.tab));
  els.status.hidden = !state.message;
  els.status.textContent = state.message;
  renderSummary();
  renderFilters();
  renderList();
}

function itemByID(id) {
  return [...itemsFor("today"), ...itemsFor("classic"), ...itemsFor("network"), ...Object.values(state.library.favorites).map((x) => x.item)]
    .find((item) => item.id === id);
}

document.addEventListener("click", (event) => {
  const target = event.target.closest("button, article[data-open]");
  if (!target) return;
  if (target.dataset.tab) {
    state.tab = target.dataset.tab;
    state.filter = "all";
    state.query = "";
    els.search.value = "";
    render();
    return;
  }
  if (target.dataset.filter) {
    state.filter = target.dataset.filter;
    render();
    return;
  }
  if (target.dataset.favorite) {
    event.stopPropagation();
    const item = itemByID(target.dataset.favorite);
    if (item) toggleFavorite(item);
    return;
  }
  if (target.dataset.read) {
    event.stopPropagation();
    toggleRead(target.dataset.read);
    return;
  }
  if (target.dataset.rate) {
    event.stopPropagation();
    const [id, rating] = target.dataset.rate.split(":");
    setRating(id, Number(rating));
    return;
  }
  if (target.dataset.link) {
    event.stopPropagation();
    openURL(target.dataset.link);
    return;
  }
  if (target.dataset.refreshAll) {
    refreshAll({ force: true });
    return;
  }
  if (target.dataset.export) {
    const blob = new Blob([JSON.stringify(state.library, null, 2)], { type: "application/json" });
    openURL(URL.createObjectURL(blob));
    return;
  }
  if (target.dataset.open) {
    const item = itemByID(target.dataset.open);
    if (item) showDetail(item);
  }
});

els.search.addEventListener("input", (event) => {
  state.query = event.target.value;
  renderList();
});

els.refresh.addEventListener("click", () => refreshAll({ force: true }));

window.addEventListener("online", () => {
  state.message = "网络已恢复。";
  refreshAll({ force: true });
});

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js").catch(() => {});
}

refreshAll();
