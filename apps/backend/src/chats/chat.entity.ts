import {
  Column,
  CreateDateColumn,
  Entity,
  OneToMany,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { ChatParticipant } from './chat_participant.entity';
import { Message } from 'src/messages/message.entity';

export enum ChatType {
  DIRECT = 'direct',
  GROUP = 'group',
}

@Entity('chats')
export class Chat {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'enum', enum: ChatType, default: ChatType.DIRECT })
  type: ChatType;

  @OneToMany(() => ChatParticipant, (participant) => participant.chat)
  participants: ChatParticipant[];

  @OneToMany(() => Message, (message) => message.chat)
  messages: Message[];

  @Column({ nullable: true })
  lastMessageId: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
