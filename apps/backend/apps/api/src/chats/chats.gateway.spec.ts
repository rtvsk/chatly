import { ConfigService } from '@nestjs/config';
import { sign } from 'jsonwebtoken';

import { FriendsService } from '../friendships/friends.service';
import { ChatsGateway, userRoom } from './chats.gateway';

describe('ChatsGateway', () => {
  const accessSecret = 'access-secret';
  const configService = {
    getOrThrow: jest.fn().mockReturnValue(accessSecret),
  } as unknown as ConfigService;

  const createFriendsService = (friendIds: string[] = []) =>
    ({
      getAcceptedFriendIds: jest.fn().mockResolvedValue(friendIds),
    }) as unknown as FriendsService;

  it('authenticates the handshake and joins only the authenticated user room', async () => {
    const gateway = new ChatsGateway(configService, createFriendsService());
    let middleware:
      | ((
          socket: {
            handshake: { auth: { token: string } };
            data: Record<string, unknown>;
          },
          next: (error?: Error) => void,
        ) => void)
      | undefined;
    const server = {
      use: jest.fn((callback) => (middleware = callback)),
      in: jest.fn(),
      to: jest.fn(),
    };
    gateway.afterInit(server as never);

    const socket = {
      handshake: {
        auth: { token: sign({ sub: 'user-id', login: 'alice' }, accessSecret) },
      },
      data: {},
      join: jest.fn(),
      emit: jest.fn(),
      disconnect: jest.fn(),
    };
    const next = jest.fn();
    middleware!(socket, next);
    await gateway.handleConnection(socket as never);

    expect(next).toHaveBeenCalledWith();
    expect(socket.join).toHaveBeenCalledWith(userRoom('user-id'));
    expect(socket.join).not.toHaveBeenCalledWith(userRoom('someone-else'));
  });

  it('rejects an invalid handshake token', () => {
    const gateway = new ChatsGateway(configService, createFriendsService());
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
    const gateway = new ChatsGateway(configService, createFriendsService());
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

  it('forwards typing changes only to the accepted recipient room', async () => {
    const friendsService = createFriendsService(['recipient-id']);
    const gateway = new ChatsGateway(configService, friendsService);
    const emit = jest.fn();
    const to = jest.fn().mockReturnValue({ emit });
    (gateway as unknown as { server: { to: typeof to } }).server = { to };
    const socket = {
      data: { user: { sub: 'sender-id', login: 'alice' } },
      disconnect: jest.fn(),
    };

    await gateway.handleTypingSet(socket as never, {
      recipientUserId: 'recipient-id',
      isTyping: true,
    });

    expect(friendsService.getAcceptedFriendIds).toHaveBeenCalledWith('sender-id');
    expect(to).toHaveBeenCalledWith(userRoom('recipient-id'));
    expect(emit).toHaveBeenCalledWith('typing.changed', {
      userId: 'sender-id',
      isTyping: true,
    });
  });

  it.each([
    undefined,
    { recipientUserId: 'recipient-id', isTyping: 'true' },
    { recipientUserId: 42, isTyping: true },
    [],
  ])('ignores malformed typing payload %#', async (payload) => {
    const friendsService = createFriendsService(['recipient-id']);
    const gateway = new ChatsGateway(configService, friendsService);
    const to = jest.fn();
    (gateway as unknown as { server: { to: typeof to } }).server = { to };
    const socket = {
      data: { user: { sub: 'sender-id', login: 'alice' } },
      disconnect: jest.fn(),
    };

    await gateway.handleTypingSet(socket as never, payload);

    expect(friendsService.getAcceptedFriendIds).not.toHaveBeenCalled();
    expect(to).not.toHaveBeenCalled();
  });

  it('ignores typing changes targeting the sender', async () => {
    const friendsService = createFriendsService(['sender-id']);
    const gateway = new ChatsGateway(configService, friendsService);
    const to = jest.fn();
    (gateway as unknown as { server: { to: typeof to } }).server = { to };
    const socket = {
      data: { user: { sub: 'sender-id', login: 'alice' } },
      disconnect: jest.fn(),
    };

    await gateway.handleTypingSet(socket as never, {
      recipientUserId: 'sender-id',
      isTyping: false,
    });

    expect(friendsService.getAcceptedFriendIds).not.toHaveBeenCalled();
    expect(to).not.toHaveBeenCalled();
  });

  it('ignores typing changes for users who are not accepted friends', async () => {
    const friendsService = createFriendsService(['friend-id']);
    const gateway = new ChatsGateway(configService, friendsService);
    const to = jest.fn();
    (gateway as unknown as { server: { to: typeof to } }).server = { to };
    const socket = {
      data: { user: { sub: 'sender-id', login: 'alice' } },
      disconnect: jest.fn(),
    };

    await gateway.handleTypingSet(socket as never, {
      recipientUserId: 'non-friend-id',
      isTyping: true,
    });

    expect(friendsService.getAcceptedFriendIds).toHaveBeenCalledWith('sender-id');
    expect(to).not.toHaveBeenCalled();
  });

  it('sends snapshots containing only accepted friends that are online', async () => {
    const friendsService = createFriendsService([
      'online-friend',
      'offline-friend',
    ]);
    const gateway = new ChatsGateway(configService, friendsService);
    const fetchSockets = jest.fn((room: string) =>
      Promise.resolve(room === userRoom('online-friend') ? [{}] : []),
    );
    const server = {
      in: jest.fn((room: string) => ({
        fetchSockets: () => fetchSockets(room),
      })),
      to: jest.fn().mockReturnValue({ emit: jest.fn() }),
    };
    (gateway as unknown as { server: typeof server }).server = server;
    const socket = {
      data: { user: { sub: 'user-id', login: 'alice' } },
      join: jest.fn(),
      emit: jest.fn(),
      disconnect: jest.fn(),
    };

    await gateway.handleConnection(socket as never);
    await gateway.handlePresenceGet(socket as never);

    expect(friendsService.getAcceptedFriendIds).toHaveBeenCalledWith('user-id');
    expect(socket.emit).toHaveBeenNthCalledWith(1, 'presence.snapshot', {
      onlineUserIds: ['online-friend'],
    });
    expect(socket.emit).toHaveBeenNthCalledWith(2, 'presence.snapshot', {
      onlineUserIds: ['online-friend'],
    });
    expect(server.in).not.toHaveBeenCalledWith(userRoom('non-friend'));
  });

  it('notifies only accepted friend rooms when a user connects', async () => {
    const gateway = new ChatsGateway(
      configService,
      createFriendsService(['friend-one', 'friend-two']),
    );
    const emit = jest.fn();
    const server = {
      in: jest
        .fn()
        .mockReturnValue({ fetchSockets: jest.fn().mockResolvedValue([]) }),
      to: jest.fn().mockReturnValue({ emit }),
    };
    (gateway as unknown as { server: typeof server }).server = server;
    const socket = {
      data: { user: { sub: 'user-id', login: 'alice' } },
      join: jest.fn(),
      emit: jest.fn(),
      disconnect: jest.fn(),
    };

    await gateway.handleConnection(socket as never);

    expect(server.to).toHaveBeenCalledWith(userRoom('friend-one'));
    expect(server.to).toHaveBeenCalledWith(userRoom('friend-two'));
    expect(emit).toHaveBeenCalledWith('presence.changed', {
      userId: 'user-id',
      isOnline: true,
    });
    expect(server.to).not.toHaveBeenCalledWith(userRoom('non-friend'));
  });

  it('announces offline only after the last socket disappears', async () => {
    const gateway = new ChatsGateway(
      configService,
      createFriendsService(['friend-id']),
    );
    const emit = jest.fn();
    const fetchSockets = jest
      .fn()
      .mockResolvedValueOnce([{}])
      .mockResolvedValueOnce([]);
    const server = {
      in: jest.fn().mockReturnValue({ fetchSockets }),
      to: jest.fn().mockReturnValue({ emit }),
    };
    (gateway as unknown as { server: typeof server }).server = server;
    const socket = {
      data: { user: { sub: 'user-id', login: 'alice' } },
    };

    await gateway.handleDisconnect(socket as never);
    await gateway.handleDisconnect(socket as never);

    expect(fetchSockets).toHaveBeenCalledTimes(2);
    expect(emit).toHaveBeenCalledTimes(1);
    expect(emit).toHaveBeenCalledWith('presence.changed', {
      userId: 'user-id',
      isOnline: false,
    });
  });

  it('does not announce an offline transition when socket lookup fails', async () => {
    const gateway = new ChatsGateway(
      configService,
      createFriendsService(['friend-id']),
    );
    const emit = jest.fn();
    const server = {
      in: jest.fn().mockReturnValue({
        fetchSockets: jest
          .fn()
          .mockRejectedValue(new Error('Redis unavailable')),
      }),
      to: jest.fn().mockReturnValue({ emit }),
    };
    (gateway as unknown as { server: typeof server }).server = server;
    (gateway as unknown as { logger: { warn: jest.Mock } }).logger = {
      warn: jest.fn(),
    };

    await gateway.handleDisconnect({
      data: { user: { sub: 'user-id', login: 'alice' } },
    } as never);

    expect(emit).not.toHaveBeenCalled();
  });
});
