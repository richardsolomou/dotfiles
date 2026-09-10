// Registers the PostHog AI Gateway as pi providers, taking the model list from
// the gateway's own /v1/models catalog instead of a checked-in snapshot.
//
// Discovery happens in the async extension factory because that is the only
// place an extension can populate a provider from the network: pi builds its
// model runtime before applying extension provider registrations and then
// refreshes cache-only, so a provider's own refreshModels() is never granted
// network access. pi awaits the factory, so models are present for interactive
// startup and for --list-models alike.
//
// To keep that fetch off the startup path most of the time, the catalog is
// cached locally and only refetched once it ages out. Anything unexpected —
// offline, a slow gateway, a bad response — falls back to the cached catalog
// and, failing that, registers nothing rather than blocking startup.
//
// The catalog publishes ids, context windows, prices and API shapes, but not
// whether a model reasons, accepts images, its output ceiling, or per-model
// quirks. Because the gateway serves the same ids as the Claude and Codex
// subscriptions, pi's own catalogs answer those. That join is what supplies
// forceAdaptiveThinking, which newer Claude models reject requests without.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const GATEWAY = (process.env.POSTHOG_GATEWAY_URL ?? "https://ai-gateway.us.posthog.com").replace(/\/+$/, "");
const AGENT_DIR = join(homedir(), ".pi", "agent");
const STORE_PATH = join(AGENT_DIR, "models-store.json");
const CACHE_PATH = join(AGENT_DIR, "gateway-catalog-cache.json");
const AUTH_PATH = join(AGENT_DIR, "auth.json");

const ANTHROPIC_PROVIDER = "posthog-gateway-anthropic";
const OPENAI_PROVIDER = "posthog-gateway-openai";

// The curated catalog changes on the order of weeks, so a stale-while-usable
// cache keeps all but one startup a day off the network entirely.
const CACHE_TTL_MS = 12 * 60 * 60 * 1000;
// The factory blocks startup, so give the gateway a short leash.
const FETCH_TIMEOUT_MS = 5_000;

interface CatalogModel {
  id: string;
  name?: string;
  owned_by?: string;
  context_window?: number;
  api_shapes?: string[];
  pricing?: { prompt?: string; completion?: string; cache_read?: string; cache_write?: string };
}

interface Traits {
  reasoning?: boolean;
  input?: ("text" | "image")[];
  maxTokens?: number;
  compat?: Record<string, unknown>;
  thinkingLevelMap?: Record<string, string | null>;
}

function readJson<T>(path: string): T | undefined {
  try {
    return JSON.parse(readFileSync(path, "utf8")) as T;
  } catch {
    return undefined;
  }
}

function gatewayKey(): string | undefined {
  if (process.env.POSTHOG_GATEWAY_KEY) return process.env.POSTHOG_GATEWAY_KEY;
  const auth = readJson<Record<string, { key?: string }>>(AUTH_PATH);
  return auth?.[OPENAI_PROVIDER]?.key ?? auth?.[ANTHROPIC_PROVIDER]?.key;
}

function perMillion(value: string | undefined): number {
  if (!value) return 0;
  const rate = Number(value) * 1_000_000;
  return Number.isFinite(rate) ? Math.round(rate * 100_000) / 100_000 : 0;
}

// Traits come from the subscription catalogs; the gateway serves the same ids.
function subscriptionTraits(): Record<string, Traits> {
  const traits: Record<string, Traits> = {};
  const store = readJson<Record<string, { models?: unknown[] }>>(STORE_PATH) ?? {};
  for (const [providerId, entry] of Object.entries(store)) {
    if (providerId === ANTHROPIC_PROVIDER || providerId === OPENAI_PROVIDER) continue;
    for (const model of entry?.models ?? []) {
      const m = model as { id?: string } & Traits;
      if (!m?.id || traits[m.id]) continue;
      traits[m.id] = {
        reasoning: m.reasoning,
        input: m.input,
        maxTokens: m.maxTokens,
        compat: m.compat,
        thinkingLevelMap: m.thinkingLevelMap ?? undefined,
      };
    }
  }
  return traits;
}

