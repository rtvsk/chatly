import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ChatParticipant } from './chat_participant.entity';

@Injectable()
export class ChatsService {
  constructor(
    @InjectRepository(ChatParticipant)
    private readonly chatParticipantsRepository: Repository<ChatParticipant>,
  ) {}

  async getMyChatIds(userId: string) {
    const participants = await this.chatParticipantsRepository.find({
      where: {
        userId,
      },
      select: {
        chatId: true,
      },
    });
    console.log(participants);
    return participants.map((participant) => participant.chatId);
  }
}
