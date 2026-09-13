import { ConfigService } from '@nestjs/config';
import { sign } from 'jsonwebtoken';

import { ChatsGateway, userRoom } from './chats.gateway';

describe('ChatsGateway', () => {
  const accessSecret = 'access-secret';
  const configService = {
    getOrThrow: jest.fn().mockReturnValue(accessSecret),
  } as unknown as ConfigService;

  it('authenticates the handshake and joins only the authenticated user room', () => {
    const gateway = new ChatsGateway(configService);
    let middleware:
      | ((
          socket: {
            handshake: { auth: { token: string } };
            data: Record<string, unknown>;
          },
          next: (error?: Error) => void,
        ) => void)
      | undefined;
    const server = { use: jest.fn((callback) => (middleware = callback)) };
    gateway.afterInit(server as never);

    const socket = {
      handshake: {
        auth: { token: sign({ sub: 'user-id', login: 'alice' }, accessSecret) },
      },
      data: {},
      join: jest.fn(),
      disconnect: jest.fn(),
    };
    const next = jest.fn();
    middleware!(socket, next);
    gateway.handleConnection(socket as never);

    expect(next).toHaveBeenCalledWith();
    expect(socket.join).toHaveBeenCalledWith(userRoom('user-id'));
    expect(socket.join).not.toHaveBeenCalledWith(userRoom('someone-else'));
  });

  it('rejects an invalid handshake token', () => {
    const gateway = new ChatsGateway(configService);
    let middleware:
      | ((
          socket: { handshake: { auth: { token: string } } },
          next: (error?: Error) => void,
        ) => void)
      | undefined;
    gateway.afterInit({
      use: jest.fn((callback) => (middleware = callback)),
    } as never);

    const next = jest.fn();
    middleware!({ handshake: { auth: { token: 'invalid' } } }, next);

    expect(next).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Unauthorized' }),
    );
  });

  it('publishes a JSON-safe message to every participant room once', () => {
    const gateway = new ChatsGateway(configService);
    const emit = jest.fn();
    const to = jest.fn().mockReturnValue({ emit });
    (gateway as unknown as { server: { to: typeof to } }).server = { to };
    const createdAt = new Date('2026-09-13T10:00:00.000Z');

    gateway.publishMessageCreated(['sender', 'recipient', 'sender'], {
      id: 'message-id',
      chatId: 'chat-id',
      senderId: 'sender',
      text: 'Hello',
      createdAt,
      updatedAt: createdAt,
    });

    expect(to).toHaveBeenCalledTimes(2);
    expect(to).toHaveBeenNthCalledWith(1, userRoom('sender'));
    expect(to).toHaveBeenNthCalledWith(2, userRoom('recipient'));
    expect(emit).toHaveBeenCalledWith('message.created', {
      id: 'message-id',
      chatId: 'chat-id',
      senderId: 'sender',
      text: 'Hello',
      createdAt: '2026-09-13T10:00:00.000Z',
      updatedAt: '2026-09-13T10:00:00.000Z',
    });
  });
});
