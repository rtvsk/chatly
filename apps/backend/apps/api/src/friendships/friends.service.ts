import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { and, desc, eq, inArray, or, sql } from 'drizzle-orm';
import { alias } from 'drizzle-orm/pg-core';

import { DatabaseService } from '../database/database.service';
import {
  FriendshipChangedEvent,
  FriendshipRealtimePublisher,
} from '../realtime/friendship-realtime.publisher';
import {
  avatars,
  chatParticipants,
  chats,
  friendships,
  users,
} from '../database/schema';
import { FriendshipStatus } from './enums/friendship-status.enum';

const requester = alias(users, 'requester');
const receiver = alias(users, 'receiver');
const requesterAvatar = alias(avatars, 'requester_avatar');
const receiverAvatar = alias(avatars, 'receiver_avatar');

@Injectable()
export class FriendsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly friendshipRealtimePublisher: FriendshipRealtimePublisher,
  ) {}

  async sendRequest(requesterId: string, receiverId: string) {
    if (requesterId === receiverId) {
      throw new BadRequestException('You cannot add yourself');
    }

    const [receiverUser] = await this.database.db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.id, receiverId))
      .limit(1);

    if (!receiverUser) {
      throw new NotFoundException('User not found');
    }

    const [existing] = await this.database.db
      .select({
        id: friendships.id,
        status: friendships.status,
      })
      .from(friendships)
      .where(
        or(
          and(
            eq(friendships.requesterId, requesterId),
            eq(friendships.receiverId, receiverId),
          ),
          and(
            eq(friendships.requesterId, receiverId),
            eq(friendships.receiverId, requesterId),
          ),
        ),
      )
      .limit(1);

    if (existing?.status === 'rejected') {
      const [friendship] = await this.database.db
        .update(friendships)
        .set({
          requesterId,
          receiverId,
          status: FriendshipStatus.PENDING,
          updatedAt: new Date(),
        })
        .where(eq(friendships.id, existing.id))
        .returning();

      this.publishFriendshipChanged(
        [friendship.requesterId, friendship.receiverId],
        'request_created',
      );
      return friendship;
    }

    if (existing) {
      throw new BadRequestException('Friend request already exists');
    }

    const [friendship] = await this.database.db
      .insert(friendships)
      .values({
        requesterId,
        receiverId,
        status: FriendshipStatus.PENDING,
      })
      .returning();

    this.publishFriendshipChanged(
      [friendship.requesterId, friendship.receiverId],
      'request_created',
    );
    return friendship;
  }

  async acceptRequest(userId: string, friendshipId: string) {
    const [friendship] = await this.database.db
      .update(friendships)
      .set({
        status: FriendshipStatus.ACCEPTED,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(friendships.id, friendshipId),
          eq(friendships.receiverId, userId),
          eq(friendships.status, FriendshipStatus.PENDING),
        ),
      )
      .returning();

    if (!friendship) {
      throw new NotFoundException('Friend request not found');
    }

    this.publishFriendshipChanged(
      [friendship.requesterId, friendship.receiverId],
      'request_accepted',
    );
    return friendship;
  }

  async rejectRequest(userId: string, friendshipId: string) {
    const [friendship] = await this.database.db
      .update(friendships)
      .set({
        status: FriendshipStatus.REJECTED,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(friendships.id, friendshipId),
          eq(friendships.receiverId, userId),
          eq(friendships.status, FriendshipStatus.PENDING),
        ),
      )
      .returning();

    if (!friendship) {
      throw new NotFoundException('Friend request not found');
    }

    this.publishFriendshipChanged(
      [friendship.requesterId, friendship.receiverId],
      'request_rejected',
    );
    return friendship;
  }

  async removeFriend(userId: string, otherUserId: string): Promise<void> {
    await this.database.db.transaction(async (tx) => {
      const [friendship] = await tx
        .delete(friendships)
        .where(
          and(
            eq(friendships.status, FriendshipStatus.ACCEPTED),
            or(
              and(
                eq(friendships.requesterId, userId),
                eq(friendships.receiverId, otherUserId),
              ),
              and(
                eq(friendships.requesterId, otherUserId),
                eq(friendships.receiverId, userId),
              ),
            ),
          ),
        )
        .returning({ id: friendships.id });

      if (!friendship) {
        throw new NotFoundException('Friendship not found');
      }

      const directChats = await tx
        .select({ id: chats.id })
        .from(chats)
        .innerJoin(chatParticipants, eq(chatParticipants.chatId, chats.id))
        .where(eq(chats.type, 'direct'))
        .groupBy(chats.id)
        .having(
          sql`count(*) = 2 and count(*) filter (where ${chatParticipants.userId} in (${userId}, ${otherUserId})) = 2`,
        );

      if (directChats.length > 0) {
        await tx.delete(chats).where(
          inArray(
            chats.id,
            directChats.map((chat) => chat.id),
          ),
        );
      }
    });

    this.publishFriendshipChanged([userId, otherUserId], 'friend_removed');
  }

  async getIncomingRequests(userId: string) {
    const requests = await this.database.db
      .select({
        friendshipId: friendships.id,
        createdAt: friendships.createdAt,
        requester: {
          id: requester.id,
          login: requester.login,
          avatarId: requesterAvatar.id,
        },
      })
      .from(friendships)
      .innerJoin(requester, eq(friendships.requesterId, requester.id))
      .leftJoin(
        requesterAvatar,
        and(
          eq(requesterAvatar.userId, requester.id),
          eq(requesterAvatar.isSelected, true),
        ),
      )
      .where(
        and(
          eq(friendships.receiverId, userId),
          eq(friendships.status, FriendshipStatus.PENDING),
        ),
      )
      .orderBy(desc(friendships.createdAt));

    return requests.map(({ friendshipId, createdAt, requester: user }) => ({
      friendshipId,
      createdAt,
      user: {
        id: user.id,
        login: user.login,
        avatarUrl: user.avatarId ? `/avatars/${user.avatarId}/file` : null,
      },
    }));
  }

  async getFriendshipStatus(userId: string, otherUserId: string) {
    const [friendship] = await this.database.db
      .select({
        id: friendships.id,
        requesterId: friendships.requesterId,
        status: friendships.status,
      })
      .from(friendships)
      .where(
        or(
          and(
            eq(friendships.requesterId, userId),
            eq(friendships.receiverId, otherUserId),
          ),
          and(
            eq(friendships.requesterId, otherUserId),
            eq(friendships.receiverId, userId),
          ),
        ),
      )
      .limit(1);

    if (!friendship || friendship.status === 'rejected') {
      return { status: 'none', friendshipId: null };
    }

    if (friendship.status === 'accepted') {
      return { status: 'friends', friendshipId: friendship.id };
    }

    return {
      status:
        friendship.requesterId === userId
          ? 'outgoing_pending'
          : 'incoming_pending',
      friendshipId: friendship.id,
    };
  }

  async getMyFriends(userId: string) {
    const friendshipRows = await this.database.db
      .select({
        requesterId: friendships.requesterId,
        requester: {
          id: requester.id,
          login: requester.login,
          avatarId: requesterAvatar.id,
        },
        receiver: {
          id: receiver.id,
          login: receiver.login,
          avatarId: receiverAvatar.id,
        },
      })
      .from(friendships)
      .innerJoin(requester, eq(friendships.requesterId, requester.id))
      .innerJoin(receiver, eq(friendships.receiverId, receiver.id))
      .leftJoin(
        requesterAvatar,
        and(
          eq(requesterAvatar.userId, requester.id),
          eq(requesterAvatar.isSelected, true),
        ),
      )
      .leftJoin(
        receiverAvatar,
        and(
          eq(receiverAvatar.userId, receiver.id),
          eq(receiverAvatar.isSelected, true),
        ),
      )
      .where(
        and(
          eq(friendships.status, FriendshipStatus.ACCEPTED),
          or(
            eq(friendships.requesterId, userId),
            eq(friendships.receiverId, userId),
          ),
        ),
      );

    return friendshipRows.map((friendship) => {
      const friend =
        friendship.requesterId === userId
          ? friendship.receiver
          : friendship.requester;

      return {
        id: friend.id,
        login: friend.login,
        avatarUrl: friend.avatarId ? `/avatars/${friend.avatarId}/file` : null,
      };
    });
  }

  async getAcceptedFriendIds(userId: string): Promise<string[]> {
    const friendshipRows = await this.database.db
      .select({
        requesterId: friendships.requesterId,
        receiverId: friendships.receiverId,
      })
      .from(friendships)
      .where(
        and(
          eq(friendships.status, FriendshipStatus.ACCEPTED),
          or(
            eq(friendships.requesterId, userId),
            eq(friendships.receiverId, userId),
          ),
        ),
      );

    return friendshipRows.map((friendship) =>
      friendship.requesterId === userId
        ? friendship.receiverId
        : friendship.requesterId,
    );
  }

  private publishFriendshipChanged(
    participantIds: readonly string[],
    type: FriendshipChangedEvent['type'],
  ): void {
    try {
      this.friendshipRealtimePublisher.publishFriendshipChanged(
        participantIds,
        {
          type,
        },
      );
    } catch {
      // Realtime delivery must not fail an already committed HTTP operation.
    }
  }
}
