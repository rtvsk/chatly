import { Controller, UseGuards, Get, Query } from '@nestjs/common';
import { JwtAuthGuard } from 'src/auth/jwt-auth.guard';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @UseGuards(JwtAuthGuard)
  @Get('search')
  async searchByLogin(@Query('login') login: string) {
    const user = await this.usersService.findByLogin(login);

    if (!user) {
      return null;
    }

    return user;
  }
}
