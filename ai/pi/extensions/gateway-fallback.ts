// Automatic fallback between subscription models (Claude Pro/Max, ChatGPT
// Codex) and their PostHog AI Gateway equivalents (see ai/pi/models.json).
//
// - A subscription call that ends in error switches the active model to the
//   matching gateway model and resends the last user turn, so the current
//   request completes without retyping anything.
// - Cooldown backs off 5m -> 10m -> ... capped at 60m per provider. While
//   cooling down, new turns are preemptively routed to the gateway instead of
//   guaranteed-failing against the subscription again.
// - Once a cooldown elapses, the next turn is routed back to the subscription
//   model that failed. A success there clears the cooldown; a failure
//   restarts it (doubled), so it self-heals without polling in the
//   background.
//
// State persists in gateway-fallback-state.json next to this extension so it
// survives across pi restarts and projects (usage limits are account-wide,
// not per-session).
//
// Caveat: neither Anthropic's nor OpenAI's OAuth subscription errors reliably
// expose a machine-readable "resets at" time through pi's provider layer, so
// this reacts to *any* terminal error on a tracked subscription provider
// rather than pattern-matching quota-specific wording. A transient, otherwise
// self-recovering error also triggers one cooldown cycle; that costs a bit of
// gateway usage but never blocks the turn.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

// Lives outside the (symlinked, dotfiles-tracked) extension file itself —
// this is per-machine, account-specific runtime state, not config.
const STATE_PATH = join(homedir(), ".pi", "agent", "gateway-fallback-state.json");

const INITIAL_BACKOFF_MS = 5 * 60 * 1000;
const MAX_BACKOFF_MS = 60 * 60 * 1000;

// The gateway carries the same model ids as the subscriptions, so a fallback
// keeps the model you were using. `defaultModelId` only covers ids the gateway
// does not serve under any spelling (e.g. gpt-5.3-codex-spark).
const FALLBACK_PAIRS: Record<string, { gatewayProvider: string; defaultModelId: string }> = {
  anthropic: { gatewayProvider: "posthog-gateway-anthropic", defaultModelId: "claude-sonnet-4-6" },
  "openai-codex": { gatewayProvider: "posthog-gateway-openai", defaultModelId: "gpt-5.6-terra" },
};

const GATEWAY_TO_SUBSCRIPTION: Record<string, string> = Object.fromEntries(
  Object.entries(FALLBACK_PAIRS).map(([sub, cfg]) => [cfg.gatewayProvider, sub]),
);

interface ProviderState {
  lastFailureAt: number | null;
  backoffMs: number;
  modelId: string | null;
}

type State = Record<string, ProviderState>;

function loadState(): State {
  try {
    return JSON.parse(readFileSync(STATE_PATH, "utf8"));
  } catch {
    return {};
  }
}

function saveState(state: State) {
  try {
    mkdirSync(dirname(STATE_PATH), { recursive: true });
    writeFileSync(STATE_PATH, JSON.stringify(state, null, 2));
  } catch {
    // Best-effort. A missed persist just means we re-probe sooner than ideal.
  }
}

function getState(state: State, provider: string): ProviderState {
  return state[provider] ?? { lastFailureAt: null, backoffMs: INITIAL_BACKOFF_MS, modelId: null };
}

// Prefer the same model on the gateway, then the same model without its date
// pin (the gateway serves undated ids), then the provider's default.
function resolveGatewayModel(
  registry: { find: (provider: string, id: string) => unknown },
  pair: { gatewayProvider: string; defaultModelId: string },
  failedModelId: string | null,
) {
  const candidates = [
    failedModelId,
    failedModelId?.replace(/-\d{8}$/, ""),
    pair.defaultModelId,
  ];
  for (const id of candidates) {
    if (!id) continue;
    const model = registry.find(pair.gatewayProvider, id);
    if (model) return { model, id };
  }
  return undefined;
}

function extractText(content: unknown): string | undefined {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    const text = content
      .filter((b): b is { type: "text"; text: string } => b?.type === "text")
      .map((b) => b.text)
      .join("\n");
    return text || undefined;
  }
  return undefined;
}

