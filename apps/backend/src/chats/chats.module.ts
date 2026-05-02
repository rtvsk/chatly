import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { Chat } from './chat.entity';
import { ChatParticipant } from './chat_participant.entity';
import { Message } from 'src/messages/message.entity';
import { User } from 'src/users/user.entity';
import { ChatsController } from './chats.controller';
import { ChatsService } from './chats.service';

@Module({
  imports: [TypeOrmModule.forFeature([Chat, ChatParticipant, Message, User])],
  controllers: [ChatsController],
  providers: [ChatsService],
  exports: [ChatsService],
})
export class ChatsModule {}
