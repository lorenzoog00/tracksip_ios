const {HttpsError} = require("firebase-functions/v2/https");
const {assertNotDeleting} = require("./social");

// ---------------------------------------------------------------------------
// Night reactions and comments
// ---------------------------------------------------------------------------

const REACTIONS = {
  beer: "🍻",
  fire: "🔥",
  laugh: "😂",
  woozy: "🥴",
  water: "💧",
  heart: "❤️",
};
const REACTION_PUSH_GAP_MS = 15 * 60 * 1000;
const MAX_TRACKED_UIDS = 50;
const MAX_COMMENT_CHARS = 200;
const MAX_COMMENTS_PER_PERSON = 50;
const COMMENT_GAP_MS = 3000;
const LATEST_COMMENTS = 3;
const MAX_MENTION_LOOKUPS = 10;
const LINK_PATTERN = /https?:\/\/|www\./i;

/**
 * The id of a night's thread: the owner and the night's start in ms.
 * Firebase uids contain no underscore, so the key splits unambiguously.
 * @param {string} owner the night owner's uid
 * @param {number} startedAt the shared night's start in ms
 * @return {string} the thread key
 */
function nightKey(owner, startedAt) {
  return `${owner}_${startedAt}`;
}

/**
 * Loads the shared night a caller wants to interact with and checks they may.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.owner the night owner's uid
 * @param {number} params.startedAt the night's start in ms
 * @param {string} params.uid the caller
 * @param {number} params.now current time in ms
 * @return {Promise<{night: object, ownerName: string, viewerName: string}>}
 *     the shared night data and both usernames
 */
async function loadNight({db, owner, startedAt, uid, now}) {
  const nightDoc = await db.doc(`shared_nights/${owner}`).get();
  const night = nightDoc.exists ? nightDoc.data() : null;
  const expiresAt = night && night.expires_at && night.expires_at.toMillis();
  if (!night || night.started_at !== startedAt || !(expiresAt > now)) {
    throw new HttpsError("not-found", "This night is no longer available.");
  }

  if (uid !== owner) {
    const [friend, blockedOwner, blockedViewer] = await Promise.all([
      db.doc(`friendships/${owner}/friends/${uid}`).get(),
      db.doc(`blocks/${uid}/blocked/${owner}`).get(),
      db.doc(`blocks/${owner}/blocked/${uid}`).get(),
    ]);
    if (!friend.exists || blockedOwner.exists || blockedViewer.exists) {
      throw new HttpsError("permission-denied", "You can't see this night.");
    }
  }

  const [viewerProfile, ownerProfile] = await Promise.all([
    db.doc(`public_profiles/${uid}`).get(),
    db.doc(`public_profiles/${owner}`).get(),
  ]);
  if (!viewerProfile.exists) {
    throw new HttpsError("failed-precondition", "Pick a username first.");
  }
  return {
    night,
    ownerName: ownerProfile.exists ? ownerProfile.data().username : "",
    viewerName: viewerProfile.data().username,
  };
}

/**
 * Keeps the newest entries of a list, dropping the oldest.
 * @param {string[]} list uids, newest last
 * @return {string[]} at most MAX_TRACKED_UIDS entries
 */
function capped(list) {
  return list.slice(-MAX_TRACKED_UIDS);
}

/**
 * Sends a push, swallowing failures: the reaction or comment is already
 * committed and is the source of truth.
 * @param {Function} notify injected notifier
 * @param {string} kind the push kind
 * @param {string} toUid recipient
 * @param {object} payload the push payload
 */
async function notifySafely(notify, kind, toUid, payload) {
  try {
    await notify(toUid, kind, payload);
  } catch (error) {
    console.error(`notify ${kind} failed`, error);
  }
}

/**
 * Sets, changes or removes the caller's single reaction on a friend's night.
 * Tapping the reaction already held removes it; null removes it too.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{owner: string, startedAt: number, emoji: ?string}} params.data
 *     the request payload; emoji is a REACTIONS key or null
 * @param {Function} params.notify (toUid, kind, payload) => Promise
 * @param {number} [params.now] current time in ms
 * @return {Promise<{emoji: ?string}>} the caller's reaction afterwards
 */
