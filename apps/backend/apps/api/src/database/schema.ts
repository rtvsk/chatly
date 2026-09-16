import {
  boolean,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  text,
  timestamp,
  unique,
  uniqueIndex,
  uuid,
  varchar,
} from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

export const chatTypeEnum = pgEnum('chats_type_enum', ['direct', 'group']);

export const friendshipStatusEnum = pgEnum('friendships_status_enum', [
  'pending',
  'accepted',
  'rejected',
]);

export const outboxEventStatusEnum = pgEnum('outbox_event_status_enum', [
  'pending',
  'processing',
  'published',
  'dead',
]);

export const users = pgTable(
  'users',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    login: varchar('login').notNull().unique(),
    email: varchar('email'),
    isVerified: boolean('isVerified').default(false).notNull(),
    passwordHash: varchar('passwordHash').notNull(),
    createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
    updatedAt: timestamp('updatedAt', { mode: 'date' }).defaultNow().notNull(),
  },
  (table) => [
    uniqueIndex('users_email_lower_unique_idx')
      .on(sql`lower(${table.email})`)
      .where(sql`${table.email} is not null`),
  ],
);

export const emailVerificationTokens = pgTable(
  'email_verification_tokens',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    tokenDigest: varchar('tokenDigest').notNull().unique(),
    userId: uuid('userId')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    expiresAt: timestamp('expiresAt', { mode: 'date' }).notNull(),
    createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
    usedAt: timestamp('usedAt', { mode: 'date' }),
  },
  (table) => [
    uniqueIndex('email_verification_tokens_user_created_idx').on(
      table.userId,
      table.createdAt,
    ),
  ],
);

export const outboxEvents = pgTable(
  'outbox_events',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    topic: varchar('topic').notNull(),
    payload: jsonb('payload').$type<Record<string, unknown>>(),
    status: outboxEventStatusEnum('status').default('pending').notNull(),
    attempts: integer('attempts').default(0).notNull(),
    availableAt: timestamp('availableAt', { mode: 'date' })
      .defaultNow()
      .notNull(),
    lockedUntil: timestamp('lockedUntil', { mode: 'date' }),
    expiresAt: timestamp('expiresAt', { mode: 'date' }).notNull(),
    publishedAt: timestamp('publishedAt', { mode: 'date' }),
    lastError: text('lastError'),
    createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
    updatedAt: timestamp('updatedAt', { mode: 'date' }).defaultNow().notNull(),
  },
  (table) => [
    index('outbox_events_dispatch_idx').on(
      table.status,
      table.availableAt,
      table.lockedUntil,
    ),
  ],
);

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

export const avatars = pgTable(
  'avatars',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    userId: uuid('userId')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    objectKey: varchar('objectKey').notNull().unique(),
    originalName: varchar('originalName').notNull(),
    mimeType: varchar('mimeType').notNull(),
    size: integer('size').notNull(),
    isSelected: boolean('isSelected').default(false).notNull(),
    createdAt: timestamp('createdAt', { mode: 'date' }).defaultNow().notNull(),
  },
  (table) => [
    uniqueIndex('avatars_one_selected_per_user_idx')
      .on(table.userId)
      .where(sql`${table.isSelected} = true`),
  ],
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
export type Avatar = typeof avatars.$inferSelect;
