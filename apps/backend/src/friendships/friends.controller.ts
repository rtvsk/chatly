import { Controller, UseGuards, Post, Req, Param, Get } from '@nestjs/common';
import { JwtAuthGuard } from 'src/auth/jwt-auth.guard';
import { FriendsService } from './friends.service';

type RequestWithUser = Request & {
  user: {
    sub: string;
    login: string;
  };
};

@Controller('friends')
export class FriendsController {
  constructor(private readonly friendsService: FriendsService) {}

  @UseGuards(JwtAuthGuard)
  @Post('request/:receiverId')
  async sendRequest(
    @Req() req: RequestWithUser,
    @Param('receiverId') receiverId: string,
  ) {
    return this.friendsService.sendRequest(req.user.sub, receiverId);
  }

  @UseGuards(JwtAuthGuard)
  @Post('accept/:friendshipId')
  async acceptRequest(
    @Req() req: RequestWithUser,
    @Param('friendshipId') friendshipId: string,
  ) {
    return this.friendsService.acceptRequest(req.user.sub, friendshipId);
  }

  @UseGuards(JwtAuthGuard)
  @Get()
  async getMyFriends(@Req() req: RequestWithUser) {
    return this.friendsService.getMyFriends(req.user.sub);
  }
}
