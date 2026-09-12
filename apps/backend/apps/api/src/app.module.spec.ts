import { MODULE_METADATA } from '@nestjs/common/constants';

import { AppModule } from './app.module';
import { FriendsModule } from './friendships/friends.module';
import { UsersModule } from './users/users.module';

describe('AppModule', () => {
  it('registers the contacts API modules', () => {
    const imports = Reflect.getMetadata(
      MODULE_METADATA.IMPORTS,
      AppModule,
    ) as unknown[];

    expect(imports).toEqual(
      expect.arrayContaining([FriendsModule, UsersModule]),
    );
  });
});
