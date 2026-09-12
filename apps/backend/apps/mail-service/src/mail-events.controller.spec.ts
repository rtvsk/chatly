import type { RmqContext } from '@nestjs/microservices';
import type { Channel, ConsumeMessage } from 'amqplib';
import type { MailSendEvent } from '@app/contracts';

import { MailEventsController } from './mail-events.controller';
import { MailService } from './mail.service';

describe('MailEventsController', () => {
  const event: MailSendEvent = {
    eventId: 'event-1',
    to: 'recipient@example.com',
    template: 'welcome',
    subject: 'Welcome',
    context: { displayName: 'Recipient' },
  };

  let process: jest.MockedFunction<MailService['process']>;
  let ack: jest.Mock;
  let nack: jest.Mock;
  let message: ConsumeMessage;
  let context: RmqContext;
  let controller: MailEventsController;

  beforeEach(() => {
    process = jest.fn();
    ack = jest.fn();
    nack = jest.fn();
    message = {} as ConsumeMessage;
    context = {
      getChannelRef: () => ({ ack, nack }) as unknown as Channel,
      getMessage: () => message,
    } as unknown as RmqContext;
    controller = new MailEventsController({ process } as MailService);
  });

  it('processes and acknowledges a valid event', async () => {
    await controller.handleMailSend(event, context);

    expect(process).toHaveBeenCalledWith(event);
    expect(ack).toHaveBeenCalledWith(message);
    expect(nack).not.toHaveBeenCalled();
  });

  it('dead-letters an invalid event without processing it', async () => {
    await controller.handleMailSend({ eventId: 'event-1' }, context);

    expect(process).not.toHaveBeenCalled();
    expect(ack).not.toHaveBeenCalled();
    expect(nack).toHaveBeenCalledWith(message, false, false);
  });

  it('dead-letters an event when processing fails', async () => {
    process.mockRejectedValue(new Error('provider unavailable'));

    await controller.handleMailSend(event, context);

    expect(ack).not.toHaveBeenCalled();
    expect(nack).toHaveBeenCalledWith(message, false, false);
  });
});
