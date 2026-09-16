import { ConfigService } from '@nestjs/config';
import { Logger } from '@nestjs/common';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { verify } from 'jsonwebtoken';
import { Server, Socket } from 'socket.io';

import { FriendsService } from '../friendships/friends.service';
import { FriendshipRealtimePublisher } from '../realtime/friendship-realtime.publisher';
import { userRoom } from '../realtime/user-room';
import type { ChatMessageResponse } from './chats.service';

type AccessTokenPayload = {
  sub: string;
  login: string;
};

type MessageCreatedEvent = Omit<
  ChatMessageResponse,
  'createdAt' | 'updatedAt'
> & { createdAt: string; updatedAt: string };

type MessageReadEvent = {
  chatId: string;
  readerId: string;
  messageId: string;
  messageCreatedAt: string;
};

export { userRoom } from '../realtime/user-room';

type PresenceSnapshotEvent = {
  onlineUserIds: string[];
};

type PresenceChangedEvent = {
  userId: string;
  isOnline: boolean;
};

type TypingSetPayload = {
  recipientUserId: string;
  isTyping: boolean;
};

type TypingChangedEvent = {
  userId: string;
  isTyping: boolean;
};

const isTypingSetPayload = (payload: unknown): payload is TypingSetPayload => {
  if (
    typeof payload !== 'object' ||
    payload === null ||
    Array.isArray(payload)
  ) {
    return false;
  }

  const candidate = payload as Record<string, unknown>;
  return (
    typeof candidate.recipientUserId === 'string' &&
    typeof candidate.isTyping === 'boolean'
  );
};

@WebSocketGateway({
  namespace: '/chats',
  transports: ['websocket'],
})
export class ChatsGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  private server!: Server;

  private readonly logger = new Logger(ChatsGateway.name);

  constructor(
    private readonly configService: ConfigService,
    private readonly friendsService: FriendsService,
    private readonly friendshipRealtimePublisher: FriendshipRealtimePublisher,
  ) {}

  afterInit(server: Server): void {
    this.server = server;
    this.friendshipRealtimePublisher.setServer(server);

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

  async handleConnection(socket: Socket): Promise<void> {
    const user = socket.data.user as AccessTokenPayload | undefined;
    if (!user) {
      socket.disconnect(true);
      return;
    }

    await socket.join(userRoom(user.sub));
    await this.sendPresenceSnapshot(socket, user.sub);
    await this.broadcastPresenceChange(user.sub, true);
  }

  async handleDisconnect(socket: Socket): Promise<void> {
    const user = socket.data.user as AccessTokenPayload | undefined;
    if (!user) {
      return;
    }

    try {
      const remainingSockets = await this.server
        .in(userRoom(user.sub))
        .fetchSockets();

      if (remainingSockets.length === 0) {
        await this.broadcastPresenceChange(user.sub, false);
      }
    } catch {
      this.logger.warn('Unable to determine presence after disconnect');
    }
  }

  @SubscribeMessage('presence.get')
  async handlePresenceGet(socket: Socket): Promise<void> {
    const user = socket.data.user as AccessTokenPayload | undefined;
    if (!user) {
      socket.disconnect(true);
      return;
    }

    await this.sendPresenceSnapshot(socket, user.sub);
  }

  @SubscribeMessage('typing.set')
  async handleTypingSet(socket: Socket, payload: unknown): Promise<void> {
    const user = socket.data.user as AccessTokenPayload | undefined;
    if (!user) {
      socket.disconnect(true);
      return;
    }

    if (!isTypingSetPayload(payload) || payload.recipientUserId === user.sub) {
      return;
    }

    try {
      const friendIds = await this.friendsService.getAcceptedFriendIds(
        user.sub,
      );
      if (!friendIds.includes(payload.recipientUserId)) {
        return;
      }

      const typingChanged: TypingChangedEvent = {
        userId: user.sub,
        isTyping: payload.isTyping,
      };
      this.server
        .to(userRoom(payload.recipientUserId))
        .emit('typing.changed', typingChanged);
    } catch {
      this.logger.warn('Unable to forward typing change');
    }
  }

  publishMessageCreated(
    participantIds: readonly string[],
    message: ChatMessageResponse,
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

  publishMessageRead(
    participantIds: readonly string[],
    payload: MessageReadEvent,
  ): void {
    for (const participantId of new Set(participantIds)) {
      this.server.to(userRoom(participantId)).emit('message.read', payload);
    }
  }

  private async sendPresenceSnapshot(
    socket: Socket,
    userId: string,
  ): Promise<void> {
    try {
      const friendIds = await this.friendsService.getAcceptedFriendIds(userId);
      const onlineUserIds = await this.getOnlineUserIds(friendIds);
      const payload: PresenceSnapshotEvent = { onlineUserIds };

      socket.emit('presence.snapshot', payload);
    } catch {
      this.logger.warn('Unable to load presence snapshot');
    }
  }

  private async broadcastPresenceChange(
    userId: string,
    isOnline: boolean,
  ): Promise<void> {
    try {
      const friendIds = await this.friendsService.getAcceptedFriendIds(userId);
      const payload: PresenceChangedEvent = { userId, isOnline };

      for (const friendId of friendIds) {
        this.server.to(userRoom(friendId)).emit('presence.changed', payload);
      }
    } catch {
      this.logger.warn('Unable to broadcast presence change');
    }
  }

  private async getOnlineUserIds(
    userIds: readonly string[],
  ): Promise<string[]> {
    const onlineUserIds: string[] = [];

    for (const userId of new Set(userIds)) {
      const sockets = await this.server.in(userRoom(userId)).fetchSockets();
      if (sockets.length > 0) {
        onlineUserIds.push(userId);
      }
    }

    return onlineUserIds;
  }
}
