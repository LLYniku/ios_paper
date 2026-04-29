interface Env {
  PAPERDAILY_SYNC: KVNamespace;
  SYNC_TOKEN: string;
  GITHUB_TOKEN?: string;
  GITHUB_OWNER?: string;
  GITHUB_REPO?: string;
  GITHUB_WORKFLOW?: string;
  GITHUB_REF?: string;
}

interface SyncedEnvelope<T> {
  updatedAt: string;
  value: T;
}

interface SyncedStateSnapshot {
  schema_version: string;
  preferences: SyncedEnvelope<unknown>;
  paper_favorite_records: SyncedEnvelope<unknown>;
  paper_read_ids: SyncedEnvelope<unknown>;
  classic_favorite_records: SyncedEnvelope<unknown>;
  classic_read_ids: SyncedEnvelope<unknown>;
  network_favorite_records: SyncedEnvelope<unknown>;
  network_read_ids: SyncedEnvelope<unknown>;
  recent_open_entries: SyncedEnvelope<unknown>;
}

const STATE_KEY = "state:default";
const DEFAULT_GITHUB_OWNER = "LLYniku";
const DEFAULT_GITHUB_REPO = "ios_paper";
const DEFAULT_GITHUB_WORKFLOW = "add-paper-to-today.yml";
const DEFAULT_GITHUB_REF = "dev";
const ARXIV_URL_PATTERN = /^https:\/\/(?:www\.)?arxiv\.org\/(?:abs|pdf|html)\/\d{4}\.\d{4,5}(?:v\d+)?(?:\.pdf)?(?:[?#].*)?$/i;

const json = (body: unknown, init?: ResponseInit) =>
  new Response(JSON.stringify(body, null, 2), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...(init?.headers ?? {}),
    },
  });

function unauthorized() {
  return json({ error: "unauthorized" }, { status: 401 });
}

function methodNotAllowed() {
  return json({ error: "method_not_allowed" }, { status: 405 });
}

function badRequest(message: string) {
  return json({ error: "bad_request", message }, { status: 400 });
}

function serviceUnavailable(message: string) {
  return json({ error: "service_unavailable", message }, { status: 503 });
}

function compareEnvelope<T>(localValue: SyncedEnvelope<T>, remoteValue: SyncedEnvelope<T>): SyncedEnvelope<T> {
  return new Date(localValue.updatedAt).getTime() >= new Date(remoteValue.updatedAt).getTime()
    ? localValue
    : remoteValue;
}

function mergeSnapshots(localSnapshot: SyncedStateSnapshot, remoteSnapshot: SyncedStateSnapshot): SyncedStateSnapshot {
  return {
    schema_version: "1.0",
    preferences: compareEnvelope(localSnapshot.preferences, remoteSnapshot.preferences),
    paper_favorite_records: compareEnvelope(localSnapshot.paper_favorite_records, remoteSnapshot.paper_favorite_records),
    paper_read_ids: compareEnvelope(localSnapshot.paper_read_ids, remoteSnapshot.paper_read_ids),
    classic_favorite_records: compareEnvelope(localSnapshot.classic_favorite_records, remoteSnapshot.classic_favorite_records),
    classic_read_ids: compareEnvelope(localSnapshot.classic_read_ids, remoteSnapshot.classic_read_ids),
    network_favorite_records: compareEnvelope(localSnapshot.network_favorite_records, remoteSnapshot.network_favorite_records),
    network_read_ids: compareEnvelope(localSnapshot.network_read_ids, remoteSnapshot.network_read_ids),
    recent_open_entries: compareEnvelope(localSnapshot.recent_open_entries, remoteSnapshot.recent_open_entries),
  };
}

function isAuthorized(request: Request, token: string) {
  const header = request.headers.get("authorization");
  return header === `Bearer ${token}`;
}

async function loadSnapshot(env: Env): Promise<SyncedStateSnapshot | null> {
  const raw = await env.PAPERDAILY_SYNC.get(STATE_KEY);
  if (!raw) {
    return null;
  }
  return JSON.parse(raw) as SyncedStateSnapshot;
}

function normalizePaperURL(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  if (!ARXIV_URL_PATTERN.test(trimmed)) {
    return null;
  }
  return trimmed;
}

async function dispatchAddPaperWorkflow(env: Env, paperURL: string): Promise<Response> {
  if (!env.GITHUB_TOKEN) {
    return serviceUnavailable("missing_github_token");
  }

  const owner = env.GITHUB_OWNER || DEFAULT_GITHUB_OWNER;
  const repo = env.GITHUB_REPO || DEFAULT_GITHUB_REPO;
  const workflow = env.GITHUB_WORKFLOW || DEFAULT_GITHUB_WORKFLOW;
  const ref = env.GITHUB_REF || DEFAULT_GITHUB_REF;
  const endpoint = `https://api.github.com/repos/${owner}/${repo}/actions/workflows/${workflow}/dispatches`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "paperdaily-sync-worker",
    },
    body: JSON.stringify({
      ref,
      inputs: {
        paper_url: paperURL,
      },
    }),
  });

  if (!response.ok) {
    const message = await response.text();
    return json(
      {
        error: "github_dispatch_failed",
        status: response.status,
        message,
      },
      { status: 502 },
    );
  }

  return json(
    {
      accepted: true,
      owner,
      repo,
      workflow,
      ref,
    },
    { status: 202 },
  );
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ ok: true });
    }

    if (!isAuthorized(request, env.SYNC_TOKEN)) {
      return unauthorized();
    }

    if (url.pathname === "/v1/state") {
      if (request.method !== "GET") {
        return methodNotAllowed();
      }
      const state = await loadSnapshot(env);
      return json({ state });
    }

    if (url.pathname === "/v1/state/merge") {
      if (request.method !== "POST") {
        return methodNotAllowed();
      }

      let incoming: SyncedStateSnapshot;
      try {
        incoming = (await request.json()) as SyncedStateSnapshot;
      } catch {
        return badRequest("invalid_json");
      }

      if (incoming.schema_version !== "1.0") {
        return badRequest("unsupported_schema_version");
      }

      const existing = await loadSnapshot(env);
      const merged = existing ? mergeSnapshots(incoming, existing) : incoming;
      await env.PAPERDAILY_SYNC.put(STATE_KEY, JSON.stringify(merged));
      return json({ state: merged });
    }

    if (url.pathname === "/v1/paper-submissions") {
      if (request.method !== "POST") {
        return methodNotAllowed();
      }

      let payload: { paper_url?: unknown };
      try {
        payload = (await request.json()) as { paper_url?: unknown };
      } catch {
        return badRequest("invalid_json");
      }

      const paperURL = normalizePaperURL(payload.paper_url);
      if (!paperURL) {
        return badRequest("only_arxiv_abs_pdf_or_html_urls_are_supported");
      }

      return dispatchAddPaperWorkflow(env, paperURL);
    }

    return json({ error: "not_found" }, { status: 404 });
  },
};
