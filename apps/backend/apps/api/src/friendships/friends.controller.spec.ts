import { HttpStatus } from '@nestjs/common';
import {
  GUARDS_METADATA,
  HTTP_CODE_METADATA,
  PATH_METADATA,
} from '@nestjs/common/constants';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { FriendsController } from './friends.controller';
import { FriendsService } from './friends.service';

describe('FriendsController', () => {
  it('protects DELETE /friends/:userId and removes the current user friendship', async () => {
    const removeFriend = jest.fn().mockResolvedValue(undefined);
    const controller = new FriendsController({
      removeFriend,
    } as unknown as FriendsService);

    await expect(
      controller.removeFriend(
        { user: { sub: 'current-user', login: 'alice' } } as never,
        'friend-user',
      ),
    ).resolves.toBeUndefined();

    expect(removeFriend).toHaveBeenCalledWith('current-user', 'friend-user');
    expect(
      Reflect.getMetadata(
        PATH_METADATA,
        FriendsController.prototype.removeFriend,
      ),
    ).toBe(':userId');
    expect(
      Reflect.getMetadata(
        HTTP_CODE_METADATA,
        FriendsController.prototype.removeFriend,
      ),
    ).toBe(HttpStatus.NO_CONTENT);
    expect(
      Reflect.getMetadata(
        GUARDS_METADATA,
        FriendsController.prototype.removeFriend,
      ),
    ).toContain(JwtAuthGuard);
  });
});
