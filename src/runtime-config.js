/**
 * Runtime configuration — persistent feature toggles that can be flipped from
 * the dashboard at runtime without a restart or editing .env. Backed by a
 * small JSON file next to the project root so it survives redeploys.
 *
 * Currently hosts the "experimental" feature flags. Keep this tiny: anything
 * that needs a restart should stay in config.js / .env.
 */

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { log } from './config.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, '..', 'runtime-config.json');

// Keys that hold numeric values instead of booleans.
const NUMERIC_KEYS = new Set(['responseCacheTTL', 'conversationPoolTTL']);

const DEFAULTS = {
  experimental: {
    // Local exact-match response cache for chat completions. When enabled,
    // identical requests within the TTL window return the stored response
    // instantly. Disable to force every request to hit the upstream model.
    responseCache: true,
    // Response cache TTL in seconds. Default 300 = 5 minutes.
    // Set to 0 to effectively disable caching (entries expire immediately).
    responseCacheTTL: 300,
    // Reuse Cascade cascade_id across multi-turn requests when the history
    // fingerprint matches. Big latency win for long conversations but relies
    // on Windsurf keeping the cascade alive — off by default.
    cascadeConversationReuse: false,
    // Conversation pool TTL in seconds. Default 600 = 10 minutes.
    // Controls how long idle cascade entries stay in the reuse pool.
    conversationPoolTTL: 600,
    // Inject a system prompt that tells the model to identify itself as the
    // requested model (e.g. "You are Claude Opus 4.6, made by Anthropic")
    // instead of revealing the Windsurf/Cascade backend. Enabled by default
    // so API responses match official Claude/GPT behaviour.
    modelIdentityPrompt: true,
    // Pre-flight rate limit check via server.codeium.com before sending a
    // chat request. Reduces wasted attempts when the account has no message
    // capacity. Adds one network round-trip per attempt so off by default.
    preflightRateLimit: false,
  },
};

function deepMerge(base, override) {
  if (!override || typeof override !== 'object') return base;
  const out = { ...base };
  for (const [k, v] of Object.entries(override)) {
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      out[k] = deepMerge(base[k] || {}, v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

let _state = structuredClone(DEFAULTS);

function load() {
  if (!existsSync(FILE)) return;
  try {
    const raw = JSON.parse(readFileSync(FILE, 'utf-8'));
    _state = deepMerge(DEFAULTS, raw);
  } catch (e) {
    log.warn(`runtime-config: failed to load ${FILE}: ${e.message}`);
  }
}

function persist() {
  try {
    writeFileSync(FILE, JSON.stringify(_state, null, 2));
  } catch (e) {
    log.warn(`runtime-config: failed to persist: ${e.message}`);
  }
}

load();

export function getRuntimeConfig() {
  return structuredClone(_state);
}

export function getExperimental() {
  return { ...(_state.experimental || {}) };
}

export function isExperimentalEnabled(key) {
  return !!_state.experimental?.[key];
}

export function getExperimentalValue(key) {
  return _state.experimental?.[key] ?? DEFAULTS.experimental?.[key];
}

export function setExperimental(patch) {
  if (!patch || typeof patch !== 'object') return getExperimental();
  _state.experimental = { ...(_state.experimental || {}), ...patch };
  // Coerce values: numeric keys stay as numbers, everything else becomes boolean.
  for (const k of Object.keys(_state.experimental)) {
    if (NUMERIC_KEYS.has(k)) {
      const n = Number(_state.experimental[k]);
      _state.experimental[k] = Number.isFinite(n) && n >= 0 ? n : DEFAULTS.experimental[k];
    } else {
      _state.experimental[k] = !!_state.experimental[k];
    }
  }
  persist();
  return getExperimental();
}