async function reactToNight({db, uid, data, notify, now = Date.now()}) {
  const {owner, startedAt, emoji} = data || {};
  if (typeof owner !== "string" || owner === "" || owner.includes("/") ||
      !Number.isFinite(startedAt)) {
    throw new HttpsError("invalid-argument", "That night isn't valid.");
  }
  if (emoji != null && !Object.hasOwn(REACTIONS, emoji)) {
    throw new HttpsError("invalid-argument", "That reaction isn't allowed.");
  }
  if (uid === owner) {
    throw new HttpsError("permission-denied",
        "You can't react to your own night.");
  }
  const {night, ownerName, viewerName} =
      await loadNight({db, owner, startedAt, uid, now});

  const threadRef = db.doc(`night_threads/${nightKey(owner, startedAt)}`);
  const reactionRef = threadRef.collection("reactions").doc(uid);
  const outcome = await db.runTransaction(async (tx) => {
    const [deleting, thread, existing] = await Promise.all([
      tx.get(db.doc(`account_deletions/${uid}`)),
      tx.get(threadRef),
      tx.get(reactionRef),
    ]);
    assertNotDeleting(deleting);

    const previous = existing.exists ? existing.data().emoji : null;
    const next = emoji == null || emoji === previous ? null : emoji;
    const summary = thread.exists ? thread.data() : {};
    const counts = {...(summary.reactions || {})};
    if (previous) counts[previous] = Math.max(0, (counts[previous] || 0) - 1);
    if (next) counts[next] = (counts[next] || 0) + 1;

    let reactors = (summary.reactors || []).filter((id) => id !== uid);
    if (next) reactors = capped([...reactors, uid]);

    const pushed = summary.pushed_reactors || [];
    const lastPush = summary.last_reaction_push_at;
    const mayPush = next !== null && !pushed.includes(uid) &&
        (typeof lastPush !== "number" || now - lastPush >= REACTION_PUSH_GAP_MS);
    let waiting = (summary.unpushed_reactors || []).filter((id) => id !== uid);
    const update = {};
    let others = null;
    if (mayPush) {
      others = waiting.length;
      waiting = [];
      update.last_reaction_push_at = now;
      update.pushed_reactors = capped([...pushed, uid]);
    } else if (next !== null && !pushed.includes(uid)) {
      waiting = capped([...waiting, uid]);
    }

    tx.set(threadRef, {
      owner,
      started_at: startedAt,
      expires_at: night.expires_at,
      reactions: counts,
      reactors,
      unpushed_reactors: waiting,
      comment_count: summary.comment_count || 0,
      latest_comments: summary.latest_comments || [],
      ...update,
    }, {merge: true});
    if (next) {
      tx.set(reactionRef, {
        uid,
        username: viewerName,
        emoji: next,
        at: now,
        expires_at: night.expires_at,
      });
    } else {
      tx.delete(reactionRef);
    }
    return {emoji: next, others};
  });

  if (outcome.others !== null) {
    await notifySafely(notify, "reaction", owner, {
      from: viewerName,
      owner,
      ownerName,
      startedAt,
      emoji: REACTIONS[outcome.emoji],
      others: outcome.others,
    });
  }
  return {emoji: outcome.emoji};
}

/**
 * Validates the night reference every comment call carries.
 * @param {object} data the request payload
 * @return {{owner: string, startedAt: number}} the validated reference
 */
function nightRef(data) {
  const {owner, startedAt} = data || {};
  if (typeof owner !== "string" || owner === "" || owner.includes("/") ||
      !Number.isFinite(startedAt)) {
    throw new HttpsError("invalid-argument", "That night isn't valid.");
  }
  return {owner, startedAt};
}

/**
 * Checks and normalises comment text.
 * @param {*} raw the submitted text
 * @return {string} the trimmed text
 */
function cleanCommentText(raw) {
  const text = typeof raw === "string" ? raw.trim() : "";
  if (text === "") {
    throw new HttpsError("invalid-argument", "Write a comment first.");
  }
  if (Array.from(text).length > MAX_COMMENT_CHARS) {
    throw new HttpsError("invalid-argument",
        "Comments are 200 characters at most.");
  }
  if (LINK_PATTERN.test(text)) {
    throw new HttpsError("invalid-argument",
        "Links aren't allowed in comments.");
  }
  return text;
}

/**
 * Whether either of two people has blocked the other.
 * @param {object} db Firestore
 * @param {string} a one uid
 * @param {string} b the other uid
 * @return {Promise<boolean>} true when a block exists in either direction
 */
async function blockedEitherWay(db, a, b) {
  const [ab, ba] = await Promise.all([
    db.doc(`blocks/${a}/blocked/${b}`).get(),
    db.doc(`blocks/${b}/blocked/${a}`).get(),
  ]);
  return ab.exists || ba.exists;
}

/**
 * Whether a person may still see a night: its owner or a current friend.
 * @param {object} db Firestore
 * @param {string} owner the night owner's uid
 * @param {string} uid the person
 * @return {Promise<boolean>} true when they are the owner or a friend
 */
async function isOwnerOrFriend(db, owner, uid) {
  if (uid === owner) return true;
  return (await db.doc(`friendships/${owner}/friends/${uid}`).get()).exists;
}

