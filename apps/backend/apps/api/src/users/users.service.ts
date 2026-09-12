import { Injectable } from '@nestjs/common';
import { and, asc, eq, ilike, ne } from 'drizzle-orm';

import { DatabaseService } from '../database/database.service';
import { avatars, users } from '../database/schema';

@Injectable()
export class UsersService {
  constructor(private readonly database: DatabaseService) {}

  async searchByLogin(login: string, currentUserId: string) {
    const normalizedLogin = login.trim();

    if (normalizedLogin.length < 3) {
      return [];
    }

    const escapedLogin = normalizedLogin.replace(/[\\%_]/g, '\\$&');

    const matchingUsers = await this.database.db
      .select({
        id: users.id,
        login: users.login,
        avatarId: avatars.id,
      })
      .from(users)
      .leftJoin(
        avatars,
        and(eq(avatars.userId, users.id), eq(avatars.isSelected, true)),
      )
      .where(
        and(
          ilike(users.login, `${escapedLogin}%`),
          ne(users.id, currentUserId),
        ),
      )
      .orderBy(asc(users.login))
      .limit(20);

    return matchingUsers.map(({ id, login, avatarId }) => ({
      id,
      login,
      avatarUrl: avatarId ? `/avatars/${avatarId}/file` : null,
    }));
  }
}
