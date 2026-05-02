import { Controller, Get, Req, UseGuards } from '@nestjs/common';

import { JwtAuthGuard } from 'src/auth/jwt-auth.guard';
import { ChatsService } from './chats.service';
import { Request } from 'express';

type RequestWithUser = Request & {
  user: {
    sub: string;
    login: string;
  };
};

@Controller('chats')
export class ChatsController {
  constructor(private readonly chatsService: ChatsService) {}

  @UseGuards(JwtAuthGuard)
  @Get()
  async getMyChats(@Req() req: RequestWithUser) {
    const userId = req.user.sub;

    console.log(`userId: `, userId);

    const chatIds = await this.chatsService.getMyChatIds(userId);

    return {
      chatIds,
    };
  }
}
