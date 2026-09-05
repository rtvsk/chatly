import { Module } from '@nestjs/common';

import { AvatarsController } from './avatars.controller';
import { AvatarsService } from './avatars.service';
import { MinioService } from './minio.service';

@Module({
  controllers: [AvatarsController],
  providers: [AvatarsService, MinioService],
})
export class AvatarsModule {}
