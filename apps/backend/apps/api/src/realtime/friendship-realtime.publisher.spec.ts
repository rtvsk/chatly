import { FriendshipRealtimePublisher } from './friendship-realtime.publisher';
import { userRoom } from './user-room';

describe('FriendshipRealtimePublisher', () => {
  it('publishes each friendship change to every distinct participant room', () => {
    const publisher = new FriendshipRealtimePublisher();
    const emit = jest.fn();
    const to = jest.fn().mockReturnValue({ emit });
    publisher.setServer({ to } as never);

    publisher.publishFriendshipChanged(['first', 'second', 'first'], {
      type: 'request_accepted',
    });

    expect(to).toHaveBeenCalledTimes(2);
    expect(to).toHaveBeenNthCalledWith(1, userRoom('first'));
    expect(to).toHaveBeenNthCalledWith(2, userRoom('second'));
    expect(emit).toHaveBeenCalledWith('friendship.changed', {
      type: 'request_accepted',
    });
  });

  it('does not throw when Socket.IO is unavailable or emitting fails', () => {
    const publisher = new FriendshipRealtimePublisher();
    (publisher as unknown as { logger: { warn: jest.Mock } }).logger = {
      warn: jest.fn(),
    };

    expect(() =>
      publisher.publishFriendshipChanged(['first'], { type: 'friend_removed' }),
    ).not.toThrow();

    publisher.setServer({
      to: jest.fn(() => {
        throw new Error('Socket.IO unavailable');
      }),
    } as never);

    expect(() =>
      publisher.publishFriendshipChanged(['first'], { type: 'friend_removed' }),
    ).not.toThrow();
  });
});
