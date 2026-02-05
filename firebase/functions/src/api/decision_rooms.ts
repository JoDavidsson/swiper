import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { nanoid } from "nanoid";
import { requireUserAuth, ensureUserDocument } from "../middleware/require_user_auth";

const db = () => admin.firestore();

/**
 * POST /api/decision-rooms
 * Create a new Decision Room. Requires authentication.
 */
export async function decisionRoomsPost(req: Request, res: Response): Promise<void> {
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required to create a Decision Room" });
    return;
  }

  const { itemIds, title } = req.body;
  if (!itemIds || !Array.isArray(itemIds) || itemIds.length === 0) {
    res.status(400).json({ error: "itemIds array is required" });
    return;
  }

  try {
    // Ensure user document exists
    await ensureUserDocument(user);

    // Verify items exist
    const itemsRef = db().collection("items");
    const itemDocs = await Promise.all(
      itemIds.map((id: string) => itemsRef.doc(id).get())
    );
    const validItemIds = itemDocs.filter(doc => doc.exists).map(doc => doc.id);

    if (validItemIds.length === 0) {
      res.status(400).json({ error: "No valid items found" });
      return;
    }

    // Create the decision room
    const roomId = nanoid(10);
    const now = admin.firestore.FieldValue.serverTimestamp();

    const roomData = {
      id: roomId,
      creatorUserId: user.uid,
      title: title || null,
      itemIds: validItemIds,
      finalistIds: [],
      status: "open",
      participantCount: 1,
      createdAt: now,
      updatedAt: now,
    };

    await db().collection("decisionRooms").doc(roomId).set(roomData);

    // Create items subcollection with initial vote counts
    const itemsSubcollection = db().collection("decisionRooms").doc(roomId).collection("items");
    const batch = db().batch();

    for (const itemId of validItemIds) {
      const itemRef = itemsSubcollection.doc(itemId);
      batch.set(itemRef, {
        id: itemId,
        itemId: itemId,
        addedBy: user.uid,
        isSuggested: false,
        suggestedUrl: null,
        voteCountUp: 0,
        voteCountDown: 0,
        addedAt: now,
      });
    }

    await batch.commit();

    // Build share URL
    const baseUrl = process.env.APP_BASE_URL || "https://swiper.app";
    const shareUrl = `${baseUrl}/r/${roomId}`;

    res.status(201).json({
      id: roomId,
      shareUrl,
    });
  } catch (error) {
    console.error("Error creating decision room:", error);
    res.status(500).json({ error: "Failed to create decision room" });
  }
}

/**
 * GET /api/decision-rooms/:id
 * Get Decision Room details. Public - no auth required.
 */
export async function decisionRoomsGet(req: Request, res: Response, roomId: string): Promise<void> {
  try {
    // Get room document
    const roomDoc = await db().collection("decisionRooms").doc(roomId).get();
    if (!roomDoc.exists) {
      res.status(404).json({ error: "Decision room not found" });
      return;
    }

    const roomData = roomDoc.data()!;

    // Get items with vote counts from subcollection
    const itemsSnapshot = await db()
      .collection("decisionRooms")
      .doc(roomId)
      .collection("items")
      .get();

    const roomItems = itemsSnapshot.docs.map(doc => doc.data());
    const itemIds = roomItems.map(item => item.itemId);

    // Fetch full item details from items collection
    const itemDetailsPromises = itemIds.map((id: string) =>
      db().collection("items").doc(id).get()
    );
    const itemDocs = await Promise.all(itemDetailsPromises);

    // Merge item details with vote counts
    const items = roomItems.map(roomItem => {
      const itemDoc = itemDocs.find(doc => doc.id === roomItem.itemId);
      const itemData = itemDoc?.data() || {};
      return {
        id: roomItem.itemId,
        title: itemData.title || "Unknown",
        priceSek: itemData.priceSek,
        images: itemData.images || [],
        retailer: itemData.retailer,
        url: itemData.url,
        voteCountUp: roomItem.voteCountUp || 0,
        voteCountDown: roomItem.voteCountDown || 0,
        isSuggested: roomItem.isSuggested || false,
        addedBy: roomItem.addedBy,
      };
    });

    res.json({
      id: roomId,
      title: roomData.title,
      status: roomData.status,
      items,
      finalistIds: roomData.finalistIds || [],
      creatorUserId: roomData.creatorUserId,
      participantCount: roomData.participantCount || 1,
      createdAt: roomData.createdAt?.toDate?.()?.toISOString() || null,
    });
  } catch (error) {
    console.error("Error getting decision room:", error);
    res.status(500).json({ error: "Failed to get decision room" });
  }
}

/**
 * POST /api/decision-rooms/:id/vote
 * Vote on an item. Requires authentication.
 */
