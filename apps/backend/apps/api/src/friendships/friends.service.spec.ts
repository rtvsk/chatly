import { DatabaseService } from '../database/database.service';
import { FriendshipStatus } from './enums/friendship-status.enum';
import { FriendsService } from './friends.service';

describe('FriendsService', () => {
  it('returns incoming requests with requester avatars', async () => {
    const createdAt = new Date('2026-09-07T12:00:00.000Z');
    const builder = {
      from: jest.fn().mockReturnThis(),
      innerJoin: jest.fn().mockReturnThis(),
      leftJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockResolvedValue([
        {
          friendshipId: 'friendship-id',
          createdAt,
          requester: {
            id: 'requester-id',
            login: 'alice',
            avatarId: 'avatar-id',
          },
        },
      ]),
    };
    const service = new FriendsService({
      db: { select: jest.fn().mockReturnValue(builder) },
    } as unknown as DatabaseService);

    await expect(service.getIncomingRequests('receiver-id')).resolves.toEqual([
      {
        friendshipId: 'friendship-id',
        createdAt,
        user: {
          id: 'requester-id',
          login: 'alice',
          avatarUrl: '/avatars/avatar-id/file',
        },
      },
    ]);
  });

  it.each([
    [FriendshipStatus.ACCEPTED, 'requester-id', 'friends'],
    [FriendshipStatus.PENDING, 'current-user', 'outgoing_pending'],
    [FriendshipStatus.PENDING, 'requester-id', 'incoming_pending'],
  ])(
    'maps %s relationships to %s',
    async (status, requesterId, expectedStatus) => {
      const builder = {
        from: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        limit: jest
          .fn()
          .mockResolvedValue([{ id: 'friendship-id', requesterId, status }]),
      };
      const service = new FriendsService({
        db: { select: jest.fn().mockReturnValue(builder) },
      } as unknown as DatabaseService);

      await expect(
        service.getFriendshipStatus('current-user', 'other-user'),
      ).resolves.toEqual({
        status: expectedStatus,
        friendshipId: 'friendship-id',
      });
    },
  );

  it('rejects a pending request addressed to the current user', async () => {
    const friendship = { id: 'friendship-id', status: 'rejected' };
    const builder = {
      set: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      returning: jest.fn().mockResolvedValue([friendship]),
    };
    const service = new FriendsService({
      db: { update: jest.fn().mockReturnValue(builder) },
    } as unknown as DatabaseService);

    await expect(
      service.rejectRequest('current-user', 'friendship-id'),
    ).resolves.toEqual(friendship);
    expect(builder.set).toHaveBeenCalledTimes(1);
  });

  it('removes an accepted friendship in either direction and its exact direct chat', async () => {
    const friendshipDelete = {
      where: jest.fn(() => ({
        returning: jest.fn().mockResolvedValue([{ id: 'friendship-id' }]),
      })),
    };
    const directChats = {
      from: jest.fn().mockReturnThis(),
      innerJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      groupBy: jest.fn().mockReturnThis(),
      having: jest.fn().mockResolvedValue([{ id: 'direct-chat-id' }]),
    };
    const chatDelete = { where: jest.fn().mockResolvedValue(undefined) };
    const tx = {
      delete: jest
        .fn()
        .mockReturnValueOnce(friendshipDelete)
        .mockReturnValueOnce(chatDelete),
      select: jest.fn().mockReturnValue(directChats),
    };
    const transaction = jest.fn(async (callback) => callback(tx));
    const service = new FriendsService({
      db: { transaction },
    } as unknown as DatabaseService);

    await expect(
      service.removeFriend('receiver-id', 'requester-id'),
    ).resolves.toBeUndefined();

    expect(transaction).toHaveBeenCalledTimes(1);
    expect(friendshipDelete.where).toHaveBeenCalledTimes(1);
    expect(directChats.having).toHaveBeenCalledTimes(1);
    expect(chatDelete.where).toHaveBeenCalledTimes(1);
  });

  it('preserves group and multi-participant direct chats by deleting only exact direct-chat matches', async () => {
    const friendshipDelete = {
      where: jest.fn(() => ({
        returning: jest.fn().mockResolvedValue([{ id: 'friendship-id' }]),
      })),
    };
    const directChats = {
      from: jest.fn().mockReturnThis(),
      innerJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      groupBy: jest.fn().mockReturnThis(),
      // The query's HAVING clause returns only chats with exactly the two users.
      having: jest.fn().mockResolvedValue([]),
    };
    const chatDelete = { where: jest.fn().mockResolvedValue(undefined) };
    const tx = {
      delete: jest
        .fn()
        .mockReturnValueOnce(friendshipDelete)
        .mockReturnValueOnce(chatDelete),
      select: jest.fn().mockReturnValue(directChats),
    };
    const transaction = jest.fn(async (callback) => callback(tx));
    const service = new FriendsService({
      db: { transaction },
    } as unknown as DatabaseService);

    await service.removeFriend('current-user', 'friend-user');

    expect(directChats.groupBy).toHaveBeenCalledTimes(1);
    expect(directChats.having).toHaveBeenCalledTimes(1);
    expect(chatDelete.where).not.toHaveBeenCalled();
  });

  it('returns 404 and leaves chats untouched when users are not accepted friends', async () => {
    const friendshipDelete = {
      where: jest.fn(() => ({
        returning: jest.fn().mockResolvedValue([]),
      })),
    };
    const tx = {
      delete: jest.fn().mockReturnValue(friendshipDelete),
      select: jest.fn(),
    };
    const transaction = jest.fn(async (callback) => callback(tx));
    const service = new FriendsService({
      db: { transaction },
    } as unknown as DatabaseService);

    await expect(
      service.removeFriend('current-user', 'not-a-friend'),
    ).rejects.toMatchObject({ status: 404 });
    expect(tx.select).not.toHaveBeenCalled();
  });
});
