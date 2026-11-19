const {HttpsError} = require("firebase-functions/v2/https");
const {normalizeUsername, validateUsername} = require("./username-policy");
const {validatePushToken, tokenIsDead} = require("./live-activity");

// ---------------------------------------------------------------------------
// Usernames and public profiles
// ---------------------------------------------------------------------------

const AVATAR_COLORS = [
  "#E8505B",
  "#F28C38",
  "#F2C14E",
  "#4CAF7A",
  "#2FA8A0",
  "#4A90D9",
  "#7A6FD6",
  "#C25BB0",
];
const SEARCH_LIMIT = 20;
const MIN_QUERY_LENGTH = 2;

/**
 * Picks a stable avatar color for a user.
 * @param {string} uid the user's id
 * @return {string} a color from the fixed palette
 */
function avatarColorFor(uid) {
  let hash = 0;
  for (const char of uid) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return AVATAR_COLORS[hash % AVATAR_COLORS.length];
}

const DELETING = "This account is being deleted.";

/**
 * Throws when the account is being deleted, so a late call from a still-valid
 * ID token can't recreate social data the deletion just removed.
 * @param {{exists: boolean}} marker the account_deletions/{uid} snapshot
 */
function assertNotDeleting(marker) {
  if (marker.exists) throw new HttpsError("failed-precondition", DELETING);
}

/**
 * Claims a unique username for the caller, releasing their previous one.
 * The handle and public profile are written in a single transaction so two
 * users can never own the same name.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{username: string}} params.data the request payload
 * @return {Promise<{username: string}>} the stored (normalized) username
 */
async function claimUsername({db, uid, data}) {
  const raw = data && data.username;
  if (!validateUsername(raw).ok) {
    throw new HttpsError("invalid-argument", "That username isn't allowed.");
  }
  const username = normalizeUsername(raw);
  const handleRef = db.doc(`usernames/${username}`);
  const profileRef = db.doc(`public_profiles/${uid}`);

  await db.runTransaction(async (tx) => {
    const [handle, profile, deleting] = await Promise.all([
      tx.get(handleRef),
      tx.get(profileRef),
      tx.get(db.doc(`account_deletions/${uid}`)),
    ]);
    assertNotDeleting(deleting);
    const current = profile.exists ? profile.data().username : null;
    if (handle.exists && handle.data().uid !== uid) {
      throw new HttpsError("already-exists", "That username is taken.");
    }
    if (current === username && handle.exists) return;

    if (current && current !== username) {
      tx.delete(db.doc(`usernames/${current}`));
    }
    tx.set(handleRef, {uid});
    if (profile.exists) {
      tx.update(profileRef, {username});
    } else {
      tx.set(profileRef, {username, avatar_color: avatarColorFor(uid)});
    }
  });
  return {username};
}

/**
 * Finds users whose username starts with the query.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{query: string}} params.data the request payload
 * @return {Promise<{results: object[]}>} matching public profiles, excluding
 *     the caller and anyone blocked in either direction
 */
async function searchUsers({db, uid, data}) {
  const query = normalizeUsername(data && data.query);
  if (query.length < MIN_QUERY_LENGTH) return {results: []};

  const blockedByCaller = new Set(
      (await db.collection(`blocks/${uid}/blocked`).get()).docs.map((d) => d.id),
  );
  // Over-fetch so exclusions rarely leave the page short.
  const snap = await db
      .collection("public_profiles")
      .orderBy("username")
      .startAt(query)
      .endAt(query + "")
      .limit(SEARCH_LIMIT * 3)
      .get();
  const candidates = snap.docs.filter(
      (d) => d.id !== uid && !blockedByCaller.has(d.id),
  );
  const blockedCaller = await Promise.all(
      candidates.map(
          async (d) => (await db.doc(`blocks/${d.id}/blocked/${uid}`).get()).exists,
      ),
  );
  const results = candidates
      .filter((_, i) => !blockedCaller[i])
      .slice(0, SEARCH_LIMIT)
      .map((d) => ({
        uid: d.id,
        username: d.data().username,
        photo_url: d.data().photo_url || null,
        avatar_color: d.data().avatar_color,
      }));
  return {results};
}