/**
 * Resolves @usernames in a comment to people who can see the night. The
 * author, strangers, non-friends of the owner and blocked people are dropped.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.text the comment text
 * @param {string} params.owner the night owner's uid
 * @param {string} params.author the author's uid
 * @return {Promise<Array<{uid: string, username: string}>>} deduped mentions
 */
async function resolveMentions({db, text, owner, author}) {
  const names = [...new Set(
      [...text.toLowerCase().matchAll(/@([a-z0-9._]{3,20})/g)]
          .map((match) => match[1]))].slice(0, MAX_MENTION_LOOKUPS);
  const resolved = await Promise.all(names.map(async (username) => {
    const handle = await db.doc(`usernames/${username}`).get();
    if (!handle.exists) return null;
    const uid = handle.data().uid;
    if (uid === author) return null;
    const [visible, blocked] = await Promise.all([
      isOwnerOrFriend(db, owner, uid),
      blockedEitherWay(db, author, uid),
    ]);
    return visible && !blocked ? {uid, username} : null;
  }));
  const seen = new Set();
  return resolved.filter((mention) => {
    if (!mention || seen.has(mention.uid)) return false;
    seen.add(mention.uid);
    return true;
  });
}

/**
 * Adds a comment to a friend's night, updating the thread summary and
 * pushing the owner, earlier commenters and anyone mentioned.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{owner: string, startedAt: number, text: string}} params.data
 *     the request payload
 * @param {Function} params.notify (toUid, kind, payload) => Promise
 * @param {number} [params.now] current time in ms
 * @return {Promise<{id: string, text: string, mentions: Array, at: number}>}
 *     the stored comment
 */
async function addComment({db, uid, data, notify, now = Date.now()}) {
  const {owner, startedAt} = nightRef(data);
  const text = cleanCommentText(data.text);
  const {night, ownerName, viewerName} =
      await loadNight({db, owner, startedAt, uid, now});
  const mentions = await resolveMentions({db, text, owner, author: uid});

  const threadRef = db.doc(`night_threads/${nightKey(owner, startedAt)}`);
  const limitRef = threadRef.collection("limits").doc(uid);
  const commentRef = threadRef.collection("comments").doc();
  const earlier = await db.runTransaction(async (tx) => {
    const [deleting, thread, limit, before] = await Promise.all([
      tx.get(db.doc(`account_deletions/${uid}`)),
      tx.get(threadRef),
      tx.get(limitRef),
      tx.get(threadRef.collection("comments").orderBy("at").select("uid")),
    ]);
    assertNotDeleting(deleting);

    const used = limit.exists ? limit.data() : {count: 0, last_at: null};
    if (used.count >= MAX_COMMENTS_PER_PERSON) {
      throw new HttpsError("resource-exhausted",
          "That's the comment limit for this night.");
    }
    if (typeof used.last_at === "number" &&
        now - used.last_at < COMMENT_GAP_MS) {
      throw new HttpsError("resource-exhausted", "Slow down a little.");
    }

    const summary = thread.exists ? thread.data() : {};
    const latest = [...(summary.latest_comments || []),
      {id: commentRef.id, uid, username: viewerName, text, at: now}]
        .slice(-LATEST_COMMENTS);
    const fresh = thread.exists ? {} : {
      reactions: {}, reactors: [], unpushed_reactors: [],
    };
    tx.set(threadRef, {
      owner,
      started_at: startedAt,
      expires_at: night.expires_at,
      ...fresh,
      comment_count: (summary.comment_count || 0) + 1,
      latest_comments: latest,
    }, {merge: true});
    tx.set(limitRef, {
      count: used.count + 1,
      last_at: now,
      expires_at: night.expires_at,
    });
    tx.set(commentRef, {
      uid,
      username: viewerName,
      text,
      mentions,
      at: now,
      expires_at: night.expires_at,
    });
    return [...new Set(before.docs.map((doc) => doc.data().uid))];
  });

  await pushComment({
    db, notify, owner, ownerName, startedAt, uid, viewerName, text, mentions,
    earlier,
  });
  return {id: commentRef.id, text, mentions, at: now};
}

/**
 * Pushes the people a new comment concerns: mentioned viewers get a
 * mention, otherwise the owner gets a comment and earlier commenters a
 * reply. Nobody gets two pushes and the author gets none. Anyone who can no
 * longer see the night or who is blocked either way with the author is
 * skipped.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {Function} params.notify injected notifier
 * @param {string} params.owner the night owner's uid
 * @param {string} params.ownerName the owner's username
 * @param {number} params.startedAt the night's start in ms
 * @param {string} params.uid the author
 * @param {string} params.viewerName the author's username
 * @param {string} params.text the comment text
 * @param {Array<{uid: string}>} params.mentions the resolved mentions
 * @param {string[]} params.earlier uids of earlier commenters, oldest first
 */
