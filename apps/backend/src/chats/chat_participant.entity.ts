import {
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  Unique,
  Column,
} from 'typeorm';

import { User } from '../users/user.entity';
import { Chat } from './chat.entity';

@Entity('chat_participants')
@Unique(['chatId', 'userId'])
export class ChatParticipant {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  chatId: string;

  @Column()
  userId: string;

  @ManyToOne(() => Chat, (chat) => chat.participants, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'chatId' })
  chat: Chat;

  @ManyToOne(() => User, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column({ nullable: true })
  lastReadMessageId: string;

  @CreateDateColumn()
  joinedAt: Date;
}
