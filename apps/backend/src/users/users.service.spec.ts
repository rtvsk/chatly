import { DatabaseService } from '../database/database.service';
import { UsersService } from './users.service';

describe('UsersService', () => {
  it('does not query the database for logins shorter than three characters', async () => {
    const select = jest.fn();
    const service = new UsersService({
      db: { select },
    } as unknown as DatabaseService);

    await expect(
      service.searchByLogin(' ab ', 'current-user'),
    ).resolves.toEqual([]);
    expect(select).not.toHaveBeenCalled();
  });

  it('returns a limited list of matching public user fields', async () => {
    const users = [
      { id: 'first-user', login: 'alex', avatarId: 'avatar-id' },
      { id: 'second-user', login: 'alexander', avatarId: null },
    ];
    const builder = {
      from: jest.fn().mockReturnThis(),
      leftJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue(users),
    };
    const select = jest.fn().mockReturnValue(builder);
    const service = new UsersService({
      db: { select },
    } as unknown as DatabaseService);

    await expect(
      service.searchByLogin('  Ale  ', 'current-user'),
    ).resolves.toEqual([
      {
        id: 'first-user',
        login: 'alex',
        avatarUrl: '/avatars/avatar-id/file',
      },
      { id: 'second-user', login: 'alexander', avatarUrl: null },
    ]);
    expect(select).toHaveBeenCalledTimes(1);
    expect(builder.leftJoin).toHaveBeenCalledTimes(1);
    expect(builder.where).toHaveBeenCalledTimes(1);
    expect(builder.limit).toHaveBeenCalledWith(20);
  });
});
