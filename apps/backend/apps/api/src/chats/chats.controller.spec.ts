import { HttpStatus } from '@nestjs/common';
import {
  GUARDS_METADATA,
  HTTP_CODE_METADATA,
  METHOD_METADATA,
  PATH_METADATA,
} from '@nestjs/common/constants';
import { RequestMethod } from '@nestjs/common/enums/request-method.enum';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChatsController } from './chats.controller';
import { ChatsService } from './chats.service';

describe('ChatsController', () => {
  it('protects PATCH /chats/:chatId/read and returns no content', async () => {
    const markRead = jest.fn().mockResolvedValue(undefined);
    const controller = new ChatsController({
      markRead,
    } as unknown as ChatsService);

    await expect(
      controller.markRead(
        { user: { sub: 'current-user', login: 'alice' } } as never,
        'chat-id',
        { messageId: '11111111-1111-1111-1111-111111111111' },
      ),
    ).resolves.toBeUndefined();

    expect(markRead).toHaveBeenCalledWith(
      'current-user',
      'chat-id',
      '11111111-1111-1111-1111-111111111111',
    );
    expect(
      Reflect.getMetadata(PATH_METADATA, ChatsController.prototype.markRead),
    ).toBe(':chatId/read');
    expect(
      Reflect.getMetadata(METHOD_METADATA, ChatsController.prototype.markRead),
    ).toBe(RequestMethod.PATCH);
    expect(
      Reflect.getMetadata(
        HTTP_CODE_METADATA,
        ChatsController.prototype.markRead,
      ),
    ).toBe(HttpStatus.NO_CONTENT);
    expect(Reflect.getMetadata(GUARDS_METADATA, ChatsController)).toContain(
      JwtAuthGuard,
    );
  });
});
