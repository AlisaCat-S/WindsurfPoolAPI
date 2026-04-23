/**
 * Cascade conversation reuse pool (experimental).
 *
 * Goal: when a multi-turn chat continues a previous exchange, reuse the same
 * Windsurf `cascade_id` instead of starting a fresh one. This lets the
 * Windsurf backend keep its own per-cascade context cached — we avoid
 * resending the full history on each turn and the server responds faster.
 *
 * The key is a "fingerprint" of the conversation up to (but not including)
 * the newest user message. A client sending [u1, a1, u2] looks up fp([u1, a1]);
 * a hit means we already drove the cascade to exactly that state. We then
 * `SendUserCascadeMessage(u2)` on the stored cascade_id and, on success,
 * re-store the entry under fp([u1, a1, u2, a2]) for the next turn.
 *
 * Safety rails:
 *   - Entries are pinned to a specific (apiKey, lsPort) pair. We must reuse
 *     the same LS and the same account or the cascade_id is meaningless.
 *   - A checked-out entry is removed from the pool. Concurrent second request
 *     with the same fingerprint falls back to a fresh cascade.
 *   - TTL configurable (default 10 min); LRU eviction at 500 entries.
 *
 * Fingerprint strategy (aligned with WindsurfAPI #24):
 *   - Hash only USER messages (excluding the latest one we're about to send).
 *     User messages have stable format across client round-trips; assistant
 *     messages don't — the client may restructure content arrays, add
 *     tool_use blocks, or modify text, causing hash mismatches and 0% hit rate.
 *   - modelKey and system prompt prefix are included in the hash so that
 *     model switches or system prompt changes don't erroneously reuse a
 *     stale cascade.
 */

import { createHash } from 'crypto';
import { getExperimentalValue } from './runtime-config.js';

// Default 10 min; overridable at runtime via dashboard.
const DEFAULT_POOL_TTL_MS = 10 * 60 * 1000;
function getPoolTTLMs() {
  const secs = getExperimentalValue('conversationPoolTTL');
  return (typeof secs === 'number' && secs >= 0) ? secs * 1000 : DEFAULT_POOL_TTL_MS;
}
const POOL_MAX = 500;

// fingerprint -> { cascadeId, sessionId, lsPort, apiKey, createdAt, lastAccess }
const _pool = new Map();

const stats = { hits: 0, misses: 0, stores: 0, evictions: 0, expired: 0 };

function sha256(s) {
  return createHash('sha256').update(s).digest('hex');
}

/**
 * Canonicalise a message list for hashing. Strips anything that could drift
 * between turns (id, name, tool metadata) and normalises content to a
 * string so array/string forms collide correctly.
 */
function canonicalise(messages) {
  return messages.map(m => ({
    role: m.role,
    content: typeof m.content === 'string'
      ? m.content
      : Array.isArray(m.content)
        ? m.content.map(p => (typeof p?.text === 'string' ? p.text : JSON.stringify(p))).join('')
        : JSON.stringify(m.content ?? ''),
  }));
}

/**
 * Extract a stable prefix from system messages for inclusion in the hash.
 * This ensures that different system prompts produce different fingerprints.
 */
function systemPrefix(messages) {
  return messages
    .filter(m => m.role === 'system')
    .map(m => typeof m.content === 'string' ? m.content : JSON.stringify(m.content ?? ''))
    .join('\0');
}

/**
 * Fingerprint for "resume this conversation". Hash only USER messages
 * (excluding the latest one we're about to send). User messages have stable
 * format across client round-trips; assistant messages don't — the client
 * may restructure content arrays, add tool_use blocks, or modify text,
 * causing hash mismatches and 0% hit rate. (#24)
 *
 * modelKey is included so that switching models within the same conversation
 * doesn't erroneously reuse an old cascade. systemPrefix is included so
 * that changing the system prompt also invalidates the fingerprint.
 *
 * Returns null when there's nothing to resume (first turn or < 2 user turns).
 */
export function fingerprintBefore(messages, modelKey = '') {
  if (!Array.isArray(messages) || messages.length < 2) return null;
  const users = messages.filter(m => m.role === 'user');
  if (users.length < 2) return null;
  return sha256(modelKey + '\0' + systemPrefix(messages) + '\0' + JSON.stringify(canonicalise(users.slice(0, -1))));
}

/**
 * Fingerprint for the full conversation after we append our assistant turn.
 * This is what the *next* request's `fingerprintBefore` will look up.
 *
 * Only user messages are hashed (same strategy as fingerprintBefore).
 */
export function fingerprintAfter(messages, modelKey = '') {
  const users = messages.filter(m => m.role === 'user');
  if (!users.length) return null;
  return sha256(modelKey + '\0' + systemPrefix(messages) + '\0' + JSON.stringify(canonicalise(users)));
}

function prune(now) {
  const ttl = getPoolTTLMs();
  // First pass: actively clear expired entries.
  for (const [fp, e] of _pool) {
    if (now - e.lastAccess > ttl) { _pool.delete(fp); stats.expired++; }
  }
  // Second pass: if still over capacity, LRU evict.
  if (_pool.size <= POOL_MAX) return;
  const entries = [..._pool.entries()].sort((a, b) => a[1].lastAccess - b[1].lastAccess);
  const toDrop = entries.length - POOL_MAX;
  for (let i = 0; i < toDrop; i++) {
    _pool.delete(entries[i][0]);
    stats.evictions++;
  }
}

/**
 * Check out a conversation if we have a matching fingerprint AND the caller
 * is willing to use the same (apiKey, lsPort) we stored. Removes the entry
 * from the pool — caller is expected to call `checkin()` with a new
 * fingerprint on success (or just drop it on failure and a fresh cascade
 * will be created next turn).
 */
export function checkout(fingerprint) {
  if (!fingerprint) { stats.misses++; return null; }
  const entry = _pool.get(fingerprint);
  if (!entry) { stats.misses++; return null; }
  _pool.delete(fingerprint);
  if (Date.now() - entry.lastAccess > getPoolTTLMs()) {
    stats.expired++;
    stats.misses++;
    return null;
  }
  stats.hits++;
  return entry;
}

/**
 * Store (or restore) a conversation entry under a new fingerprint.
 */
export function checkin(fingerprint, entry) {
  if (!fingerprint || !entry) return;
  const now = Date.now();
  _pool.set(fingerprint, {
    cascadeId: entry.cascadeId,
    sessionId: entry.sessionId,
    lsPort: entry.lsPort,
    apiKey: entry.apiKey,
    createdAt: entry.createdAt || now,
    lastAccess: now,
  });
  stats.stores++;
  prune(now);
}

/**
 * Drop any entries that belong to a (apiKey, lsPort) pair that just went
 * away (account removed, LS restarted). Keeps the pool honest.
 */
export function invalidateFor({ apiKey, lsPort }) {
  let dropped = 0;
  for (const [fp, e] of _pool) {
    if ((apiKey && e.apiKey === apiKey) || (lsPort && e.lsPort === lsPort)) {
      _pool.delete(fp);
      dropped++;
    }
  }
  return dropped;
}

export function poolStats() {
  return {
    size: _pool.size,
    maxSize: POOL_MAX,
    ttlMs: getPoolTTLMs(),
    ...stats,
    hitRate: stats.hits + stats.misses > 0
      ? ((stats.hits / (stats.hits + stats.misses)) * 100).toFixed(1)
      : '0.0',
  };
}

export function poolClear() {
  const n = _pool.size;
  _pool.clear();
  return n;
}
