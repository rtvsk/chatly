import { MODULE_METADATA } from '@nestjs/common/constants';
import { ConfigService } from '@nestjs/config';
import { ClientProxyFactory, Transport } from '@nestjs/microservices';

import { DEFAULT_MAIL_DLQ, DEFAULT_MAIL_QUEUE } from '@app/contracts';

import { AuthModule } from './auth.module';
import { MAIL_CLIENT } from './mail.publisher';

describe('AuthModule mail publisher', () => {
  it('declares the mail queue with the same DLQ arguments as the consumer', () => {
    const providers: unknown = Reflect.getMetadata(
      MODULE_METADATA.PROVIDERS,
      AuthModule,
    );
    if (!Array.isArray(providers)) {
      throw new Error('AuthModule providers metadata is missing');
    }
    const provider = (providers as unknown[]).find(
      (
        candidate,
      ): candidate is {
        provide: symbol;
        useFactory: (configService: ConfigService) => unknown;
      } =>
        typeof candidate === 'object' &&
        candidate !== null &&
        'provide' in candidate &&
        candidate.provide === MAIL_CLIENT &&
        'useFactory' in candidate &&
        typeof candidate.useFactory === 'function',
    );
    if (!provider) {
      throw new Error('Mail client provider is missing');
    }
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
        persistent: true,
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
