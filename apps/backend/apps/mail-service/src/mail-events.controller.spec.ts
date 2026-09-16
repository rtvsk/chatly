import type { RmqContext } from '@nestjs/microservices';
import type { ConsumeMessage, Options } from 'amqplib';
import { MAIL_RETRY_HEADER, type MailSendEvent } from '@app/contracts';

import { MailEventsController } from './mail-events.controller';
import { MailService } from './mail.service';

describe('MailEventsController', () => {
  const event: MailSendEvent = {
    eventId: 'event-1',
    to: 'recipient@example.com',
    template: 'email-verification',
    expiresAt: new Date(Date.now() + 60_000).toISOString(),
    subject: 'Confirm email',
    context: {
      verificationUrl: 'https://chatly.test/verify-email?token=token',
    },
  };

  let process: jest.MockedFunction<MailService['process']>;
  let ack: jest.Mock;
  let nack: jest.Mock;
  let sendToQueue: jest.MockedFunction<
    (
      queue: string,
      content: Buffer,
      options?: Options.Publish,
    ) => Promise<boolean>
  >;
  let message: ConsumeMessage;
  let context: RmqContext;
  let controller: MailEventsController;

  beforeEach(() => {
    process = jest.fn();
    ack = jest.fn();
    nack = jest.fn();
    sendToQueue = jest
      .fn<
        (
          queue: string,
          content: Buffer,
          options?: Options.Publish,
        ) => Promise<boolean>
      >()
      .mockResolvedValue(true);
    message = {
      content: Buffer.from('{}'),
      properties: { headers: {} },
    } as ConsumeMessage;
    context = {
      getChannelRef: () => ({ ack, nack, sendToQueue }),
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

  it('dead-letters a verification event without its required URL', async () => {
    await controller.handleMailSend(
      {
        eventId: 'event-2',
        to: 'recipient@example.com',
        template: 'email-verification',
        expiresAt: new Date(Date.now() + 60_000).toISOString(),
        context: {},
      },
      context,
    );

    expect(process).not.toHaveBeenCalled();
    expect(ack).not.toHaveBeenCalled();
    expect(nack).toHaveBeenCalledWith(message, false, false);
  });

  it('publishes a failed event to the first retry queue before acking it', async () => {
    process.mockRejectedValue(new Error('provider unavailable'));

    await controller.handleMailSend(event, context);

    const [queue, content, options] = sendToQueue.mock.calls[0];
    expect(queue).toBe('mail.events.retry.10000');
    expect(content).toBe(message.content);
    expect(options?.persistent).toBe(true);
    expect(options?.headers).toMatchObject({ [MAIL_RETRY_HEADER]: 1 });
    expect(ack).toHaveBeenCalledWith(message);
    expect(nack).not.toHaveBeenCalled();
  });

  it('dead-letters an event after all retry attempts fail', async () => {
    process.mockRejectedValue(new Error('provider unavailable'));
    message.properties.headers = { [MAIL_RETRY_HEADER]: 3 };

    await controller.handleMailSend(event, context);

    expect(sendToQueue).not.toHaveBeenCalled();
    expect(ack).not.toHaveBeenCalled();
    expect(nack).toHaveBeenCalledWith(message, false, false);
  });

  it('requeues the original event when retry publication fails', async () => {
    process.mockRejectedValue(new Error('provider unavailable'));
    sendToQueue.mockRejectedValue(new Error('rabbit unavailable'));

    await controller.handleMailSend(event, context);

    expect(ack).not.toHaveBeenCalled();
    expect(nack).toHaveBeenCalledWith(message, false, true);
  });

  it('dead-letters an expired verification event without sending it', async () => {
    const expired = {
      ...event,
      expiresAt: new Date(Date.now() - 1).toISOString(),
    };

    await controller.handleMailSend(expired, context);

    expect(process).not.toHaveBeenCalled();
    expect(nack).toHaveBeenCalledWith(message, false, false);
  });
});
