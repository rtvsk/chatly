import { Injectable } from '@nestjs/common';
import { eq } from 'drizzle-orm';

import { DatabaseService } from '../database/database.service';
import { users } from '../database/schema';

@Injectable()
export class UsersService {
  constructor(private readonly database: DatabaseService) {}

  async findByLogin(login: string) {
    const [user] = await this.database.db
      .select({
        id: users.id,
        login: users.login,
        createdAt: users.createdAt,
      })
      .from(users)
      .where(eq(users.login, login))
      .limit(1);

    return user ?? null;
  }
}