export async function decisionRoomsVotePost(req: Request, res: Response, roomId: string): Promise<void> {
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required to vote" });
    return;
  }

  const { itemId, vote } = req.body;
  if (!itemId || !vote || !["up", "down"].includes(vote)) {
    res.status(400).json({ error: "itemId and vote (up/down) are required" });
    return;
  }

  try {
    // Verify room exists
    const roomRef = db().collection("decisionRooms").doc(roomId);
    const roomDoc = await roomRef.get();
    if (!roomDoc.exists) {
      res.status(404).json({ error: "Decision room not found" });
      return;
    }

    // Check if item is in the room
    const itemRef = roomRef.collection("items").doc(itemId);
    const itemDoc = await itemRef.get();
    if (!itemDoc.exists) {
      res.status(404).json({ error: "Item not found in this room" });
      return;
    }

    // Check for existing vote
    const existingVoteQuery = await db()
      .collection("votes")
      .where("roomId", "==", roomId)
      .where("itemId", "==", itemId)
      .where("userId", "==", user.uid)
      .limit(1)
      .get();

    const existingVote = existingVoteQuery.docs[0];
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Transaction to update vote counts atomically
    await db().runTransaction(async (transaction) => {
      const currentItemDoc = await transaction.get(itemRef);
      const currentData = currentItemDoc.data() || {};
      let voteCountUp = currentData.voteCountUp || 0;
      let voteCountDown = currentData.voteCountDown || 0;

      if (existingVote) {
        const oldVote = existingVote.data().vote;
        if (oldVote === vote) {
          // Same vote, do nothing
          return;
        }

        // Update vote counts
        if (oldVote === "up") voteCountUp--;
        else voteCountDown--;

        if (vote === "up") voteCountUp++;
        else voteCountDown++;

        // Update existing vote
        transaction.update(existingVote.ref, { vote, updatedAt: now });
      } else {
        // New vote
        if (vote === "up") voteCountUp++;
        else voteCountDown++;

        // Create vote document
        const voteRef = db().collection("votes").doc(nanoid());
        transaction.set(voteRef, {
          id: voteRef.id,
          roomId,
          itemId,
          userId: user.uid,
          vote,
          createdAt: now,
        });

        // Update participant count (first-time voter)
        const roomData = (await transaction.get(roomRef)).data() || {};
        const currentParticipants = new Set(roomData.participants || [roomData.creatorUserId]);
        if (!currentParticipants.has(user.uid)) {
          currentParticipants.add(user.uid);
          transaction.update(roomRef, {
            participantCount: currentParticipants.size,
            participants: Array.from(currentParticipants),
            updatedAt: now,
          });
        }
      }

      // Update item vote counts
      transaction.update(itemRef, {
        voteCountUp,
        voteCountDown,
      });
    });

    // Get updated counts
    const updatedItemDoc = await itemRef.get();
    const updatedData = updatedItemDoc.data() || {};

    res.json({
      success: true,
      voteCountUp: updatedData.voteCountUp || 0,
      voteCountDown: updatedData.voteCountDown || 0,
    });
  } catch (error) {
    console.error("Error voting:", error);
    res.status(500).json({ error: "Failed to record vote" });
  }
}

/**
 * POST /api/decision-rooms/:id/comment
 * Add a comment. Requires authentication.
 */