// ---------------------------------------------------------------------------
// Friend requests, friendships and blocks
// ---------------------------------------------------------------------------

/**
 * Validates a uid argument from the request payload.
 * @param {*} value the raw value
 * @param {string} caller the calling user's uid
 * @return {string} the uid
 */
function otherUid(value, caller) {
  if (typeof value !== "string" || value === "" || value.includes("/")) {
    throw new HttpsError("invalid-argument", "Missing user.");
  }
  if (value === caller) {
    throw new HttpsError("invalid-argument", "That's you.");
  }
  return value;
}

/**
 * Sends a notification without letting a failure leak out: the committed
 * friendship state is the source of truth.
 * @param {Function} notify injected notifier
 * @param {string} toUid recipient
 * @param {string} kind "request" or "accepted"
 * @param {string} fromUsername the acting user's username
 */
async function notifySafely(notify, toUid, kind, fromUsername) {
  try {
    await notify(toUid, kind, fromUsername);
  } catch (error) {
    console.error(`notify ${kind} failed`, error);
  }
}

/**
 * Sends a friend request, or accepts one the target already sent.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{toUid: string}} params.data the request payload
 * @param {Function} params.notify (toUid, kind, fromUsername) => Promise
 * @return {Promise<{status: string}>} "requested" or "friends"
 */
async function sendFriendRequest({db, uid, data, notify}) {
  const toUid = otherUid(data && data.toUid, uid);
  const now = Date.now();

  const outcome = await db.runTransaction(async (tx) => {
    const [me, them, blockedThem, blockedMe, friend, reverse, mine, deleting] =
      await Promise.all([
        tx.get(db.doc(`public_profiles/${uid}`)),
        tx.get(db.doc(`public_profiles/${toUid}`)),
        tx.get(db.doc(`blocks/${uid}/blocked/${toUid}`)),
        tx.get(db.doc(`blocks/${toUid}/blocked/${uid}`)),
        tx.get(db.doc(`friendships/${uid}/friends/${toUid}`)),
        tx.get(db.doc(`friend_requests/${toUid}_${uid}`)),
        tx.get(db.doc(`friend_requests/${uid}_${toUid}`)),
        tx.get(db.doc(`account_deletions/${uid}`)),
      ]);
    assertNotDeleting(deleting);
    if (!me.exists) {
      throw new HttpsError("failed-precondition", "Pick a username first.");
    }
    if (!them.exists) {
      throw new HttpsError("not-found", "That user doesn't exist.");
    }
    if (blockedThem.exists || blockedMe.exists) {
      throw new HttpsError("permission-denied", "You can't add that user.");
    }
    const fromUsername = me.data().username;
    if (friend.exists) return {status: "friends"};
    if (reverse.exists) {
      tx.delete(reverse.ref);
      if (mine.exists) tx.delete(mine.ref);
      tx.set(db.doc(`friendships/${uid}/friends/${toUid}`), {since: now});
      tx.set(db.doc(`friendships/${toUid}/friends/${uid}`), {since: now});
      return {status: "friends", kind: "accepted", fromUsername};
    }
    if (mine.exists) return {status: "requested"};
    tx.set(mine.ref, {from: uid, to: toUid, created_at: now});
    return {status: "requested", kind: "request", fromUsername};
  });

  if (outcome.kind) {
    await notifySafely(notify, toUid, outcome.kind, outcome.fromUsername);
  }
  return {status: outcome.status};
}

/**
 * Accepts or declines a pending request addressed to the caller.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{fromUid: string, accept: boolean}} params.data the payload
 * @param {Function} params.notify (toUid, kind, fromUsername) => Promise
 * @return {Promise<{status: string}>} "friends" or "declined"
 */
