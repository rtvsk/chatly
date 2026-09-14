import { Injectable, Logger } from '@nestjs/common';
import { Server } from 'socket.io';

import { userRoom } from './user-room';

export type FriendshipChangedEvent = {
  type:
    | 'request_created'
    | 'request_accepted'
    | 'request_rejected'
    | 'friend_removed';
};

@Injectable()
export class FriendshipRealtimePublisher {
  private readonly logger = new Logger(FriendshipRealtimePublisher.name);
  private server?: Server;

  setServer(server: Server): void {
    this.server = server;
  }

  publishFriendshipChanged(
    participantIds: readonly string[],
    event: FriendshipChangedEvent,
  ): void {
    if (!this.server) {
      this.logger.warn(
        'Unable to publish friendship change: server unavailable',
      );
      return;
    }

    try {
      for (const participantId of new Set(participantIds)) {
        this.server
          .to(userRoom(participantId))
          .emit('friendship.changed', event);
      }
    } catch {
      this.logger.warn('Unable to publish friendship change');
    }
  }
}