// Effort params are accepted by the GPT-5/6 and o-series lines and by the
// open-weight checkpoints; older OpenAI lines reject them.
function likelyReasons(model: CatalogModel): boolean {
  return model.owned_by === "posthog" || /^o[0-9]/.test(model.id) || /^gpt-[56]/.test(model.id);
}

function toConfig(model: CatalogModel, traits: Record<string, Traits>) {
  const t = traits[model.id] ?? {};
  return {
    id: model.id,
    name: `${model.name ?? model.id} (Gateway)`,
    reasoning: t.reasoning ?? likelyReasons(model),
    input: t.input ?? ["text"],
    contextWindow: model.context_window ?? 128_000,
    maxTokens: t.maxTokens ?? 16_384,
    cost: {
      input: perMillion(model.pricing?.prompt),
      output: perMillion(model.pricing?.completion),
      cacheRead: perMillion(model.pricing?.cache_read),
      cacheWrite: perMillion(model.pricing?.cache_write),
    },
    ...(t.compat ? { compat: t.compat } : {}),
    ...(t.thinkingLevelMap ? { thinkingLevelMap: t.thinkingLevelMap } : {}),
    // Open-weight checkpoints run on vLLM-class backends; chat completions is
    // the shape they all implement.
    ...(model.owned_by === "posthog" ? { api: "openai-completions" as const } : {}),
  };
}

async function loadCatalog(): Promise<CatalogModel[]> {
  const cache = readJson<{ fetchedAt?: number; models?: CatalogModel[] }>(CACHE_PATH);
  const cached = cache?.models ?? [];
  const fresh = cache?.fetchedAt && Date.now() - cache.fetchedAt < CACHE_TTL_MS;
  const offline = process.env.PI_OFFLINE === "1" || process.argv.includes("--offline");

  if (fresh || offline) return cached;

  const key = gatewayKey();
  if (!key) return cached;

  try {
    const response = await fetch(`${GATEWAY}/v1/models`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (!response.ok) return cached;
    const payload = (await response.json()) as { data?: CatalogModel[] };
    const models = (payload.data ?? []).filter((m) => m?.id);
    if (models.length === 0) return cached;

    try {
      mkdirSync(dirname(CACHE_PATH), { recursive: true });
      writeFileSync(CACHE_PATH, JSON.stringify({ fetchedAt: Date.now(), models }, null, 2));
    } catch {
      // A missed cache write only costs a fetch on the next startup.
    }
    return models;
  } catch {
    // Offline, timing out, or an unhealthy gateway: the last known catalog is
    // more useful than an empty provider, and startup must not block on this.
    return cached;
  }
}

export default async function (pi: ExtensionAPI) {
  const catalog = await loadCatalog();
  if (catalog.length === 0) return;

  const traits = subscriptionTraits();
  // Image and realtime endpoints are not usable as pi chat models.
  const usable = catalog.filter((m) => !/image|realtime/.test(m.id));
  const speaks = (m: CatalogModel) => (m.api_shapes ?? []).includes("anthropic-messages");

  const anthropicModels = usable.filter(speaks).map((m) => toConfig(m, traits));
  const openaiModels = usable.filter((m) => !speaks(m)).map((m) => toConfig(m, traits));

  if (anthropicModels.length > 0) {
    pi.registerProvider(ANTHROPIC_PROVIDER, {
      name: "PostHog AI Gateway (Anthropic)",
      baseUrl: GATEWAY,
      api: "anthropic-messages",
      models: anthropicModels,
    } as never);
  }

  if (openaiModels.length > 0) {
    pi.registerProvider(OPENAI_PROVIDER, {
      name: "PostHog AI Gateway (OpenAI-compatible)",
      baseUrl: `${GATEWAY}/v1`,
      api: "openai-responses",
      models: openaiModels,
    } as never);
  }
}
