import { Module } from '@nestjs/common';

import { FriendshipRealtimePublisher } from './friendship-realtime.publisher';

@Module({
  providers: [FriendshipRealtimePublisher],
  exports: [FriendshipRealtimePublisher],
})
export class RealtimeModule {}
