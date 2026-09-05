import { BadRequestException } from '@nestjs/common';

import { DatabaseService } from '../database/database.service';
import { MinioService } from './minio.service';
import { AvatarsService } from './avatars.service';

describe('AvatarsService', () => {
  const userId = '75e92735-8e2c-4aeb-86f7-f57ecc780d60';

  it('rejects a file that is not a supported image', async () => {
    const minio = {
      putObject: jest.fn(),
      removeObject: jest.fn(),
    };
    const service = new AvatarsService(
      { db: {} } as DatabaseService,
      minio as unknown as MinioService,
    );

    await expect(
      service.create(userId, {
        buffer: Buffer.from('not an image'),
        originalname: 'avatar.txt',
        size: 12,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(minio.putObject).not.toHaveBeenCalled();
  });

  it('stores the first avatar in MinIO and marks it as selected', async () => {
    const createdAt = new Date('2026-09-05T12:00:00.000Z');
    const selectBuilder = {
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue([]),
    };
    const values = jest.fn().mockImplementation((data) => ({
      returning: jest.fn().mockResolvedValue([
        {
          id: 'avatar-id',
          createdAt,
          ...data,
        },
      ]),
    }));
    const transactionClient = {
      select: jest.fn().mockReturnValue(selectBuilder),
      insert: jest.fn().mockReturnValue({ values }),
    };
    const transaction = jest
      .fn()
      .mockImplementation(
        (callback: (client: typeof transactionClient) => Promise<unknown>) =>
          callback(transactionClient),
      );
    const minio = {
      putObject: jest.fn().mockResolvedValue(undefined),
      removeObject: jest.fn().mockResolvedValue(undefined),
    };
    const service = new AvatarsService(
      { db: { transaction } } as unknown as DatabaseService,
      minio as unknown as MinioService,
    );
    const png = Buffer.from('89504e470d0a1a0a', 'hex');

    const result = await service.create(userId, {
      buffer: png,
      originalname: 'me.png',
      size: png.length,
    });

    expect(minio.putObject).toHaveBeenCalledWith(
      expect.stringMatching(new RegExp(`^${userId}/.+\\.png$`)),
      png,
      png.length,
      'image/png',
    );
    expect(values).toHaveBeenCalledWith(
      expect.objectContaining({
        userId,
        originalName: 'me.png',
        mimeType: 'image/png',
        isSelected: true,
      }),
    );
    expect(result).toEqual(
      expect.objectContaining({
        id: 'avatar-id',
        isSelected: true,
        url: '/avatars/avatar-id/file',
      }),
    );
  });
});