async function respondToFriendRequest({db, uid, data, notify}) {
  const fromUid = otherUid(data && data.fromUid, uid);
  if (!data || typeof data.accept !== "boolean") {
    throw new HttpsError("invalid-argument", "Missing accept flag.");
  }
  const accept = data.accept;
  const now = Date.now();

  const outcome = await db.runTransaction(async (tx) => {
    const [request, me, blockedThem, blockedMe, deleting] = await Promise.all([
      tx.get(db.doc(`friend_requests/${fromUid}_${uid}`)),
      tx.get(db.doc(`public_profiles/${uid}`)),
      tx.get(db.doc(`blocks/${uid}/blocked/${fromUid}`)),
      tx.get(db.doc(`blocks/${fromUid}/blocked/${uid}`)),
      tx.get(db.doc(`account_deletions/${uid}`)),
    ]);
    assertNotDeleting(deleting);
    if (!request.exists) {
      throw new HttpsError("not-found", "No such friend request.");
    }
    if (!accept) {
      tx.delete(request.ref);
      return {status: "declined"};
    }
    if (blockedThem.exists || blockedMe.exists) {
      throw new HttpsError("permission-denied", "You can't add that user.");
    }
    if (!me.exists) {
      throw new HttpsError("failed-precondition", "Pick a username first.");
    }
    tx.delete(request.ref);
    tx.set(db.doc(`friendships/${uid}/friends/${fromUid}`), {since: now});
    tx.set(db.doc(`friendships/${fromUid}/friends/${uid}`), {since: now});
    return {status: "friends", fromUsername: me.data().username};
  });

  if (outcome.status === "friends") {
    await notifySafely(notify, fromUid, "accepted", outcome.fromUsername);
  }
  return {status: outcome.status};
}

/**
 * Withdraws a request the caller sent.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{toUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "cancelled"
 */
async function cancelFriendRequest({db, uid, data}) {
  const toUid = otherUid(data && data.toUid, uid);
  await db.doc(`friend_requests/${uid}_${toUid}`).delete();
  return {status: "cancelled"};
}

/**
 * Ends a friendship on both sides.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{friendUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "removed"
 */
async function removeFriend({db, uid, data}) {
  const friendUid = otherUid(data && data.friendUid, uid);
  const batch = db.batch();
  batch.delete(db.doc(`friendships/${uid}/friends/${friendUid}`));
  batch.delete(db.doc(`friendships/${friendUid}/friends/${uid}`));
  await batch.commit();
  return {status: "removed"};
}

/**
 * Blocks a user and severs every tie with them in one atomic batch.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{targetUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "blocked"
 */
async function blockUser({db, uid, data}) {
  const targetUid = otherUid(data && data.targetUid, uid);
  const batch = db.batch();
  // The uid field lets account deletion find blocks via a collection group.
  batch.set(db.doc(`blocks/${uid}/blocked/${targetUid}`), {
    uid: targetUid,
    created_at: Date.now(),
  });
  batch.delete(db.doc(`friendships/${uid}/friends/${targetUid}`));
  batch.delete(db.doc(`friendships/${targetUid}/friends/${uid}`));
  batch.delete(db.doc(`friend_requests/${uid}_${targetUid}`));
  batch.delete(db.doc(`friend_requests/${targetUid}_${uid}`));
  await batch.commit();
  return {status: "blocked"};
}

/**
 * Lifts the caller's block on a user.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{targetUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "unblocked"
 */
async function unblockUser({db, uid, data}) {
  const targetUid = otherUid(data && data.targetUid, uid);
  await db.doc(`blocks/${uid}/blocked/${targetUid}`).delete();
  return {status: "unblocked"};
}

// ---------------------------------------------------------------------------
// Reports, push tokens and friend-request pushes
// ---------------------------------------------------------------------------

const REPORT_KINDS = ["username", "photo", "comment"];
const PUSH_COPY = {
  request: (username) => `@${username} sent you a friend request`,
  accepted: (username) => `@${username} accepted your friend request`,
  contact: (username) => `@${username} is on TrackSip. Add them as a friend`,
  contactNoProfile: (username) =>
    `@${username} is on TrackSip Social. Create your profile to add them`,
};
// What the app opens on tap: the friends screen, an add sheet for the
// sender, or Social (where someone without a profile picks a username).
const PUSH_ROUTE = {
  request: "friends",
  accepted: "friends",
  contact: "add",
  contactNoProfile: "social",
};

/**
 * Finds the comment a report is about and copies what the reviewer needs.
 * The reporter must still be able to see the night, and the comment must be
 * on it and written by the reported person.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the reporter
 * @param {string} params.targetUid the reported person
 * @param {{owner: string, startedAt: number, commentId: string}} params.data
 *     the payload
 * @return {Promise<object>} {id, night, uid, username, text}
 */
