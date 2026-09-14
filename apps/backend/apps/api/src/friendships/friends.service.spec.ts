import { DatabaseService } from '../database/database.service';
import { FriendshipRealtimePublisher } from '../realtime/friendship-realtime.publisher';
import { FriendshipStatus } from './enums/friendship-status.enum';
import { FriendsService } from './friends.service';

describe('FriendsService', () => {
  const createFriendshipRealtimePublisher = () =>
    ({
      publishFriendshipChanged: jest.fn(),
    }) as unknown as FriendshipRealtimePublisher;

  const createFriendsService = (
    database: DatabaseService,
    friendshipRealtimePublisher = createFriendshipRealtimePublisher(),
  ) => new FriendsService(database, friendshipRealtimePublisher);

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
    const service = createFriendsService({
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
      const service = createFriendsService({
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

  it('returns the opposite user ID for accepted friendships in either direction', async () => {
    const builder = {
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockResolvedValue([
        { requesterId: 'current-user', receiverId: 'friend-one' },
        { requesterId: 'friend-two', receiverId: 'current-user' },
      ]),
    };
    const service = createFriendsService({
      db: { select: jest.fn().mockReturnValue(builder) },
    } as unknown as DatabaseService);

    await expect(service.getAcceptedFriendIds('current-user')).resolves.toEqual(
      ['friend-one', 'friend-two'],
    );
    expect(builder.where).toHaveBeenCalledTimes(1);
  });

  it('publishes a request_created change after creating a friend request', async () => {
    const receiverQuery = {
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue([{ id: 'receiver-id' }]),
    };
    const existingQuery = {
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue([]),
    };
    const friendship = {
      id: 'friendship-id',
      requesterId: 'requester-id',
      receiverId: 'receiver-id',
      status: FriendshipStatus.PENDING,
    };
    const insert = {
      values: jest.fn().mockReturnThis(),
      returning: jest.fn().mockResolvedValue([friendship]),
    };
    const publisher = createFriendshipRealtimePublisher();
    const service = createFriendsService(
      {
        db: {
          select: jest
            .fn()
            .mockReturnValueOnce(receiverQuery)
            .mockReturnValueOnce(existingQuery),
          insert: jest.fn().mockReturnValue(insert),
        },
      } as unknown as DatabaseService,
      publisher,
    );

    await expect(
      service.sendRequest('requester-id', 'receiver-id'),
    ).resolves.toEqual(friendship);
    expect(publisher.publishFriendshipChanged).toHaveBeenCalledWith(
      ['requester-id', 'receiver-id'],
      { type: 'request_created' },
    );
  });

  it('publishes a request_accepted change only after accepting a request', async () => {
    const friendship = {
      id: 'friendship-id',
      requesterId: 'requester-id',
      receiverId: 'receiver-id',
      status: FriendshipStatus.ACCEPTED,
    };
    const update = {
      set: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      returning: jest.fn().mockResolvedValue([friendship]),
    };
    const publisher = createFriendshipRealtimePublisher();
    const service = createFriendsService(
      {
        db: { update: jest.fn().mockReturnValue(update) },
      } as unknown as DatabaseService,
      publisher,
    );

    await expect(
      service.acceptRequest('receiver-id', 'friendship-id'),
    ).resolves.toEqual(friendship);
    expect(publisher.publishFriendshipChanged).toHaveBeenCalledWith(
      ['requester-id', 'receiver-id'],
      { type: 'request_accepted' },
    );
  });

  it('rejects a pending request addressed to the current user', async () => {
    const friendship = {
      id: 'friendship-id',
      requesterId: 'requester-id',
      receiverId: 'current-user',
      status: 'rejected',
    };
    const builder = {
      set: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      returning: jest.fn().mockResolvedValue([friendship]),
    };
    const publisher = createFriendshipRealtimePublisher();
    const service = createFriendsService(
      {
        db: { update: jest.fn().mockReturnValue(builder) },
      } as unknown as DatabaseService,
      publisher,
    );

    await expect(
      service.rejectRequest('current-user', 'friendship-id'),
    ).resolves.toEqual(friendship);
    expect(builder.set).toHaveBeenCalledTimes(1);
    expect(publisher.publishFriendshipChanged).toHaveBeenCalledWith(
      ['requester-id', 'current-user'],
      { type: 'request_rejected' },
    );
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
    const publisher = createFriendshipRealtimePublisher();
    const service = createFriendsService(
      {
        db: { transaction },
      } as unknown as DatabaseService,
      publisher,
    );

    await expect(
      service.removeFriend('receiver-id', 'requester-id'),
    ).resolves.toBeUndefined();

    expect(transaction).toHaveBeenCalledTimes(1);
    expect(friendshipDelete.where).toHaveBeenCalledTimes(1);
    expect(directChats.having).toHaveBeenCalledTimes(1);
    expect(chatDelete.where).toHaveBeenCalledTimes(1);
    expect(publisher.publishFriendshipChanged).toHaveBeenCalledWith(
      ['receiver-id', 'requester-id'],
      { type: 'friend_removed' },
    );
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
    const service = createFriendsService({
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
    const service = createFriendsService({
      db: { transaction },
    } as unknown as DatabaseService);

    await expect(
      service.removeFriend('current-user', 'not-a-friend'),
    ).rejects.toMatchObject({ status: 404 });
    expect(tx.select).not.toHaveBeenCalled();
  });

  it('does not publish when the friendship transaction fails', async () => {
    const publisher = createFriendshipRealtimePublisher();
    const service = createFriendsService(
      {
        db: {
          transaction: jest
            .fn()
            .mockRejectedValue(new Error('database unavailable')),
        },
      } as unknown as DatabaseService,
      publisher,
    );

    await expect(
      service.removeFriend('current-user', 'friend-user'),
    ).rejects.toThrow('database unavailable');
    expect(publisher.publishFriendshipChanged).not.toHaveBeenCalled();
  });

  it('returns a committed mutation when publishing realtime fails', async () => {
    const friendship = {
      id: 'friendship-id',
      requesterId: 'requester-id',
      receiverId: 'receiver-id',
      status: FriendshipStatus.ACCEPTED,
    };
    const update = {
      set: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      returning: jest.fn().mockResolvedValue([friendship]),
    };
    const publisher = {
      publishFriendshipChanged: jest.fn(() => {
        throw new Error('Socket.IO unavailable');
      }),
    } as unknown as FriendshipRealtimePublisher;
    const service = createFriendsService(
      {
        db: { update: jest.fn().mockReturnValue(update) },
      } as unknown as DatabaseService,
      publisher,
    );

    await expect(
      service.acceptRequest('receiver-id', 'friendship-id'),
    ).resolves.toEqual(friendship);
  });
});
