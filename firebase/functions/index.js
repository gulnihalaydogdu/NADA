const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// New incoming like — skip if this like completes a match (match push covers it).
exports.onLikeCreated = onDocumentCreated("likes/{likeId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const fromUserId = data.fromUserId;
  const toUserId = data.toUserId;
  if (!fromUserId || !toUserId || fromUserId === toUserId) return;

  const reverse = await db.collection("likes")
    .where("fromUserId", "==", toUserId)
    .where("toUserId", "==", fromUserId)
    .limit(1)
    .get();
  if (!reverse.empty) {
    if (!(await isBlocked(fromUserId, toUserId))) {
      await ensureMatch(fromUserId, toUserId);
    }
    return;
  }

  const prefs = await db.doc(`preferences/${toUserId}`).get();
  if (prefs.exists && prefs.get("notifyOnLikes") === false) {
    return;
  }

  const name = await displayName(fromUserId);
  await sendToUser(toUserId, {
    title: "New click",
    body: `${name} clicked you`,
    data: {
      type: "like",
      fromUserId: String(fromUserId)
    }
  });
});

// Mutual match — notify both people.
exports.onMatchCreated = onDocumentCreated("matches/{matchId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const userAId = data.userAId;
  const userBId = data.userBId;
  if (!userAId || !userBId) return;

  const matchId = event.params.matchId;
  const [nameA, nameB] = await Promise.all([
    displayName(userAId),
    displayName(userBId)
  ]);

  await Promise.all([
    sendToUser(userAId, {
      title: "You're mutuals",
      body: `You and ${nameB} clicked`,
      data: { type: "match", matchId: String(matchId) }
    }),
    sendToUser(userBId, {
      title: "You're mutuals",
      body: `You and ${nameA} clicked`,
      data: { type: "match", matchId: String(matchId) }
    })
  ]);

  await seedOpeningMessages(matchId, userAId, userBId);
});

// New chat message — notify the other participant (W5-02).
exports.onMessageCreated = onDocumentCreated(
  "matches/{matchId}/messages/{messageId}",
  async (event) => {
    const messageId = event.params.messageId;
    if (typeof messageId === "string" && messageId.startsWith("opening_")) {
      return;
    }

    const data = event.data?.data();
    if (!data) return;

    const senderId = data.senderId;
    const body = typeof data.body === "string" ? data.body : "";
    if (!senderId || !body.trim()) return;

    const matchId = event.params.matchId;
    const matchSnap = await db.doc(`matches/${matchId}`).get();
    if (!matchSnap.exists || matchSnap.get("unmatchedAt")) return;

    const userIds = matchSnap.get("userIds");
    if (!Array.isArray(userIds) || !userIds.includes(senderId)) return;
    const recipientId = userIds.find((id) => id && id !== senderId);
    if (!recipientId) return;

    if (await isBlocked(senderId, recipientId)) return;

    const prefs = await db.doc(`preferences/${recipientId}`).get();
    if (prefs.exists && prefs.get("notifyOnMessages") === false) {
      return;
    }

    const name = await displayName(senderId);
    await sendToUser(recipientId, {
      title: name,
      body: previewMessage(body),
      data: {
        type: "message",
        matchId: String(matchId),
        senderId: String(senderId)
      }
    });
  }
);

function previewMessage(body) {
  const oneLine = String(body).replace(/\s+/g, " ").trim();
  if (!oneLine) return "New message";
  if (oneLine.length <= 80) return oneLine;
  return `${oneLine.slice(0, 79)}…`;
}

async function displayName(userId) {
  const snap = await db.doc(`users/${userId}`).get();
  const name = snap.get("displayName");
  if (typeof name === "string" && name.trim()) return name.trim();
  return "Someone";
}

async function isBlocked(userA, userB) {
  const [ab, ba] = await Promise.all([
    db.doc(`blocks/${userA}_${userB}`).get(),
    db.doc(`blocks/${userB}_${userA}`).get()
  ]);
  return ab.exists || ba.exists;
}

async function seedOpeningMessages(matchId, userAId, userBId) {
  const [ab, ba] = await Promise.all([
    db.collection("likes")
      .where("fromUserId", "==", userAId)
      .where("toUserId", "==", userBId)
      .get(),
    db.collection("likes")
      .where("fromUserId", "==", userBId)
      .where("toUserId", "==", userAId)
      .get()
  ]);

  for (const doc of [...ab.docs, ...ba.docs]) {
    const comment = doc.get("comment");
    if (typeof comment !== "string" || !comment.trim()) continue;
    const senderId = doc.get("fromUserId");
    if (typeof senderId !== "string" || !senderId) continue;

    const body = comment.trim().slice(0, 1000);
    const createdAt = doc.get("createdAt") || FieldValue.serverTimestamp();
    const ref = db.doc(`matches/${matchId}/messages/opening_${doc.id}`);
    try {
      await ref.create({ senderId, body, createdAt });
    } catch (error) {
      if (error.code !== 6 && error.code !== "already-exists") {
        throw error;
      }
    }
  }
}

async function ensureMatch(fromUserId, toUserId) {
  const ids = [fromUserId, toUserId].slice().sort();
  const matchId = `${ids[0]}_${ids[1]}`;
  const ref = db.doc(`matches/${matchId}`);
  try {
    await ref.create({
      userAId: ids[0],
      userBId: ids[1],
      userIds: ids,
      createdAt: FieldValue.serverTimestamp()
    });
  } catch (error) {
    if (error.code !== 6 && error.code !== "already-exists") {
      throw error;
    }
  }
}

async function sendToUser(userId, { title, body, data }) {
  const tokensSnap = await db.collection("users").doc(userId)
    .collection("deviceTokens")
    .get();
  const tokens = tokensSnap.docs
    .map((doc) => doc.get("fcmToken"))
    .filter((token) => typeof token === "string" && token.length > 0);

  if (tokens.length === 0) {
    logger.info("No device tokens", { userId });
    return;
  }

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    apns: {
      payload: {
        aps: { sound: "default" }
      }
    }
  });

  logger.info("FCM send", {
    userId,
    success: response.successCount,
    failure: response.failureCount
  });
}
