import { PgDialect } from 'drizzle-orm/pg-core';

import { DatabaseService } from '../database/database.service';
import { ChatsGateway } from './chats.gateway';
import { ChatsService } from './chats.service';

describe('ChatsService', () => {
  const gateway = {
    publishMessageCreated: jest.fn(),
    publishMessageRead: jest.fn(),
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
          lastMessageReadByPeer: false,
          unreadCount: 0,
          createdAt,
          updatedAt: createdAt,
        },
      ]),
    };
    const select = jest.fn().mockReturnValue(builder);
    const service = new ChatsService(
      {
        db: { select },
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
        unreadCount: 0,
        createdAt,
        updatedAt: createdAt,
      },
    ]);

    const unreadCount = select.mock.calls[0][0].unreadCount;
    const query = new PgDialect().sqlToQuery(unreadCount);
    expect(query.sql).toContain('from "messages" as "unread_chat_message"');
    expect(query.sql).toContain(
      'left join "messages" as "last_read_chat_message"',
    );
    expect(query.sql).toContain('"unread_chat_message"."senderId" <> $1');
    expect(query.sql).toContain('"last_read_chat_message"."id" is null');
    expect(query.sql).toContain(
      '"unread_chat_message"."createdAt" > "last_read_chat_message"."createdAt"',
    );
    expect(query.sql).toContain(
      '"unread_chat_message"."id" > "last_read_chat_message"."id"',
    );
    expect(query.params).toEqual(['current-user']);
  });

  it('includes the peer read status on a chat summary last message', async () => {
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
          peerAvatarId: null,
          lastMessageId: 'message-id',
          lastMessageChatId: 'chat-id',
          lastMessageSenderId: 'current-user',
          lastMessageText: 'Hello',
          lastMessageCreatedAt: createdAt,
          lastMessageUpdatedAt: createdAt,
          lastMessageReadByPeer: true,
          unreadCount: 0,
          createdAt,
          updatedAt: createdAt,
        },
      ]),
    };
    const select = jest.fn().mockReturnValue(builder);
    const service = new ChatsService(
      { db: { select } } as unknown as DatabaseService,
      gateway,
    );

    await expect(service.getMyChats('current-user')).resolves.toEqual([
      expect.objectContaining({
        lastMessage: expect.objectContaining({
          id: 'message-id',
          readByPeer: true,
        }),
      }),
    ]);

    const readByPeer = select.mock.calls[0][0].lastMessageReadByPeer;
    const query = new PgDialect().sqlToQuery(readByPeer);
    expect(query.sql).toContain('"peer_last_read_message"');
    expect(query.sql).toContain('< "peer_last_read_message"."createdAt"');
    expect(builder.leftJoin).toHaveBeenCalledTimes(3);
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
    ).resolves.toEqual({ ...message, readByPeer: false });

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
      { ...message, readByPeer: false },
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

  it('returns message read status from the peer cursor using message order', async () => {
    const createdAt = new Date('2026-09-13T10:00:00.000Z');
    const participant = participantQuery([{ id: 'chat-id' }]);
    const history = {
      from: jest.fn().mockReturnThis(),
      innerJoin: jest.fn().mockReturnThis(),
      leftJoin: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockResolvedValue([
        {
          id: 'message-before-cursor',
          chatId: 'chat-id',
          senderId: 'current-user',
          text: 'Before',
          createdAt,
          updatedAt: createdAt,
          readByPeer: true,
        },
        {
          id: 'message-after-cursor',
          chatId: 'chat-id',
          senderId: 'current-user',
          text: 'After',
          createdAt,
          updatedAt: createdAt,
          readByPeer: false,
        },
      ]),
    };
    const select = jest
      .fn()
      .mockReturnValueOnce(participant)
      .mockReturnValueOnce(history);
    const service = new ChatsService(
      { db: { select } } as unknown as DatabaseService,
      gateway,
    );

    await expect(
      service.getMessages('current-user', 'chat-id'),
    ).resolves.toEqual([
      expect.objectContaining({
        id: 'message-before-cursor',
        readByPeer: true,
      }),
      expect.objectContaining({
        id: 'message-after-cursor',
        readByPeer: false,
      }),
    ]);

    const readByPeer = select.mock.calls[1][0].readByPeer;
    const query = new PgDialect().sqlToQuery(readByPeer);
    expect(query.sql).toContain('"peer_last_read_message"');
    expect(query.sql).toContain('< "peer_last_read_message"."createdAt"');
    expect(query.sql).toContain('<= "peer_last_read_message"."id"');
    expect(history.innerJoin).toHaveBeenCalled();
    expect(history.leftJoin).toHaveBeenCalled();
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

  it('marks a valid message as read for a participant', async () => {
    const newer = new Date('2026-09-13T10:01:00.000Z');
    const participantLockQuery = participantQuery([{ id: 'chat-id' }]);
    const readCursorQuery = participantQuery([{ lastReadMessageId: null }]);
    const targetMessageQuery = messageQuery([
      { id: '11111111-1111-1111-1111-111111111111', createdAt: newer },
    ]);
    const update = {
      set: jest.fn().mockReturnThis(),
      where: jest.fn().mockResolvedValue(undefined),
    };
    const participantRows = {
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
        .mockReturnValueOnce(participantLockQuery)
        .mockReturnValueOnce(readCursorQuery)
        .mockReturnValueOnce(targetMessageQuery)
        .mockReturnValueOnce(participantRows),
      update: jest.fn().mockReturnValue(update),
    };
    const publishMessageRead = jest.fn();
    const service = serviceWithTransaction(tx, {
      publishMessageRead,
    } as unknown as ChatsGateway);

    await expect(
      service.markRead(
        'current-user',
        'chat-id',
        '11111111-1111-1111-1111-111111111111',
      ),
    ).resolves.toBeUndefined();

    expect(readCursorQuery.for).toHaveBeenCalledWith('update');
    expect(update.set).toHaveBeenCalledWith({
      lastReadMessageId: '11111111-1111-1111-1111-111111111111',
    });
    expect(publishMessageRead).toHaveBeenCalledWith(
      ['current-user', 'peer-user'],
      {
        chatId: 'chat-id',
        readerId: 'current-user',
        messageId: '11111111-1111-1111-1111-111111111111',
        messageCreatedAt: '2026-09-13T10:01:00.000Z',
      },
    );
  });

  it('does not rewind an existing read cursor', async () => {
    const cursorTime = new Date('2026-09-13T10:01:00.000Z');
    const olderTime = new Date('2026-09-13T10:00:00.000Z');
    const participantLockQuery = participantQuery([{ id: 'chat-id' }]);
    const readCursorQuery = participantQuery([
      { lastReadMessageId: '22222222-2222-2222-2222-222222222222' },
    ]);
    const targetMessageQuery = messageQuery([
      { id: '11111111-1111-1111-1111-111111111111', createdAt: olderTime },
    ]);
    const currentMessageQuery = messageQuery([
      { id: '22222222-2222-2222-2222-222222222222', createdAt: cursorTime },
    ]);
    const tx = {
      select: jest
        .fn()
        .mockReturnValueOnce(participantLockQuery)
        .mockReturnValueOnce(readCursorQuery)
        .mockReturnValueOnce(targetMessageQuery)
        .mockReturnValueOnce(currentMessageQuery),
      update: jest.fn(),
    };
    const publishMessageRead = jest.fn();
    const service = serviceWithTransaction(tx, {
      publishMessageRead,
    } as unknown as ChatsGateway);

    await service.markRead(
      'current-user',
      'chat-id',
      '11111111-1111-1111-1111-111111111111',
    );

    expect(tx.update).not.toHaveBeenCalled();
    expect(publishMessageRead).not.toHaveBeenCalled();
  });

  it.each([undefined, 'not-a-uuid', 1])(
    'rejects an invalid read message ID',
    async (messageId) => {
      const transaction = jest.fn();
      const service = new ChatsService(
        { db: { transaction } } as unknown as DatabaseService,
        gateway,
      );

      await expect(
        service.markRead('current-user', 'chat-id', messageId),
      ).rejects.toMatchObject({ status: 400 });
      expect(transaction).not.toHaveBeenCalled();
    },
  );

  it('hides read targets outside the participant chat', async () => {
    const participantLockQuery = participantQuery([{ id: 'chat-id' }]);
    const readCursorQuery = participantQuery([{ lastReadMessageId: null }]);
    const targetMessageQuery = messageQuery([]);
    const tx = {
      select: jest
        .fn()
        .mockReturnValueOnce(participantLockQuery)
        .mockReturnValueOnce(readCursorQuery)
        .mockReturnValueOnce(targetMessageQuery),
      update: jest.fn(),
    };
    const service = serviceWithTransaction(tx, gateway);

    await expect(
      service.markRead(
        'current-user',
        'chat-id',
        '11111111-1111-1111-1111-111111111111',
      ),
    ).rejects.toMatchObject({ status: 404 });
  });

  it('does not publish a read event when the transaction fails', async () => {
    const publishMessageRead = jest.fn();
    const service = new ChatsService(
      {
        db: {
          transaction: jest.fn().mockRejectedValue(new Error('database error')),
        },
      } as unknown as DatabaseService,
      { publishMessageRead } as unknown as ChatsGateway,
    );

    await expect(
      service.markRead(
        'current-user',
        'chat-id',
        '11111111-1111-1111-1111-111111111111',
      ),
    ).rejects.toThrow('database error');
    expect(publishMessageRead).not.toHaveBeenCalled();
  });
});

function participantQuery(rows: unknown[]) {
  return {
    from: jest.fn().mockReturnThis(),
    innerJoin: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    for: jest.fn().mockReturnThis(),
    limit: jest.fn().mockResolvedValue(rows),
  };
}

function messageQuery(rows: unknown[]) {
  return {
    from: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    limit: jest.fn().mockResolvedValue(rows),
  };
}

function serviceWithTransaction(
  tx: object,
  gateway: ChatsGateway,
): ChatsService {
  return new ChatsService(
    {
      db: { transaction: jest.fn(async (callback) => callback(tx)) },
    } as unknown as DatabaseService,
    gateway,
  );
}
