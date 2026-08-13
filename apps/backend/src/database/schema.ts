import {
  pgEnum,
  pgTable,
  text,
  timestamp,
  unique,
  uuid,
  varchar,
} from 'drizzle-orm/pg-core';

export const chatTypeEnum = pgEnum('chats_type_enum', ['direct', 'group']);

export const friendshipStatusEnum = pgEnum('friendships_status_enum', [
  'pending',
  'accepted',
  'rejected',
]);

export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  login: varchar('login').notNull().unique(),
  passwordHash: varchar('passwordHash').notNull(),
  createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
  updatedAt: timestamp('updatedAt', { mode: 'date' }).defaultNow().notNull(),
});

export const refreshTokens = pgTable(
  'refresh_tokens',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    tokenHash: varchar('tokenHash').notNull(),
    expiresAt: timestamp('expiresAt', { mode: 'date' }).notNull(),
    userId: uuid('userId')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
  },
  (table) => [unique('refresh_tokens_userId_key').on(table.userId)],
);

export const chats = pgTable('chats', {
  id: uuid('id').defaultRandom().primaryKey(),
  type: chatTypeEnum('type').default('direct').notNull(),
  lastMessageId: varchar('lastMessageId'),
  createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
  updatedAt: timestamp('updatedAt', { mode: 'date' }).defaultNow().notNull(),
});

export const chatParticipants = pgTable(
  'chat_participants',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    chatId: uuid('chatId')
      .notNull()
      .references(() => chats.id, { onDelete: 'cascade' }),
    userId: uuid('userId')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    lastReadMessageId: varchar('lastReadMessageId'),
    joinedAt: timestamp('joinedAt', { mode: 'date' }).defaultNow().notNull(),
  },
  (table) => [
    unique('chat_participants_chatId_userId_key').on(
      table.chatId,
      table.userId,
    ),
  ],
);

export const messages = pgTable('messages', {
  id: uuid('id').defaultRandom().primaryKey(),
  chatId: uuid('chatId')
    .notNull()
    .references(() => chats.id, { onDelete: 'cascade' }),
  senderId: uuid('senderId')
    .notNull()
    .references(() => users.id, { onDelete: 'cascade' }),
  text: text('text').notNull(),
  createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
  updatedAt: timestamp('updatedAt', { mode: 'date' }).defaultNow().notNull(),
});

export const friendships = pgTable(
  'friendships',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    requesterId: uuid('requesterId')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    receiverId: uuid('receiverId')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    status: friendshipStatusEnum('status').default('pending').notNull(),
    createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
    updatedAt: timestamp('updatedAt', { mode: 'date' }).defaultNow().notNull(),
  },
  (table) => [
    unique('friendships_requesterId_receiverId_key').on(
      table.requesterId,
      table.receiverId,
    ),
  ],
);

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
