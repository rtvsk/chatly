import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { alias } from 'drizzle-orm/pg-core';
import { and, asc, desc, eq, gt, ne, or, sql } from 'drizzle-orm';

import { DatabaseService } from '../database/database.service';
import {
  avatars,
  chatParticipants,
  chats,
  friendships,
  messages,
  users,
} from '../database/schema';
import { FriendshipStatus } from '../friendships/enums/friendship-status.enum';
import { ChatsGateway } from './chats.gateway';

export type ChatMessage = {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  createdAt: Date;
  updatedAt: Date;
};

export type ChatSummary = {
  id: string;
  type: 'direct';
  peer: {
    id: string;
    login: string;
    avatarUrl: string | null;
  };
  lastMessage: ChatMessage | null;
  createdAt: Date;
  updatedAt: Date;
};

type ChatSummaryRow = {
  id: string;
  peerId: string;
  peerLogin: string;
  peerAvatarId: string | null;
  lastMessageId: string | null;
  lastMessageChatId: string | null;
  lastMessageSenderId: string | null;
  lastMessageText: string | null;
  lastMessageCreatedAt: Date | null;
  lastMessageUpdatedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

const currentParticipant = alias(chatParticipants, 'current_chat_participant');
const peerParticipant = alias(chatParticipants, 'peer_chat_participant');
const peerUser = alias(users, 'chat_peer');
const peerAvatar = alias(avatars, 'chat_peer_avatar');

@Injectable()
export class ChatsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly chatsGateway: ChatsGateway,
  ) {}

  async getMyChats(userId: string): Promise<ChatSummary[]> {
    const rows = await this.database.db
      .select({
        id: chats.id,
        peerId: peerUser.id,
        peerLogin: peerUser.login,
        peerAvatarId: peerAvatar.id,
        lastMessageId: messages.id,
        lastMessageChatId: messages.chatId,
        lastMessageSenderId: messages.senderId,
        lastMessageText: messages.text,
        lastMessageCreatedAt: messages.createdAt,
        lastMessageUpdatedAt: messages.updatedAt,
        createdAt: chats.createdAt,
        updatedAt: chats.updatedAt,
      })
      .from(chats)
      .innerJoin(
        currentParticipant,
        and(
          eq(currentParticipant.chatId, chats.id),
          eq(currentParticipant.userId, userId),
        ),
      )
      .innerJoin(
        peerParticipant,
        and(
          eq(peerParticipant.chatId, chats.id),
          ne(peerParticipant.userId, userId),
        ),
      )
      .innerJoin(peerUser, eq(peerParticipant.userId, peerUser.id))
      .leftJoin(
        peerAvatar,
        and(
          eq(peerAvatar.userId, peerUser.id),
          eq(peerAvatar.isSelected, true),
        ),
      )
      .leftJoin(
        messages,
        sql`${chats.lastMessageId} = cast(${messages.id} as text)`,
      )
      .where(eq(chats.type, 'direct'))
      .orderBy(desc(chats.updatedAt));

    return rows.map((row) => this.toChatSummary(row));
  }

  async getDirectChat(
    userId: string,
    peerId: string,
  ): Promise<ChatSummary | null> {
    await this.assertDirectChatAllowed(userId, peerId);

    const chatId = await this.findDirectChatId(
      this.database.db,
      userId,
      peerId,
    );
    if (!chatId) {
      return null;
    }

    return this.getChatSummary(this.database.db, chatId, userId);
  }

  async getOrCreateDirectChat(
    userId: string,
    peerId: string,
  ): Promise<ChatSummary> {
    this.assertNotSelf(userId, peerId);
    await this.assertUserExists(peerId);

    return this.database.db.transaction(async (tx) => {
      const [friendship] = await tx
        .select({ id: friendships.id })
        .from(friendships)
        .where(
          and(
            eq(friendships.status, FriendshipStatus.ACCEPTED),
            or(
              and(
                eq(friendships.requesterId, userId),
                eq(friendships.receiverId, peerId),
              ),
              and(
                eq(friendships.requesterId, peerId),
                eq(friendships.receiverId, userId),
              ),
            ),
          ),
        )
        .for('update')
        .limit(1);

      if (!friendship) {
        throw new ForbiddenException('Users are not friends');
      }

      const existingChatId = await this.findDirectChatId(tx, userId, peerId);
      if (existingChatId) {
        return this.getChatSummary(tx, existingChatId, userId);
      }

      const [chat] = await tx
        .insert(chats)
        .values({ type: 'direct' })
        .returning({ id: chats.id });

      await tx.insert(chatParticipants).values([
        { chatId: chat.id, userId },
        { chatId: chat.id, userId: peerId },
      ]);

      return this.getChatSummary(tx, chat.id, userId);
    });
  }

  async getMessages(
    userId: string,
    chatId: string,
    afterMessageId?: string,
  ): Promise<ChatMessage[]> {
    await this.assertParticipant(this.database.db, userId, chatId);

    let afterMessage: Pick<ChatMessage, 'id' | 'createdAt'> | undefined;
    if (afterMessageId) {
      const [message] = await this.database.db
        .select({ id: messages.id, createdAt: messages.createdAt })
        .from(messages)
        .where(
          and(eq(messages.id, afterMessageId), eq(messages.chatId, chatId)),
        )
        .limit(1);

      if (!message) {
        throw new NotFoundException('Message not found');
      }

      afterMessage = message;
    }

    return this.database.db
      .select({
        id: messages.id,
        chatId: messages.chatId,
        senderId: messages.senderId,
        text: messages.text,
        createdAt: messages.createdAt,
        updatedAt: messages.updatedAt,
      })
      .from(messages)
      .where(
        afterMessage
          ? and(
              eq(messages.chatId, chatId),
              or(
                gt(messages.createdAt, afterMessage.createdAt),
                and(
                  eq(messages.createdAt, afterMessage.createdAt),
                  gt(messages.id, afterMessage.id),
                ),
              ),
            )
          : eq(messages.chatId, chatId),
      )
      .orderBy(asc(messages.createdAt), asc(messages.id));
  }

  async sendMessage(
    userId: string,
    chatId: string,
    text: unknown,
  ): Promise<ChatMessage> {
    if (typeof text !== 'string') {
      throw new BadRequestException('Message text is required');
    }

    const trimmedText = text.trim();
    if (!trimmedText || trimmedText.length > 4000) {
      throw new BadRequestException(
        'Message text must be between 1 and 4000 characters',
      );
    }

    const { message, participantIds } = await this.database.db.transaction(
      async (tx) => {
        await this.assertParticipant(tx, userId, chatId, true);

        const [message] = await tx
          .insert(messages)
          .values({ chatId, senderId: userId, text: trimmedText })
          .returning({
            id: messages.id,
            chatId: messages.chatId,
            senderId: messages.senderId,
            text: messages.text,
            createdAt: messages.createdAt,
            updatedAt: messages.updatedAt,
          });

        await tx
          .update(chats)
          .set({ lastMessageId: message.id, updatedAt: new Date() })
          .where(eq(chats.id, chatId));

        const participants = await tx
          .select({ userId: chatParticipants.userId })
          .from(chatParticipants)
          .where(eq(chatParticipants.chatId, chatId));

        return {
          message,
          participantIds: participants.map((participant) => participant.userId),
        };
      },
    );
    this.chatsGateway.publishMessageCreated(participantIds, message);

    return message;
  }

  private assertNotSelf(userId: string, peerId: string): void {
    if (userId === peerId) {
      throw new BadRequestException('You cannot create a chat with yourself');
    }
  }

  private async assertDirectChatAllowed(
    userId: string,
    peerId: string,
  ): Promise<void> {
    this.assertNotSelf(userId, peerId);
    await this.assertUserExists(peerId);

    const [friendship] = await this.database.db
      .select({ id: friendships.id })
      .from(friendships)
      .where(
        and(
          eq(friendships.status, FriendshipStatus.ACCEPTED),
          or(
            and(
              eq(friendships.requesterId, userId),
              eq(friendships.receiverId, peerId),
            ),
            and(
              eq(friendships.requesterId, peerId),
              eq(friendships.receiverId, userId),
            ),
          ),
        ),
      )
      .limit(1);

    if (!friendship) {
      throw new ForbiddenException('Users are not friends');
    }
  }

  private async assertUserExists(userId: string): Promise<void> {
    const [user] = await this.database.db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    if (!user) {
      throw new NotFoundException('User not found');
    }
  }

  private async findDirectChatId(
    db: Pick<DatabaseService['db'], 'select'>,
    userId: string,
    peerId: string,
  ): Promise<string | null> {
    const directChats = await db
      .select({ id: chats.id })
      .from(chats)
      .innerJoin(chatParticipants, eq(chatParticipants.chatId, chats.id))
      .where(eq(chats.type, 'direct'))
      .groupBy(chats.id)
      .having(
        sql`count(*) = 2 and count(*) filter (where ${chatParticipants.userId} in (${userId}, ${peerId})) = 2`,
      );

    return directChats[0]?.id ?? null;
  }

  private async getChatSummary(
    db: Pick<DatabaseService['db'], 'select'>,
    chatId: string,
    userId: string,
  ): Promise<ChatSummary> {
    const [row] = await db
      .select({
        id: chats.id,
        peerId: peerUser.id,
        peerLogin: peerUser.login,
        peerAvatarId: peerAvatar.id,
        lastMessageId: messages.id,
        lastMessageChatId: messages.chatId,
        lastMessageSenderId: messages.senderId,
        lastMessageText: messages.text,
        lastMessageCreatedAt: messages.createdAt,
        lastMessageUpdatedAt: messages.updatedAt,
        createdAt: chats.createdAt,
        updatedAt: chats.updatedAt,
      })
      .from(chats)
      .innerJoin(
        currentParticipant,
        and(
          eq(currentParticipant.chatId, chats.id),
          eq(currentParticipant.userId, userId),
        ),
      )
      .innerJoin(
        peerParticipant,
        and(
          eq(peerParticipant.chatId, chats.id),
          ne(peerParticipant.userId, userId),
        ),
      )
      .innerJoin(peerUser, eq(peerParticipant.userId, peerUser.id))
      .leftJoin(
        peerAvatar,
        and(
          eq(peerAvatar.userId, peerUser.id),
          eq(peerAvatar.isSelected, true),
        ),
      )
      .leftJoin(
        messages,
        sql`${chats.lastMessageId} = cast(${messages.id} as text)`,
      )
      .where(and(eq(chats.id, chatId), eq(chats.type, 'direct')))
      .limit(1);

    if (!row) {
      throw new NotFoundException('Chat not found');
    }

    return this.toChatSummary(row);
  }

  private async assertParticipant(
    db: Pick<DatabaseService['db'], 'select'>,
    userId: string,
    chatId: string,
    lock = false,
  ): Promise<void> {
    const query = db
      .select({ id: chats.id })
      .from(chats)
      .innerJoin(
        chatParticipants,
        and(
          eq(chatParticipants.chatId, chats.id),
          eq(chatParticipants.userId, userId),
        ),
      )
      .where(eq(chats.id, chatId));

    const [chat] = await (lock ? query.for('update') : query).limit(1);
    if (!chat) {
      throw new NotFoundException('Chat not found');
    }
  }

  private toChatSummary(row: ChatSummaryRow): ChatSummary {
    return {
      id: row.id,
      type: 'direct',
      peer: {
        id: row.peerId,
        login: row.peerLogin,
        avatarUrl: row.peerAvatarId
          ? `/avatars/${row.peerAvatarId}/file`
          : null,
      },
      lastMessage: row.lastMessageId
        ? {
            id: row.lastMessageId,
            chatId: row.lastMessageChatId!,
            senderId: row.lastMessageSenderId!,
            text: row.lastMessageText!,
            createdAt: row.lastMessageCreatedAt!,
            updatedAt: row.lastMessageUpdatedAt!,
          }
        : null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }
}