async function pushComment({db, notify, owner, ownerName, startedAt, uid,
  viewerName, text, mentions, earlier}) {
  const kinds = new Map();
  if (uid !== owner) kinds.set(owner, "comment");
  for (const id of earlier) if (!kinds.has(id)) kinds.set(id, "reply");
  for (const {uid: id} of mentions) {
    if (id !== owner) kinds.set(id, "mention");
  }
  kinds.delete(uid);

  const payload = {from: viewerName, owner, ownerName, startedAt, text};
  await Promise.all([...kinds].map(async ([toUid, kind]) => {
    try {
      const [visible, blocked] = await Promise.all([
        isOwnerOrFriend(db, owner, toUid),
        blockedEitherWay(db, uid, toUid),
      ]);
      if (!visible || blocked) return;
    } catch (error) {
      console.error("comment push check failed", error);
      return;
    }
    await notifySafely(notify, kind, toUid, payload);
  }));
}

/**
 * Deletes a comment. Its author and the night's owner may.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{owner: string, startedAt: number, commentId: string}} params.data
 *     the request payload
 * @param {number} [params.now] current time in ms
 * @return {Promise<{status: string}>} "deleted"
 */
async function deleteComment({db, uid, data, now = Date.now()}) {
  const {owner, startedAt} = nightRef(data);
  const commentId = data.commentId;
  if (typeof commentId !== "string" || commentId === "" ||
      commentId.includes("/")) {
    throw new HttpsError("invalid-argument", "That comment isn't valid.");
  }
  await loadNight({db, owner, startedAt, uid, now});

  const threadRef = db.doc(`night_threads/${nightKey(owner, startedAt)}`);
  const commentRef = threadRef.collection("comments").doc(commentId);
  await db.runTransaction(async (tx) => {
    const [deleting, thread, existing, newest] = await Promise.all([
      tx.get(db.doc(`account_deletions/${uid}`)),
      tx.get(threadRef),
      tx.get(commentRef),
      tx.get(threadRef.collection("comments")
          .orderBy("at", "desc").limit(LATEST_COMMENTS + 1)),
    ]);
    assertNotDeleting(deleting);
    if (!existing.exists) {
      throw new HttpsError("not-found", "That comment is already gone.");
    }
    if (existing.data().uid !== uid && uid !== owner) {
      throw new HttpsError("permission-denied",
          "You can't delete this comment.");
    }
    const latest = newest.docs
        .filter((doc) => doc.id !== commentId)
        .slice(0, LATEST_COMMENTS)
        .reverse()
        .map((doc) => {
          const {uid: author, username, text, at} = doc.data();
          return {id: doc.id, uid: author, username, text, at};
        });
    const summary = thread.exists ? thread.data() : {};
    tx.delete(commentRef);
    tx.set(threadRef, {
      comment_count: Math.max(0, (summary.comment_count || 0) - 1),
      latest_comments: latest,
    }, {merge: true});
  });
  return {status: "deleted"};
}

/**
 * Reads a night's reactions and comments, oldest first, leaving out anyone
 * the caller has blocked or who has blocked the caller.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{owner: string, startedAt: number}} params.data the request payload
 * @param {number} [params.now] current time in ms
 * @return {Promise<{reactions: Array, comments: Array}>} the visible thread
 */
async function getNightThread({db, uid, data, now = Date.now()}) {
  const {owner, startedAt} = nightRef(data);
  await loadNight({db, owner, startedAt, uid, now});

  const threadRef = db.doc(`night_threads/${nightKey(owner, startedAt)}`);
  const [reactionDocs, commentDocs] = await Promise.all([
    threadRef.collection("reactions").orderBy("at").limit(500).get(),
    threadRef.collection("comments").orderBy("at").limit(500).get(),
  ]);
  const authors = new Set([...reactionDocs.docs, ...commentDocs.docs]
      .map((doc) => doc.data().uid));
  authors.delete(uid);
  const hidden = new Set();
  await Promise.all([...authors].map(async (author) => {
    if (await blockedEitherWay(db, uid, author)) hidden.add(author);
  }));

  return {
    reactions: reactionDocs.docs
        .filter((doc) => !hidden.has(doc.data().uid))
        .map((doc) => {
          const {uid: id, username, emoji, at} = doc.data();
          return {uid: id, username, emoji, at};
        }),
    comments: commentDocs.docs
        .filter((doc) => !hidden.has(doc.data().uid))
        .map((doc) => {
          const {uid: id, username, text, mentions, at} = doc.data();
          return {id: doc.id, uid: id, username, text, mentions, at};
        }),
  };
}

module.exports = {
  REACTIONS, nightKey, loadNight, reactToNight,
  addComment, deleteComment, getNightThread,
};
