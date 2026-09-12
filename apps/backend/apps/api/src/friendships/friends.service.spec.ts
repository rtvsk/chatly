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
});
