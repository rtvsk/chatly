import { Controller, UseGuards, Get, Query, Req } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UsersService } from './users.service';

type RequestWithUser = Request & {
  user: {
    sub: string;
    login: string;
  };
};

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @UseGuards(JwtAuthGuard)
  @Get('search')
  async searchByLogin(@Req() req: RequestWithUser, @Query('login') login = '') {
    return this.usersService.searchByLogin(login, req.user.sub);
  }
}
