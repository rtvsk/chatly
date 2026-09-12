import { Module } from '@nestjs/common';

import { MailEventsController } from './mail-events.controller';
import { MailService } from './mail.service';
import { mailTransportProvider } from './mail-transporter.provider';

@Module({
  controllers: [MailEventsController],
  providers: [mailTransportProvider, MailService],
})
export class MailServiceModule {}
