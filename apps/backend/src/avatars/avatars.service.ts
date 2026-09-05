import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { and, desc, eq } from 'drizzle-orm';

import { DatabaseService } from '../database/database.service';
import { Avatar, avatars } from '../database/schema';
import { MinioService } from './minio.service';

export type AvatarUpload = {
  buffer: Buffer;
  originalname: string;
  size: number;
};

const avatarMimeTypes = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/heic': 'heic',
} as const;

@Injectable()
export class AvatarsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly minio: MinioService,
  ) {}

  async list(userId: string) {
    const result = await this.database.db
      .select()
      .from(avatars)
      .where(eq(avatars.userId, userId))
      .orderBy(desc(avatars.isSelected), desc(avatars.createdAt));

    return result.map((avatar) => this.toResponse(avatar));
  }

  async create(userId: string, file?: AvatarUpload) {
    if (!file || file.size === 0) {
      throw new BadRequestException('Avatar file is required');
    }

    const mimeType = this.detectMimeType(file.buffer);
    const extension = avatarMimeTypes[mimeType];
    const objectKey = `${userId}/${randomUUID()}.${extension}`;

    await this.minio.putObject(objectKey, file.buffer, file.size, mimeType);

    try {
      const avatar = await this.database.db.transaction(async (tx) => {
        const [existingAvatar] = await tx
          .select({ id: avatars.id })
          .from(avatars)
          .where(eq(avatars.userId, userId))
          .limit(1);

        const [createdAvatar] = await tx
          .insert(avatars)
          .values({
            userId,
            objectKey,
            originalName: file.originalname || `avatar.${extension}`,
            mimeType,
            size: file.size,
            isSelected: !existingAvatar,
          })
          .returning();

        return createdAvatar;
      });

      return this.toResponse(avatar);
    } catch (error) {
      await this.minio.removeObject(objectKey);
      throw error;
    }
  }

  async select(userId: string, avatarId: string) {
    const avatar = await this.findOwnedAvatar(userId, avatarId);

    await this.database.db.transaction(async (tx) => {
      await tx
        .update(avatars)
        .set({ isSelected: false })
        .where(eq(avatars.userId, userId));
      await tx
        .update(avatars)
        .set({ isSelected: true })
        .where(eq(avatars.id, avatar.id));
    });

    return this.toResponse({ ...avatar, isSelected: true });
  }

  async remove(userId: string, avatarId: string) {
    const avatar = await this.findOwnedAvatar(userId, avatarId);

    await this.minio.removeObject(avatar.objectKey);

    await this.database.db.transaction(async (tx) => {
      await tx.delete(avatars).where(eq(avatars.id, avatar.id));

      if (avatar.isSelected) {
        const [nextAvatar] = await tx
          .select({ id: avatars.id })
          .from(avatars)
          .where(eq(avatars.userId, userId))
          .orderBy(desc(avatars.createdAt))
          .limit(1);

        if (nextAvatar) {
          await tx
            .update(avatars)
            .set({ isSelected: true })
            .where(eq(avatars.id, nextAvatar.id));
        }
      }
    });

    return { id: avatar.id };
  }

  async getFile(userId: string, avatarId: string) {
    const avatar = await this.findOwnedAvatar(userId, avatarId);
    const stream = await this.minio.getObject(avatar.objectKey);

    return { avatar, stream };
  }

  private async findOwnedAvatar(userId: string, avatarId: string) {
    const [avatar] = await this.database.db
      .select()
      .from(avatars)
      .where(and(eq(avatars.id, avatarId), eq(avatars.userId, userId)))
      .limit(1);

    if (!avatar) {
      throw new NotFoundException('Avatar not found');
    }

    return avatar;
  }

  private toResponse(avatar: Avatar) {
    return {
      id: avatar.id,
      originalName: avatar.originalName,
      mimeType: avatar.mimeType,
      size: avatar.size,
      isSelected: avatar.isSelected,
      createdAt: avatar.createdAt,
      url: `/avatars/${avatar.id}/file`,
    };
  }

  private detectMimeType(buffer: Buffer): keyof typeof avatarMimeTypes {
    if (
      buffer.length >= 3 &&
      buffer[0] === 0xff &&
      buffer[1] === 0xd8 &&
      buffer[2] === 0xff
    ) {
      return 'image/jpeg';
    }

    if (
      buffer.length >= 8 &&
      buffer.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))
    ) {
      return 'image/png';
    }

    const signature = buffer.subarray(0, 6).toString('ascii');
    if (signature === 'GIF87a' || signature === 'GIF89a') {
      return 'image/gif';
    }

    if (
      buffer.length >= 12 &&
      buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
      buffer.subarray(8, 12).toString('ascii') === 'WEBP'
    ) {
      return 'image/webp';
    }

    if (buffer.length >= 12 && buffer.subarray(4, 8).toString() === 'ftyp') {
      const brand = buffer.subarray(8, 12).toString();
      if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(brand)) {
        return 'image/heic';
      }
    }

    throw new BadRequestException(
      'Only JPEG, PNG, GIF, WebP, and HEIC are allowed',
    );
  }
}
