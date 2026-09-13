import { DatabaseService } from '../database/database.service';
import { ChatsGateway } from './chats.gateway';
import { ChatsService } from './chats.service';

describe('ChatsService', () => {
  const gateway = {
    publishMessageCreated: jest.fn(),
  } as unknown as ChatsGateway;

  it('returns direct chat summaries with a nullable last message', async () => {
    const createdAt = new Date('2026-09-13T09:00:00.000Z');
    const builder = {
      from: jest.fn().mockReturnThis(),
      innerJoin: jest.fn().mockReturnThis(),
      leftJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockResolvedValue([
        {
          id: 'chat-id',
          peerId: 'peer-id',
          peerLogin: 'alice',
          peerAvatarId: 'avatar-id',
          lastMessageId: null,
          lastMessageChatId: null,
          lastMessageSenderId: null,
          lastMessageText: null,
          lastMessageCreatedAt: null,
          lastMessageUpdatedAt: null,
          createdAt,
          updatedAt: createdAt,
        },
      ]),
    };
    const service = new ChatsService(
      {
        db: { select: jest.fn().mockReturnValue(builder) },
      } as unknown as DatabaseService,
      gateway,
    );

    await expect(service.getMyChats('current-user')).resolves.toEqual([
      {
        id: 'chat-id',
        type: 'direct',
        peer: {
          id: 'peer-id',
          login: 'alice',
          avatarUrl: '/avatars/avatar-id/file',
        },
        lastMessage: null,
        createdAt,
        updatedAt: createdAt,
      },
    ]);
  });

  it('trims a message and atomically updates its chat', async () => {
    const createdAt = new Date('2026-09-13T10:00:00.000Z');
    const participantQuery = {
      from: jest.fn().mockReturnThis(),
      innerJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      for: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue([{ id: 'chat-id' }]),
    };
    const message = {
      id: 'message-id',
      chatId: 'chat-id',
      senderId: 'current-user',
      text: 'Hello',
      createdAt,
      updatedAt: createdAt,
    };
    const insertMessage = {
      values: jest.fn().mockReturnThis(),
      returning: jest.fn().mockResolvedValue([message]),
    };
    const updateChat = {
      set: jest.fn().mockReturnThis(),
      where: jest.fn().mockResolvedValue(undefined),
    };
    const participantRowsQuery = {
      from: jest.fn().mockReturnThis(),
      where: jest
        .fn()
        .mockResolvedValue([
          { userId: 'current-user' },
          { userId: 'peer-user' },
        ]),
    };
    const tx = {
      select: jest
        .fn()
        .mockReturnValueOnce(participantQuery)
        .mockReturnValueOnce(participantRowsQuery),
      insert: jest.fn().mockReturnValue(insertMessage),
      update: jest.fn().mockReturnValue(updateChat),
    };
    const transaction = jest.fn(async (callback) => callback(tx));
    const service = new ChatsService(
      {
        db: { transaction },
      } as unknown as DatabaseService,
      gateway,
    );

    await expect(
      service.sendMessage('current-user', 'chat-id', '  Hello  '),
    ).resolves.toEqual(message);

    expect(participantQuery.for).toHaveBeenCalledWith('update');
    expect(insertMessage.values).toHaveBeenCalledWith({
      chatId: 'chat-id',
      senderId: 'current-user',
      text: 'Hello',
    });
    expect(updateChat.set).toHaveBeenCalledWith(
      expect.objectContaining({ lastMessageId: 'message-id' }),
    );
    expect(gateway.publishMessageCreated).toHaveBeenCalledWith(
      ['current-user', 'peer-user'],
      message,
    );
  });

  it.each(['   ', 'x'.repeat(4001), null])(
    'rejects an invalid message body',
    async (text) => {
      const service = new ChatsService(
        {
          db: { transaction: jest.fn() },
        } as unknown as DatabaseService,
        gateway,
      );

      await expect(
        service.sendMessage('current-user', 'chat-id', text),
      ).rejects.toMatchObject({ status: 400 });
    },
  );

  it('rejects direct-chat creation for oneself before querying the database', async () => {
    const select = jest.fn();
    const service = new ChatsService(
      {
        db: { select },
      } as unknown as DatabaseService,
      gateway,
    );

    await expect(
      service.getOrCreateDirectChat('current-user', 'current-user'),
    ).rejects.toMatchObject({ status: 400 });
    expect(select).not.toHaveBeenCalled();
  });

  it('locks the accepted friendship and rejects non-friends', async () => {
    const userQuery = {
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue([{ id: 'peer-id' }]),
    };
    const friendshipQuery = {
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      for: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue([]),
    };
    const tx = { select: jest.fn().mockReturnValue(friendshipQuery) };
    const transaction = jest.fn(async (callback) => callback(tx));
    const service = new ChatsService(
      {
        db: {
          select: jest.fn().mockReturnValue(userQuery),
          transaction,
        },
      } as unknown as DatabaseService,
      gateway,
    );

    await expect(
      service.getOrCreateDirectChat('current-user', 'peer-id'),
    ).rejects.toMatchObject({ status: 403 });
    expect(friendshipQuery.for).toHaveBeenCalledWith('update');
  });

  it('hides messages from nonparticipants', async () => {
    const participantQuery = {
      from: jest.fn().mockReturnThis(),
      innerJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue([]),
    };
    const service = new ChatsService(
      {
        db: { select: jest.fn().mockReturnValue(participantQuery) },
      } as unknown as DatabaseService,
      gateway,
    );

    await expect(
      service.getMessages('outsider-id', 'chat-id'),
    ).rejects.toMatchObject({ status: 404 });
  });

  it('does not publish a message when its transaction fails', async () => {
    const publishMessageCreated = jest.fn();
    const service = new ChatsService(
      {
        db: {
          transaction: jest.fn().mockRejectedValue(new Error('database error')),
        },
      } as unknown as DatabaseService,
      { publishMessageCreated } as unknown as ChatsGateway,
    );

    await expect(
      service.sendMessage('current-user', 'chat-id', 'Hello'),
    ).rejects.toThrow('database error');
    expect(publishMessageCreated).not.toHaveBeenCalled();
  });
});
