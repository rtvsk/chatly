import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { ClientProxyFactory, Transport } from '@nestjs/microservices';
import { DEFAULT_MAIL_DLQ, DEFAULT_MAIL_QUEUE } from '@app/contracts';

import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { PassportModule } from '@nestjs/passport';
import { JwtStrategy } from './jwt.strategy';
import { MAIL_CLIENT, MailPublisher } from './mail.publisher';

@Module({
  imports: [PassportModule, JwtModule.register({})],
  controllers: [AuthController],
  providers: [
    AuthService,
    JwtStrategy,
    MailPublisher,
    {
      provide: MAIL_CLIENT,
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const deadLetterQueue =
          configService.get<string>('MAIL_DLQ') ?? DEFAULT_MAIL_DLQ;

        return ClientProxyFactory.create({
          transport: Transport.RMQ,
          options: {
            urls: [configService.getOrThrow<string>('RABBITMQ_URL')],
            queue:
              configService.get<string>('MAIL_QUEUE') ?? DEFAULT_MAIL_QUEUE,
            queueOptions: {
              durable: true,
              arguments: {
                'x-dead-letter-exchange': '',
                'x-dead-letter-routing-key': deadLetterQueue,
              },
            },
          },
        });
      },
    },
  ],
  exports: [AuthService],
})
export class AuthModule {}
