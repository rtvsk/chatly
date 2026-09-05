import { Injectable, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Client } from 'minio';

@Injectable()
export class MinioService implements OnModuleInit {
  private readonly client: Client;
  readonly bucket: string;

  constructor(configService: ConfigService) {
    const endpoint = new URL(
      configService.get<string>('S3_ENDPOINT', 'http://localhost:9000'),
    );

    this.bucket = configService.get<string>(
      'S3_AVATARS_BUCKET',
      'chatly-avatars',
    );
    this.client = new Client({
      endPoint: endpoint.hostname,
      port: endpoint.port
        ? Number(endpoint.port)
        : endpoint.protocol === 'https:'
          ? 443
          : 80,
      useSSL: endpoint.protocol === 'https:',
      accessKey: configService.get<string>('S3_ACCESS_KEY', 'minioadmin'),
      secretKey: configService.get<string>('S3_SECRET_KEY', 'minioadmin'),
    });
  }

  async onModuleInit() {
    const exists = await this.client.bucketExists(this.bucket);

    if (!exists) {
      await this.client.makeBucket(this.bucket);
    }
  }

  putObject(objectKey: string, data: Buffer, size: number, mimeType: string) {
    return this.client.putObject(this.bucket, objectKey, data, size, {
      'Content-Type': mimeType,
    });
  }

  getObject(objectKey: string) {
    return this.client.getObject(this.bucket, objectKey);
  }

  removeObject(objectKey: string) {
    return this.client.removeObject(this.bucket, objectKey);
  }
}
