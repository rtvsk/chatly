import { ConfigService } from '@nestjs/config';
import { INestApplicationContext } from '@nestjs/common';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';

import { RedisIoAdapter } from './redis-io.adapter';

jest.mock('redis', () => ({ createClient: jest.fn() }));
jest.mock('@socket.io/redis-adapter', () => ({ createAdapter: jest.fn() }));

describe('RedisIoAdapter', () => {
  const configService = {
    get: jest.fn((key: string) =>
      key === 'REDIS_HOST' ? 'localhost' : '6379',
    ),
  } as unknown as ConfigService;

  beforeEach(() => jest.clearAllMocks());

  it('connects dedicated Redis pub/sub clients and closes both on shutdown', async () => {
    const subClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      on: jest.fn(),
      quit: jest.fn().mockResolvedValue(undefined),
      isOpen: true,
    };
    const pubClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      duplicate: jest.fn().mockReturnValue(subClient),
      on: jest.fn(),
      quit: jest.fn().mockResolvedValue(undefined),
      isOpen: true,
    };
    jest.mocked(createClient).mockReturnValue(pubClient as never);
    jest.mocked(createAdapter).mockReturnValue(jest.fn() as never);
    const adapter = new RedisIoAdapter(
      {} as INestApplicationContext,
      configService,
    );

    await adapter.connectToRedis();
    await adapter.closeRedisClients();

    expect(createClient).toHaveBeenCalledWith({
      socket: { host: 'localhost', port: 6379 },
    });
    expect(pubClient.connect).toHaveBeenCalledTimes(1);
    expect(subClient.connect).toHaveBeenCalledTimes(1);
    expect(createAdapter).toHaveBeenCalledWith(pubClient, subClient);
    expect(pubClient.quit).toHaveBeenCalledTimes(1);
    expect(subClient.quit).toHaveBeenCalledTimes(1);
  });

  it('uses local Redis defaults when environment variables are absent', async () => {
    const subClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      on: jest.fn(),
      quit: jest.fn().mockResolvedValue(undefined),
      isOpen: true,
    };
    const pubClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      duplicate: jest.fn().mockReturnValue(subClient),
      on: jest.fn(),
      quit: jest.fn().mockResolvedValue(undefined),
      isOpen: true,
    };
    jest.mocked(createClient).mockReturnValue(pubClient as never);
    jest.mocked(createAdapter).mockReturnValue(jest.fn() as never);
    const adapter = new RedisIoAdapter(
      {} as INestApplicationContext,
      {
        get: jest.fn(),
      } as unknown as ConfigService,
    );

    await adapter.connectToRedis();

    expect(createClient).toHaveBeenCalledWith({
      socket: { host: 'localhost', port: 6379 },
    });
    await adapter.closeRedisClients();
  });

  it('rejects an invalid configured Redis port before connecting', async () => {
    const adapter = new RedisIoAdapter(
      {} as INestApplicationContext,
      {
        get: jest.fn((key: string) =>
          key === 'REDIS_HOST' ? 'localhost' : 'not-a-port',
        ),
      } as unknown as ConfigService,
    );

    await expect(adapter.connectToRedis()).rejects.toThrow(
      'REDIS_PORT must be a valid TCP port',
    );
    expect(createClient).not.toHaveBeenCalled();
  });
});