async function reportedComment({db, uid, targetUid, data}) {
  // Required here: interactions.js requires this module at load time.
  const {loadNight, nightKey} = require("./interactions");
  const {owner, startedAt, commentId} = data;
  if (typeof owner !== "string" || owner === "" || owner.includes("/") ||
      !Number.isFinite(startedAt) || typeof commentId !== "string" ||
      commentId === "" || commentId.includes("/")) {
    throw new HttpsError("invalid-argument", "That comment isn't valid.");
  }
  await loadNight({db, owner, startedAt, uid, now: Date.now()});
  const night = nightKey(owner, startedAt);
  const snap = await db
      .doc(`night_threads/${night}/comments/${commentId}`)
      .get();
  if (!snap.exists || snap.data().uid !== targetUid) {
    throw new HttpsError("not-found", "That comment is already gone.");
  }
  const {text, username} = snap.data();
  return {id: commentId, night, uid: targetUid, username, text};
}

/**
 * Records a report against another user's username, photo or a comment they
 * wrote. A comment report carries the night (owner, startedAt) and
 * commentId, and stores a copy of the comment. The logged line feeds a
 * log-based alert that emails the developer.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the reporter
 * @param {{targetUid: string, kind: string}} params.data the payload
 * @return {Promise<{status: string}>} always "reported"
 */
async function reportUser({db, uid, data}) {
  const targetUid = otherUid(data && data.targetUid, uid);
  const kind = data && data.kind;
  if (!REPORT_KINDS.includes(kind)) {
    throw new HttpsError("invalid-argument", "Unknown report kind.");
  }
  if (!(await db.doc(`public_profiles/${targetUid}`).get()).exists) {
    throw new HttpsError("not-found", "That user doesn't exist.");
  }
  const report = {
    reporter: uid,
    target_uid: targetUid,
    kind,
    created_at: Date.now(),
  };
  if (kind === "comment") {
    report.comment = await reportedComment({db, uid, targetUid, data});
  }
  await db.collection("reports").add(report);
  console.error("SOCIAL_REPORT", report);
  return {status: "reported"};
}

/**
 * Stores the caller's APNs token so friend requests can reach them. A device
 * token belongs to one account at a time: any other account still holding it
 * (signed out on this phone) loses it, so its pushes stop landing here.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{token: string, environment: string}} params.data the payload
 * @return {Promise<{status: string}>} always "registered"
 */
async function registerPushToken({db, uid, data}) {
  const {token, environment} = data || {};
  validatePushToken(token, environment);
  assertNotDeleting(await db.doc(`account_deletions/${uid}`).get());
  const holders = await db
      .collection("push_tokens")
      .where("token", "==", token)
      .get();
  const batch = db.batch();
  for (const holder of holders.docs) {
    if (holder.id !== uid) batch.delete(holder.ref);
  }
  batch.set(db.doc(`push_tokens/${uid}`), {
    token,
    environment,
    updated_at: Date.now(),
  });
  await batch.commit();
  return {status: "registered"};
}

/**
 * Builds the notifier sendFriendRequest and respondToFriendRequest call.
 * Users with no stored token are skipped; dead tokens are deleted.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {Function} params.send (environment, token, payload) =>
 *     {status, reason}
 * @return {Function} (toUid, kind, fromUsername) => Promise
 */
function notifyFromPushTokens({db, send}) {
  return async (toUid, kind, fromUsername) => {
    const copy = PUSH_COPY[kind];
    if (!copy) throw new Error(`unknown notification kind ${kind}`);
    const ref = db.doc(`push_tokens/${toUid}`);
    const snap = await ref.get();
    if (!snap.exists) return;
    const {token, environment} = snap.data();
    const result = await send(environment, token, {
      aps: {alert: {body: copy(fromUsername)}, sound: "default"},
      route: PUSH_ROUTE[kind],
      username: fromUsername,
    });
    if (tokenIsDead(result)) await ref.delete();
  };
}

// ---------------------------------------------------------------------------
// People you might know: friends of friends, and contacts on TrackSip
// ---------------------------------------------------------------------------

