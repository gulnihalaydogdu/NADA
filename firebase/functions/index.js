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
});

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
