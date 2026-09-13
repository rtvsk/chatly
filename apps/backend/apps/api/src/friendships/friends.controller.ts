import {
  Controller,
  UseGuards,
  Post,
  Req,
  Param,
  Get,
  Delete,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
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
  @Post('reject/:friendshipId')
  async rejectRequest(
    @Req() req: RequestWithUser,
    @Param('friendshipId') friendshipId: string,
  ) {
    return this.friendsService.rejectRequest(req.user.sub, friendshipId);
  }

  @UseGuards(JwtAuthGuard)
  @Delete(':userId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async removeFriend(
    @Req() req: RequestWithUser,
    @Param('userId') userId: string,
  ) {
    await this.friendsService.removeFriend(req.user.sub, userId);
  }

  @UseGuards(JwtAuthGuard)
  @Get('requests')
  async getIncomingRequests(@Req() req: RequestWithUser) {
    return this.friendsService.getIncomingRequests(req.user.sub);
  }

  @UseGuards(JwtAuthGuard)
  @Get('status/:userId')
  async getFriendshipStatus(
    @Req() req: RequestWithUser,
    @Param('userId') userId: string,
  ) {
    return this.friendsService.getFriendshipStatus(req.user.sub, userId);
  }

  @UseGuards(JwtAuthGuard)
  @Get()
  async getMyFriends(@Req() req: RequestWithUser) {
    return this.friendsService.getMyFriends(req.user.sub);
  }
}
