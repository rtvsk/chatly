import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';

import { AuthModule } from './auth/auth.module';
import { User } from './users/user.entity';
import { RefreshToken } from './auth/refresh-token.entity';
import { LoggerMiddleware } from './common/middleware/logger.middleware';
import { ChatsModule } from './chats/chats.module';
import { Chat } from './chats/chat.entity';
import { ChatParticipant } from './chats/chat_participant.entity';
import { Message } from './messages/message.entity';
import { Friendship } from './friendships/friendship.entity';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),

    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        host: config.getOrThrow<string>('DATABASE_HOST'),
        port: Number(config.getOrThrow<string>('DATABASE_PORT')),
        username: config.getOrThrow<string>('DATABASE_USER'),
        password: config.getOrThrow<string>('DATABASE_PASSWORD'),
        database: config.getOrThrow<string>('DATABASE_NAME'),
        entities: [
          User,
          RefreshToken,
          Chat,
          ChatParticipant,
          Message,
          Friendship,
        ],
        synchronize: config.get<string>('NODE_ENV') === 'development',
      }),
    }),

    AuthModule,
    ChatsModule,
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggerMiddleware).forRoutes('*');
  }
}
