import { HttpException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';

import { DatabaseService } from '../database/database.service';
import type { User } from '../database/schema';
import { OutboxDispatcherService } from './outbox-dispatcher.service';
import { AuthService } from './auth.service';

const user = (overrides: Partial<User> = {}): User => ({
  id: 'd4ceea5b-b1df-4603-b617-f49ed039e2a2',
  login: 'alice',
  email: 'alice@example.com',
  isVerified: false,
  passwordHash: '',
  createdAt: new Date(),
  updatedAt: new Date(),
  ...overrides,
});

const selectReturning = (result: unknown[]) => {
  const query = {
    from: jest.fn(),
    where: jest.fn(),
    limit: jest.fn(),
  };
  query.from.mockReturnValue(query);
  query.where.mockReturnValue(query);
  query.limit.mockResolvedValue(result);
  return query;
};

const verificationSelectReturning = (result: unknown[]) => {
  const query = {
    from: jest.fn(),
    innerJoin: jest.fn(),
    where: jest.fn(),
    limit: jest.fn(),
  };
  query.from.mockReturnValue(query);
  query.innerJoin.mockReturnValue(query);
  query.where.mockReturnValue(query);
  query.limit.mockResolvedValue(result);
  return query;
};

describe('AuthService', () => {
  const config = {
    getOrThrow: jest.fn((key: string) => {
      const values: Record<string, string> = {
        EMAIL_VERIFICATION_BASE_URL: 'https://chatly.test/auth/verify-email',
        JWT_ACCESS_SECRET: 'access-secret',
        JWT_ACCESS_EXPIRES_IN: '900',
        JWT_REFRESH_SECRET: 'refresh-secret',
        JWT_REFRESH_EXPIRES_IN: '2592000',
      };
      return values[key];
    }),
  } as unknown as ConfigService;

  it('does not issue tokens to an unverified user with valid credentials', async () => {
    const passwordHash = await bcrypt.hash('correct-password', 4);
    const query = selectReturning([user({ passwordHash })]);
    const database = {
      db: { select: jest.fn(() => query) },
    } as unknown as DatabaseService;
    const signAsync = jest.fn();
    const jwt = { signAsync } as unknown as JwtService;
    const service = new AuthService(
      database,
      jwt,
      config,
      {} as OutboxDispatcherService,
    );

    await expect(
      service.signin({ login: 'alice', password: 'correct-password' }),
    ).rejects.toMatchObject({
      status: 403,
      response: {
        code: 'EMAIL_NOT_VERIFIED',
        email: 'alice@example.com',
      },
    } satisfies Partial<HttpException>);
    expect(signAsync).not.toHaveBeenCalled();
  });

  it('atomically creates signup state and reports pending delivery', async () => {
    const existingUserQuery = selectReturning([]);
    const createdUser = user();
    const createUser = {
      returning: jest.fn().mockResolvedValue([createdUser]),
    };
    const insertToken = { values: jest.fn().mockResolvedValue(undefined) };
    const insertOutbox = { values: jest.fn().mockResolvedValue(undefined) };
    const transactionInsert = jest
      .fn()
      .mockReturnValueOnce({ values: jest.fn(() => createUser) })
      .mockReturnValueOnce(insertToken)
      .mockReturnValueOnce(insertOutbox);
    const transaction = jest.fn(
      (
        callback: (tx: { insert: jest.Mock }) => Promise<{
          user: User;
          outboxEventId: string;
        }>,
      ) => callback({ insert: transactionInsert }),
    );
    const database = {
      db: {
        select: jest.fn(() => existingUserQuery),
        transaction,
      },
    } as unknown as DatabaseService;
    const dispatchNow = jest.fn().mockRejectedValue(new Error('offline'));
    const dispatcher = { dispatchNow } as unknown as OutboxDispatcherService;
    const service = new AuthService(
      database,
      {} as JwtService,
      config,
      dispatcher,
    );

    await expect(
      service.signup({
        login: 'alice',
        email: ' Alice@Example.COM ',
        password: 'password',
        repeatPassword: 'password',
      }),
    ).resolves.toMatchObject({
      status: 'verification_required',
      delivery: 'pending',
      user: { email: 'alice@example.com', isVerified: false },
    });
    expect(transaction).toHaveBeenCalledTimes(1);
    const tokenCalls = insertToken.values.mock.calls as unknown as [
      [{ userId: string }],
    ];
    const outboxCalls = insertOutbox.values.mock.calls as unknown as [
      [
        {
          id: string;
          topic: string;
          payload: { to: string; template: string; expiresAt: string };
        },
      ],
    ];
    const tokenValues = tokenCalls[0][0];
    const outboxValues = outboxCalls[0][0];
    expect(tokenValues.userId).toBe(createdUser.id);
    expect(outboxValues.topic).toBe('mail.send');
    expect(outboxValues.payload).toMatchObject({
      to: 'alice@example.com',
      template: 'email-verification',
    });
    expect(new Date(outboxValues.payload.expiresAt).getTime()).not.toBeNaN();
    expect(dispatchNow).toHaveBeenCalledWith(outboxValues.id);
  });

  it('marks a valid verification token as used and verifies its user', async () => {
    const query = verificationSelectReturning([
      {
        token: { id: 'token-1', expiresAt: new Date(Date.now() + 60_000) },
        user: user(),
      },
    ]);
    const where = jest.fn().mockResolvedValue(undefined);
    const update = jest.fn(() => ({ set: jest.fn(() => ({ where })) }));
    const transaction = jest.fn(
      (callback: (tx: { update: typeof update }) => Promise<void>) =>
        callback({ update }),
    );
    const database = {
      db: { select: jest.fn(() => query), transaction },
    } as unknown as DatabaseService;
    const service = new AuthService(
      database,
      {} as JwtService,
      config,
      {} as OutboxDispatcherService,
    );

    await expect(service.verifyEmail('valid-token')).resolves.toEqual({
      verified: true,
    });
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(update).toHaveBeenCalledTimes(2);
  });

  it('rejects an expired verification token without mutating the user', async () => {
    const query = verificationSelectReturning([
      {
        token: { id: 'token-1', expiresAt: new Date(Date.now() - 60_000) },
        user: user(),
      },
    ]);
    const transaction = jest.fn();
    const database = {
      db: { select: jest.fn(() => query), transaction },
    } as unknown as DatabaseService;
    const service = new AuthService(
      database,
      {} as JwtService,
      config,
      {} as OutboxDispatcherService,
    );

    await expect(service.verifyEmail('expired-token')).resolves.toEqual({
      verified: false,
    });
    expect(transaction).not.toHaveBeenCalled();
  });

  it('accepts a reused token for an already verified user', async () => {
    const query = verificationSelectReturning([
      {
        token: { id: 'token-1', expiresAt: new Date(Date.now() - 60_000) },
        user: user({ isVerified: true }),
      },
    ]);
    const transaction = jest.fn();
    const database = {
      db: { select: jest.fn(() => query), transaction },
    } as unknown as DatabaseService;
    const service = new AuthService(
      database,
      {} as JwtService,
      config,
      {} as OutboxDispatcherService,
    );

    await expect(service.verifyEmail('used-token')).resolves.toEqual({
      verified: true,
    });
    expect(transaction).not.toHaveBeenCalled();
  });
});
