UPDATE "chat_participants" AS participant
SET "lastReadMessageId" = chat."lastMessageId"
FROM "chats" AS chat
WHERE participant."chatId" = chat."id"
  AND participant."lastReadMessageId" IS NULL
  AND chat."lastMessageId" IS NOT NULL;
