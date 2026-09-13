import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { Request } from 'express';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChatsService } from './chats.service';

type RequestWithUser = Request & {
  user: {
    sub: string;
    login: string;
  };
};

type CreateMessageBody = {
  text?: unknown;
};

@Controller('chats')
@UseGuards(JwtAuthGuard)
export class ChatsController {
  constructor(private readonly chatsService: ChatsService) {}

  @Get()
  async getMyChats(@Req() req: RequestWithUser) {
    return { chats: await this.chatsService.getMyChats(req.user.sub) };
  }

  @Get('direct/:userId')
  async getDirectChat(
    @Req() req: RequestWithUser,
    @Param('userId') userId: string,
  ) {
    return { chat: await this.chatsService.getDirectChat(req.user.sub, userId) };
  }

  @Post('direct/:userId')
  async getOrCreateDirectChat(
    @Req() req: RequestWithUser,
    @Param('userId') userId: string,
  ) {
    return this.chatsService.getOrCreateDirectChat(req.user.sub, userId);
  }

  @Get(':chatId/messages')
  async getMessages(
    @Req() req: RequestWithUser,
    @Param('chatId') chatId: string,
    @Query('after') after?: string,
  ) {
    return {
      messages: await this.chatsService.getMessages(
        req.user.sub,
        chatId,
        after,
      ),
    };
  }

  @Post(':chatId/messages')
  sendMessage(
    @Req() req: RequestWithUser,
    @Param('chatId') chatId: string,
    @Body() body: CreateMessageBody,
  ) {
    return this.chatsService.sendMessage(req.user.sub, chatId, body?.text);
  }
}