const SUGGEST_LIMIT = 20;
// Friend lists read per call. Past this the ranking is from a sample, which is
// fine for suggestions and keeps one call to a bounded number of reads.
const SUGGEST_FRIENDS_SCANNED = 50;
const CONTACT_EMAILS_MAX = 2000;
const CONTACT_CALLS_PER_DAY = 5;
const CONTACT_PUSHES_PER_CALL = 30;
const DAY_MS = 86400000;
const NUDGE_SENDERS_KEPT = 50;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * The public card for a profile document.
 * @param {object} doc a public_profiles snapshot
 * @return {object} uid, username, photo_url and avatar_color
 */
function profileCard(doc) {
  return {
    uid: doc.id,
    username: doc.data().username,
    photo_url: doc.data().photo_url || null,
    avatar_color: doc.data().avatar_color,
  };
}

/**
 * Ids in a subcollection, as a set.
 * @param {object} db Firestore
 * @param {string} path collection path
 * @return {Promise<Set<string>>}
 */
async function idsIn(db, path) {
  return new Set((await db.collection(path).get()).docs.map((d) => d.id));
}

/**
 * Friends of the caller's friends, ranked by how many friends they share.
 * Each result names one of those shared friends ("friends with @beto").
 * Nobody the caller blocked, or who blocked the caller, is suggested.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @return {Promise<{results: object[]}>}
 */
async function suggestFriends({db, uid}) {
  const [friends, blocked] = await Promise.all([
    idsIn(db, `friendships/${uid}/friends`),
    idsIn(db, `blocks/${uid}/blocked`),
  ]);
  const scanned = [...friends].slice(0, SUGGEST_FRIENDS_SCANNED);
  const theirFriends = await Promise.all(
      scanned.map((f) => idsIn(db, `friendships/${f}/friends`)),
  );

  const mutual = new Map(); // candidate -> {count, via}
  theirFriends.forEach((set, i) => {
    for (const candidate of set) {
      const excluded = candidate === uid || friends.has(candidate) ||
        blocked.has(candidate);
      if (excluded) continue;
      const entry = mutual.get(candidate) || {count: 0, via: scanned[i]};
      entry.count += 1;
      mutual.set(candidate, entry);
    }
  });

  const ranked = [...mutual.entries()]
      .sort((a, b) => b[1].count - a[1].count || a[0].localeCompare(b[0]))
      .slice(0, SUGGEST_LIMIT * 2)
      .map(([candidate]) => candidate);
  const [profiles, blocks] = await Promise.all([
    Promise.all(ranked.map((c) => db.doc(`public_profiles/${c}`).get())),
    Promise.all(ranked.map((c) => db.doc(`blocks/${c}/blocked/${uid}`).get())),
  ]);
  const visible = profiles
      .filter((p, i) => p.exists && !blocks[i].exists)
      .slice(0, SUGGEST_LIMIT);

  const viaIds = [...new Set(visible.map((p) => mutual.get(p.id).via))];
  const viaNames = new Map(
      (await Promise.all(viaIds.map((v) => db.doc(`public_profiles/${v}`).get())))
          .filter((d) => d.exists)
          .map((d) => [d.id, d.data().username]),
  );

  return {
    results: visible.map((p) => ({
      ...profileCard(p),
      mutual_count: mutual.get(p.id).count,
      mutual_username: viaNames.get(mutual.get(p.id).via) || null,
    })),
  };
}

/**
 * Lowercased, trimmed, de-duplicated emails that look like emails.
 * @param {*} value the raw payload
 * @return {string[]}
 */
function cleanEmails(value) {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Missing contacts.");
  }
  if (value.length > CONTACT_EMAILS_MAX) {
    throw new HttpsError("invalid-argument", "Too many contacts.");
  }
  const emails = new Set();
  for (const raw of value) {
    if (typeof raw !== "string") continue;
    const email = raw.trim().toLowerCase();
    if (email.length <= 254 && EMAIL_PATTERN.test(email)) emails.add(email);
  }
  return [...emails];
}

