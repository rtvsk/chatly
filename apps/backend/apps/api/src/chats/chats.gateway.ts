import { ConfigService } from '@nestjs/config';
import {
  OnGatewayConnection,
  OnGatewayInit,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { verify } from 'jsonwebtoken';
import { Server, Socket } from 'socket.io';

import type { ChatMessage } from './chats.service';

type AccessTokenPayload = {
  sub: string;
  login: string;
};

type MessageCreatedEvent = Omit<ChatMessage, 'createdAt' | 'updatedAt'> & {
  createdAt: string;
  updatedAt: string;
};

export const userRoom = (userId: string): string => `user:${userId}`;

@WebSocketGateway({
  namespace: '/chats',
  transports: ['websocket'],
})
export class ChatsGateway implements OnGatewayInit, OnGatewayConnection {
  @WebSocketServer()
  private server!: Server;

  constructor(private readonly configService: ConfigService) {}

  afterInit(server: Server): void {
    server.use((socket, next) => {
      const token = socket.handshake.auth?.token;
      if (typeof token !== 'string') {
        next(new Error('Unauthorized'));
        return;
      }

      try {
        const payload = verify(
          token,
          this.configService.getOrThrow<string>('JWT_ACCESS_SECRET'),
        ) as AccessTokenPayload;

        if (!payload.sub || !payload.login) {
          next(new Error('Unauthorized'));
          return;
        }

        socket.data.user = { sub: payload.sub, login: payload.login };
        next();
      } catch {
        next(new Error('Unauthorized'));
      }
    });
  }

  handleConnection(socket: Socket): void {
    const user = socket.data.user as AccessTokenPayload | undefined;
    if (!user) {
      socket.disconnect(true);
      return;
    }

    void socket.join(userRoom(user.sub));
  }

  publishMessageCreated(
    participantIds: readonly string[],
    message: ChatMessage,
  ): void {
    const payload: MessageCreatedEvent = {
      ...message,
      createdAt: message.createdAt.toISOString(),
      updatedAt: message.updatedAt.toISOString(),
    };

    for (const participantId of new Set(participantIds)) {
      this.server.to(userRoom(participantId)).emit('message.created', payload);
    }
  }
}
