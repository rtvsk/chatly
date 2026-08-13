import { Injectable } from '@nestjs/common';
import { eq } from 'drizzle-orm';

import { DatabaseService } from '../database/database.service';
import { chatParticipants } from '../database/schema';

@Injectable()
export class ChatsService {
  constructor(private readonly database: DatabaseService) {}

  async getMyChatIds(userId: string) {
    const participants = await this.database.db
      .select({ chatId: chatParticipants.chatId })
      .from(chatParticipants)
      .where(eq(chatParticipants.userId, userId));

    return participants.map((participant) => participant.chatId);
  }
}
