// Usernames are public handles, so the policy is applied on the normalized
// form only: trimmed and lowercased. Format is checked first, then reserved
// names (exact match), then offensive words (substring match).
const MIN_LENGTH = 3;
const MAX_LENGTH = 20;
const FORMAT = /^[a-z0-9._]+$/;

// Names that would impersonate the app or its staff. Exact match only, so a
// reserved word inside a longer name is still allowed.
const RESERVED = new Set([
  "admin",
  "support",
  "tracksip",
  "siptrack",
  "official",
  "moderator",
]);

// Short list of English and Spanish slurs and obscenities. Substring match,
// so every entry must be specific enough not to appear inside ordinary words.
const OFFENSIVE = [
  "fuck",
  "shit",
  "bitch",
  "cunt",
  "nigger",
  "faggot",
  "whore",
  "retard",
  "mierda",
  "pendejo",
  "cabron",
  "chingar",
  "maricon",
  "verga",
];

/**
 * Trims and lowercases a raw username.
 * @param {string} raw the username as typed
 * @return {string} the canonical form used for storage and comparison
 */
function normalizeUsername(raw) {
  return String(raw).trim().toLowerCase();
}

/**
 * Checks a username against the format and blocklist policy.
 * @param {string} name the username as typed; normalized before checking
 * @return {{ok: true} | {ok: false, reason: string}} "format" when the
 *     length or characters are wrong, "blocked" when the name is reserved or
 *     contains an offensive word
 */
function validateUsername(name) {
  if (typeof name !== "string") {
    return {ok: false, reason: "format"};
  }
  const normalized = normalizeUsername(name);
  if (
    normalized.length < MIN_LENGTH ||
    normalized.length > MAX_LENGTH ||
    !FORMAT.test(normalized)
  ) {
    return {ok: false, reason: "format"};
  }
  if (RESERVED.has(normalized)) {
    return {ok: false, reason: "blocked"};
  }
  if (OFFENSIVE.some((word) => normalized.includes(word))) {
    return {ok: false, reason: "blocked"};
  }
  return {ok: true};
}

module.exports = {normalizeUsername, validateUsername};
