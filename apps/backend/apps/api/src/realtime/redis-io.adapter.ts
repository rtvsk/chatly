import { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { ConfigService } from '@nestjs/config';
import { createClient } from 'redis';
import { Server, ServerOptions } from 'socket.io';

export class RedisIoAdapter extends IoAdapter {
  private pubClient?: ReturnType<typeof createClient>;
  private subClient?: ReturnType<typeof createClient>;
  private adapterConstructor?: ReturnType<typeof createAdapter>;

  constructor(
    app: INestApplicationContext,
    private readonly configService: ConfigService,
  ) {
    super(app);
  }

  async connectToRedis(): Promise<void> {
    const host =
      this.configService.get<string>('REDIS_HOST')?.trim() || 'localhost';
    const portValue = this.configService.get<string>('REDIS_PORT')?.trim();
    const port = portValue ? Number(portValue) : 6379;
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      throw new TypeError('REDIS_PORT must be a valid TCP port');
    }
    const pubClient = createClient({ socket: { host, port } });
    const subClient = pubClient.duplicate();
    // node-redis requires an error listener even though connection failures
    // are propagated by connect() and abort API startup below.
    pubClient.on('error', () => undefined);
    subClient.on('error', () => undefined);

    try {
      await Promise.all([pubClient.connect(), subClient.connect()]);
    } catch (error) {
      await Promise.allSettled([pubClient.quit(), subClient.quit()]);
      throw error;
    }

    this.pubClient = pubClient;
    this.subClient = subClient;
    this.adapterConstructor = createAdapter(pubClient, subClient);
  }

  override createIOServer(port: number, options?: ServerOptions): Server {
    if (!this.adapterConstructor) {
      throw new Error('Redis Socket.IO adapter has not been connected');
    }

    const server = super.createIOServer(port, {
      ...options,
      transports: ['websocket'],
    }) as Server;
    server.adapter(this.adapterConstructor);
    return server;
  }

  override async close(server: Server): Promise<void> {
    await super.close(server);
    await this.closeRedisClients();
  }

  async closeRedisClients(): Promise<void> {
    const clients = [this.pubClient, this.subClient].filter(
      (client): client is ReturnType<typeof createClient> =>
        client !== undefined,
    );
    this.pubClient = undefined;
    this.subClient = undefined;
    this.adapterConstructor = undefined;

    await Promise.all(
      clients.map((client) =>
        client.isOpen ? client.quit() : Promise.resolve(),
      ),
    );
  }
}
