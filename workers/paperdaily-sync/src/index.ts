interface Env {
  PAPERDAILY_SYNC: KVNamespace;
  SYNC_TOKEN: string;
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

    return json({ error: "not_found" }, { status: 404 });
  },
};