/**
 * Records that `fromUid` is about to nudge `toUid`, unless toUid was nudged in
 * the last day or has already heard about fromUid.
 * @param {object} db Firestore
 * @param {string} toUid recipient
 * @param {string} fromUid sender
 * @param {number} now clock
 * @return {Promise<boolean>} true when the push should go out
 */
async function claimNudge(db, toUid, fromUid, now) {
  const ref = db.doc(`contact_nudges/${toUid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const senders = snap.exists ? snap.data().senders || [] : [];
    const recent = snap.exists && now - snap.data().last_at < DAY_MS;
    if (recent || senders.includes(fromUid)) return false;
    tx.set(ref, {
      last_at: now,
      senders: [...senders, fromUid].slice(-NUDGE_SENDERS_KEPT),
    });
    return true;
  });
}

/**
 * Finds which of the caller's contacts have TrackSip, by email. Nothing from
 * the contact list is stored or logged: the emails are matched and dropped.
 *
 * Contacts with a Social profile come back as results and are told the caller
 * is on TrackSip; those with an account but no profile are nudged to create
 * one and are never revealed to the caller. Each person gets at most one such
 * push a day, and never twice about the same sender.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{emails: string[]}} params.data the payload
 * @param {Function} params.lookupEmails (emails) => Promise<string[]> uids of
 *     accounts whose verified email is one of these
 * @param {Function} params.notify (toUid, kind, fromUsername) => Promise
 * @param {number} [params.now] clock, for tests
 * @return {Promise<{results: object[]}>}
 */
async function matchContacts({
  db, uid, data, lookupEmails, notify, now = Date.now(),
}) {
  const emails = cleanEmails(data && data.emails);
  const [me, deleting] = await Promise.all([
    db.doc(`public_profiles/${uid}`).get(),
    db.doc(`account_deletions/${uid}`).get(),
  ]);
  assertNotDeleting(deleting);
  if (!me.exists) {
    throw new HttpsError("failed-precondition", "Pick a username first.");
  }

  const limitRef = db.doc(`contact_match_limits/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(limitRef);
    const {window_start: start = 0, count = 0} = snap.exists ? snap.data() : {};
    const fresh = !snap.exists || now - start >= DAY_MS;
    if (!fresh && count >= CONTACT_CALLS_PER_DAY) {
      throw new HttpsError("resource-exhausted",
          "You've checked your contacts a lot today. Try again tomorrow.");
    }
    tx.set(limitRef, fresh ?
      {window_start: now, count: 1} :
      {window_start: start, count: count + 1});
  });
  if (emails.length === 0) return {results: []};

  const [matched, friends, blocked] = await Promise.all([
    lookupEmails(emails),
    idsIn(db, `friendships/${uid}/friends`),
    idsIn(db, `blocks/${uid}/blocked`),
  ]);
  const candidates = [...new Set(matched)]
      .filter((c) => c !== uid && !blocked.has(c));

  const [profiles, blocks] = await Promise.all([
    Promise.all(candidates.map((c) => db.doc(`public_profiles/${c}`).get())),
    Promise.all(candidates.map((c) => db.doc(`blocks/${c}/blocked/${uid}`).get())),
  ]);
  const onSocial = [];
  const noProfile = [];
  candidates.forEach((c, i) => {
    if (blocks[i].exists) return;
    if (profiles[i].exists) {
      if (!friends.has(c)) onSocial.push(profiles[i]);
    } else {
      noProfile.push(c);
    }
  });

  const fromUsername = me.data().username;
  const targets = [
    ...onSocial.map((p) => [p.id, "contact"]),
    ...noProfile.map((c) => [c, "contactNoProfile"]),
  ].slice(0, CONTACT_PUSHES_PER_CALL);
  for (const [toUid, kind] of targets) {
    if (await claimNudge(db, toUid, uid, now)) {
      await notifySafely(notify, toUid, kind, fromUsername);
    }
  }

  return {
    results: onSocial.map((p) => ({...profileCard(p), in_contacts: true})),
  };
}

module.exports = {
  suggestFriends,
  matchContacts,
  assertNotDeleting,
  reportUser,
  registerPushToken,
  notifyFromPushTokens,
  claimUsername,
  searchUsers,
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  removeFriend,
  blockUser,
  unblockUser,
};
