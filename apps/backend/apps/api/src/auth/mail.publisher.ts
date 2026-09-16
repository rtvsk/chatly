import { Inject, Injectable } from '@nestjs/common';
import type { ClientProxy } from '@nestjs/microservices';
import { lastValueFrom } from 'rxjs';
import { MAIL_SEND_PATTERN, type MailSendEvent } from '@app/contracts';

export const MAIL_CLIENT = Symbol('MAIL_CLIENT');

@Injectable()
export class MailPublisher {
  constructor(@Inject(MAIL_CLIENT) private readonly client: ClientProxy) {}

  async publish(event: MailSendEvent): Promise<void> {
    await lastValueFrom(this.client.emit(MAIL_SEND_PATTERN, event));
  }
}
