# PaperDaily Sync Worker

This Cloudflare Worker stores the user's synced PaperDaily state in KV.

It is designed for a single-user setup:
- one Worker
- one KV namespace
- one bearer token shared by your iPhone and Mac apps

## Endpoints

- `GET /health`
- `GET /v1/state`
- `POST /v1/state/merge`

`/v1/state` and `/v1/state/merge` require:

```text
Authorization: Bearer <SYNC_TOKEN>
```

## Deploy

1. Install dependencies:

```bash
cd workers/paperdaily-sync
npm install
```

2. Create KV:

```bash
npx wrangler kv namespace create PAPERDAILY_SYNC
```

3. Copy the returned namespace id into [wrangler.jsonc](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/workers/paperdaily-sync/wrangler.jsonc).

4. Set the sync token:

```bash
npx wrangler secret put SYNC_TOKEN
```

5. Deploy:

```bash
npx wrangler deploy
```

After deploy, the Worker base URL will look like:

```text
https://paperdaily-sync.<your-subdomain>.workers.dev
```

## App Configuration

In the PaperDaily app Settings page:

- `Sync Base URL`: your Worker URL
- `Sync Token`: the same token you stored as `SYNC_TOKEN`

Once both iPhone and Mac use the same Worker URL and token, they will share:

- favorites
- read state
- ratings
- favorite snapshots
- recent opens
- basic preferences
