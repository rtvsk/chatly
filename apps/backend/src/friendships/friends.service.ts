import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { and, eq, or } from 'drizzle-orm';
import { alias } from 'drizzle-orm/pg-core';

import { DatabaseService } from '../database/database.service';
import { friendships, users } from '../database/schema';
import { FriendshipStatus } from './enums/friendship-status.enum';

const requester = alias(users, 'requester');
const receiver = alias(users, 'receiver');

@Injectable()
export class FriendsService {
  constructor(private readonly database: DatabaseService) {}

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
      .select({ id: friendships.id })
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

    return friendship;
  }

  async getMyFriends(userId: string) {
    const friendshipRows = await this.database.db
      .select({
        requesterId: friendships.requesterId,
        requester: {
          id: requester.id,
          login: requester.login,
        },
        receiver: {
          id: receiver.id,
          login: receiver.login,
        },
      })
      .from(friendships)
      .innerJoin(requester, eq(friendships.requesterId, requester.id))
      .innerJoin(receiver, eq(friendships.receiverId, receiver.id))
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
      };
    });
  }
}
