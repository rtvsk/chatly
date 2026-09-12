import { Module } from '@nestjs/common';

import { MailEventsController } from './mail-events.controller';
import { MailService } from './mail.service';

@Module({
  controllers: [MailEventsController],
  providers: [MailService],
})
export class MailServiceModule {}