export default function (pi: ExtensionAPI) {
  let state = loadState();

  pi.on("before_agent_start", async (_event, ctx) => {
    const model = ctx.model;
    if (!model) return;
    const now = Date.now();

    const pair = FALLBACK_PAIRS[model.provider];
    if (pair) {
      const s = getState(state, model.provider);
      if (s.lastFailureAt && now - s.lastFailureAt < s.backoffMs) {
        const target = resolveGatewayModel(ctx.modelRegistry, pair, model.id);
        if (target && (await pi.setModel(target.model))) {
          const minsLeft = Math.ceil((s.backoffMs - (now - s.lastFailureAt)) / 60000);
          if (ctx.hasUI) {
            ctx.ui.notify(
              `${model.provider} is cooling down (~${minsLeft}m left) — using ${target.id} on PostHog AI Gateway`,
              "info",
            );
          }
        }
      }
      return;
    }

    const subscriptionProvider = GATEWAY_TO_SUBSCRIPTION[model.provider];
    if (!subscriptionProvider) return;
    const s = getState(state, subscriptionProvider);
    if (s.lastFailureAt && s.modelId && now - s.lastFailureAt >= s.backoffMs) {
      const target = ctx.modelRegistry.find(subscriptionProvider, s.modelId);
      if (target && (await pi.setModel(target))) {
        if (ctx.hasUI) {
          ctx.ui.notify(`Cooldown elapsed — retrying ${subscriptionProvider} subscription`, "info");
        }
      }
    }
  });

  pi.on("message_end", async (event, ctx) => {
    if (event.message.role !== "assistant") return;
    const provider = event.message.provider;
    if (!provider || !FALLBACK_PAIRS[provider]) return;
    const now = Date.now();

    if (event.message.stopReason !== "error") {
      if (state[provider]?.lastFailureAt) {
        state[provider] = { lastFailureAt: null, backoffMs: INITIAL_BACKOFF_MS, modelId: null };
        saveState(state);
        if (ctx.hasUI) ctx.ui.notify(`${provider} subscription recovered — staying on it`, "info");
      }
      return;
    }

    const pair = FALLBACK_PAIRS[provider];
    const prev = getState(state, provider);
    state[provider] = {
      lastFailureAt: now,
      backoffMs: prev.lastFailureAt ? Math.min(prev.backoffMs * 2, MAX_BACKOFF_MS) : INITIAL_BACKOFF_MS,
      modelId: event.message.model ?? prev.modelId,
    };
    saveState(state);

    const target = resolveGatewayModel(ctx.modelRegistry, pair, event.message.model ?? null);
    if (!target) {
      if (ctx.hasUI) {
        ctx.ui.notify(`${provider} errored and no PostHog gateway model is configured to fall back to`, "error");
      }
      return;
    }
    if (!(await pi.setModel(target.model))) {
      if (ctx.hasUI) {
        ctx.ui.notify(`${provider} errored; PostHog gateway fallback has no API key configured`, "error");
      }
      return;
    }
    if (ctx.hasUI) {
      ctx.ui.notify(
        `${provider} errored (${event.message.errorMessage ?? "unknown error"}) — falling back to ${target.id} on PostHog AI Gateway`,
        "warning",
      );
    }

    const branch = ctx.sessionManager.getBranch();
    for (let i = branch.length - 1; i >= 0; i--) {
      const entry = branch[i];
      if (entry.type === "message" && entry.message.role === "user") {
        const text = extractText(entry.message.content);
        if (text) pi.sendUserMessage(text, { deliverAs: "followUp" });
        break;
      }
    }
  });

  pi.registerCommand("gateway-fallback", {
    description: "Show PostHog AI Gateway fallback status per subscription provider",
    handler: async (_args, ctx) => {
      const now = Date.now();
      const lines = Object.keys(FALLBACK_PAIRS).map((provider) => {
        const s = getState(state, provider);
        if (!s.lastFailureAt) return `${provider}: healthy`;
        const remaining = Math.max(0, Math.ceil((s.backoffMs - (now - s.lastFailureAt)) / 60000));
        return remaining > 0
          ? `${provider}: on gateway, retrying in ~${remaining}m (model was ${s.modelId})`
          : `${provider}: cooldown elapsed, will retry next turn (model was ${s.modelId})`;
      });
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });
}
