import { MODULE_METADATA } from '@nestjs/common/constants';
import { ConfigService } from '@nestjs/config';
import { ClientProxyFactory, Transport } from '@nestjs/microservices';

import { DEFAULT_MAIL_DLQ, DEFAULT_MAIL_QUEUE } from '@app/contracts';

import { AuthModule } from './auth.module';
import { MAIL_CLIENT } from './mail.publisher';

describe('AuthModule mail publisher', () => {
  it('declares the mail queue with the same DLQ arguments as the consumer', () => {
    const providers = Reflect.getMetadata(
      MODULE_METADATA.PROVIDERS,
      AuthModule,
    );
    const provider = providers.find(
      (candidate: { provide?: symbol }) => candidate.provide === MAIL_CLIENT,
    ) as {
      useFactory: (configService: ConfigService) => unknown;
    };
    const create = jest
      .spyOn(ClientProxyFactory, 'create')
      .mockReturnValue({} as ReturnType<typeof ClientProxyFactory.create>);
    const config = {
      getOrThrow: jest.fn(() => 'amqp://example.test'),
      get: jest.fn(() => undefined),
    } as unknown as ConfigService;

    provider.useFactory(config);

    expect(create).toHaveBeenCalledWith({
      transport: Transport.RMQ,
      options: {
        urls: ['amqp://example.test'],
        queue: DEFAULT_MAIL_QUEUE,
        queueOptions: {
          durable: true,
          arguments: {
            'x-dead-letter-exchange': '',
            'x-dead-letter-routing-key': DEFAULT_MAIL_DLQ,
          },
        },
      },
    });
  });
});
