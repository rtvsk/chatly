import {
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Req,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Request } from 'express';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AvatarsService } from './avatars.service';
import type { AvatarUpload } from './avatars.service';

type RequestWithUser = Request & {
  user: {
    sub: string;
    login: string;
  };
};

@Controller('avatars')
@UseGuards(JwtAuthGuard)
export class AvatarsController {
  constructor(private readonly avatarsService: AvatarsService) {}

  @Get()
  list(@Req() req: RequestWithUser) {
    return this.avatarsService.list(req.user.sub);
  }

  @Post()
  @UseInterceptors(
    FileInterceptor('file', {
      limits: {
        files: 1,
        fileSize: 5 * 1024 * 1024,
      },
    }),
  )
  create(@Req() req: RequestWithUser, @UploadedFile() file?: AvatarUpload) {
    return this.avatarsService.create(req.user.sub, file);
  }

  @Get(':id/file')
  async getFile(@Req() req: RequestWithUser, @Param('id') id: string) {
    const { avatar, stream } = await this.avatarsService.getFile(
      req.user.sub,
      id,
    );

    return new StreamableFile(stream, {
      type: avatar.mimeType,
      length: avatar.size,
    });
  }

  @Patch(':id/select')
  select(@Req() req: RequestWithUser, @Param('id') id: string) {
    return this.avatarsService.select(req.user.sub, id);
  }

  @Delete(':id')
  remove(@Req() req: RequestWithUser, @Param('id') id: string) {
    return this.avatarsService.remove(req.user.sub, id);
  }
}