export async function decisionRoomsCommentPost(req: Request, res: Response, roomId: string): Promise<void> {
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required to comment" });
    return;
  }

  const { text, itemId } = req.body;
  if (!text || typeof text !== "string" || text.trim().length === 0) {
    res.status(400).json({ error: "Comment text is required" });
    return;
  }

  try {
    // Verify room exists
    const roomRef = db().collection("decisionRooms").doc(roomId);
    const roomDoc = await roomRef.get();
    if (!roomDoc.exists) {
      res.status(404).json({ error: "Decision room not found" });
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const commentId = nanoid();

    await db().collection("comments").doc(commentId).set({
      id: commentId,
      roomId,
      itemId: itemId || null,
      userId: user.uid,
      text: text.trim(),
      createdAt: now,
    });

    // Update room
    await roomRef.update({ updatedAt: now });

    res.status(201).json({
      id: commentId,
      createdAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error("Error adding comment:", error);
    res.status(500).json({ error: "Failed to add comment" });
  }
}

/**
 * GET /api/decision-rooms/:id/comments
 * Get comments for a room. Public.
 */
export async function decisionRoomsCommentsGet(req: Request, res: Response, roomId: string): Promise<void> {
  try {
    // Verify room exists
    const roomDoc = await db().collection("decisionRooms").doc(roomId).get();
    if (!roomDoc.exists) {
      res.status(404).json({ error: "Decision room not found" });
      return;
    }

    // Get comments
    const commentsSnapshot = await db()
      .collection("comments")
      .where("roomId", "==", roomId)
      .orderBy("createdAt", "desc")
      .limit(100)
      .get();

    // Get user info for each comment
    const userIds = new Set(commentsSnapshot.docs.map(doc => doc.data().userId));
    const userDocs = await Promise.all(
      Array.from(userIds).map(uid => db().collection("users").doc(uid).get())
    );
    const userMap = new Map(userDocs.filter(doc => doc.exists).map(doc => [doc.id, doc.data()]));

    const comments = commentsSnapshot.docs.map(doc => {
      const data = doc.data();
      const userData = userMap.get(data.userId) || {};
      return {
        id: data.id,
        text: data.text,
        userId: data.userId,
        displayName: userData.displayName || "Anonymous",
        photoUrl: userData.photoUrl || null,
        itemId: data.itemId,
        createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
      };
    });

    res.json({ comments });
  } catch (error) {
    console.error("Error getting comments:", error);
    res.status(500).json({ error: "Failed to get comments" });
  }
}

/**
 * POST /api/decision-rooms/:id/suggest
 * Suggest an alternative item. Requires authentication.
 */
export async function decisionRoomsSuggestPost(req: Request, res: Response, roomId: string): Promise<void> {
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required to suggest alternatives" });
    return;
  }

  const { url } = req.body;
  if (!url || typeof url !== "string") {
    res.status(400).json({ error: "URL is required" });
    return;
  }

  try {
    // Verify room exists
    const roomRef = db().collection("decisionRooms").doc(roomId);
    const roomDoc = await roomRef.get();
    if (!roomDoc.exists) {
      res.status(404).json({ error: "Decision room not found" });
      return;
    }

    const roomData = roomDoc.data()!;
    if (roomData.status !== "open") {
      res.status(400).json({ error: "Cannot suggest items in a finalized room" });
      return;
    }

    // For now, create a placeholder item - in a real implementation,
    // we'd extract product data from the URL
    const suggestedItemId = nanoid(10);
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Add to room's items subcollection
    await roomRef.collection("items").doc(suggestedItemId).set({
      id: suggestedItemId,
      itemId: suggestedItemId,
      addedBy: user.uid,
      isSuggested: true,
      suggestedUrl: url,
      voteCountUp: 0,
      voteCountDown: 0,
      addedAt: now,
    });

    // Create a minimal item document (placeholder)
    await db().collection("items").doc(suggestedItemId).set({
      id: suggestedItemId,
      sourceId: "suggested",
      url: url,
      title: "Suggested item",
      priceSek: 0,
      images: [],
      retailer: "external",
      active: false, // Don't show in regular deck
      styleTags: [],
      createdAt: now,
      updatedAt: now,
      ingestedAt: now,
    });

    // Update room
    await roomRef.update({
      itemIds: admin.firestore.FieldValue.arrayUnion(suggestedItemId),
      updatedAt: now,
    });

    res.status(201).json({
      success: true,
      itemId: suggestedItemId,
    });
  } catch (error) {
    console.error("Error suggesting item:", error);
    res.status(500).json({ error: "Failed to suggest item" });
  }
}

/**
 * POST /api/decision-rooms/:id/finalists
 * Set finalists. Requires authentication and creator permission.
 */
export async function decisionRoomsFinalistsPost(req: Request, res: Response, roomId: string): Promise<void> {
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const { finalistIds } = req.body;
  if (!finalistIds || !Array.isArray(finalistIds) || finalistIds.length !== 2) {
    res.status(400).json({ error: "Exactly 2 finalistIds are required" });
    return;
  }

  try {
    // Verify room exists and user is creator
    const roomRef = db().collection("decisionRooms").doc(roomId);
    const roomDoc = await roomRef.get();
    if (!roomDoc.exists) {
      res.status(404).json({ error: "Decision room not found" });
      return;
    }

    const roomData = roomDoc.data()!;
    if (roomData.creatorUserId !== user.uid) {
      res.status(403).json({ error: "Only the room creator can set finalists" });
      return;
    }

    // Verify finalists are in the room
    const itemsSnapshot = await roomRef.collection("items").get();
    const roomItemIds = itemsSnapshot.docs.map(doc => doc.id);
    const validFinalists = finalistIds.every((id: string) => roomItemIds.includes(id));
    if (!validFinalists) {
      res.status(400).json({ error: "Invalid finalist IDs" });
      return;
    }

    // Update room
    await roomRef.update({
      finalistIds,
      status: "finalists",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      success: true,
      status: "finalists",
    });
  } catch (error) {
    console.error("Error setting finalists:", error);
    res.status(500).json({ error: "Failed to set finalists" });
  }
}
