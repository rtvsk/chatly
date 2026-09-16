import {
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { MAIL_SEND_PATTERN } from '@app/contracts';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes, randomUUID } from 'crypto';
import { and, eq, gt, lt, or, sql } from 'drizzle-orm';

import { DatabaseService } from '../database/database.service';
import {
  emailVerificationTokens,
  outboxEvents,
  refreshTokens,
  type User,
  users,
} from '../database/schema';
import { ResendVerificationDto } from './dto/resend-verification.dto';
import { SigninDto } from './dto/signin.dto';
import { SignupDto } from './dto/signup.dto';
import { OutboxDispatcherService } from './outbox-dispatcher.service';

const EMAIL_NOT_VERIFIED = 'EMAIL_NOT_VERIFIED';
const TOKEN_LIFETIME_MS = 24 * 60 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;

@Injectable()
export class AuthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly outboxDispatcher: OutboxDispatcherService,
  ) {}

  async signup(dto: SignupDto) {
    if (dto.password !== dto.repeatPassword) {
      throw new BadRequestException('Passwords do not match');
    }

    const email = this.normalizeEmail(dto.email);
    const [existingUser] = await this.database.db
      .select({ id: users.id })
      .from(users)
      .where(
        or(eq(users.login, dto.login), sql`lower(${users.email}) = ${email}`),
      )
      .limit(1);

    if (existingUser) {
      throw new ConflictException('User already exists');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);
    let user: User;
    let outboxEventId: string;

    try {
      ({ user, outboxEventId } = await this.database.db.transaction(
        async (tx) => {
          const [createdUser] = await tx
            .insert(users)
            .values({
              login: dto.login,
              email,
              passwordHash,
              isVerified: false,
            })
            .returning();
          const verification = this.buildVerification(createdUser);
          await tx.insert(emailVerificationTokens).values(verification.token);
          await tx.insert(outboxEvents).values(verification.outbox);
          return {
            user: createdUser,
            outboxEventId: verification.outbox.id,
          };
        },
      ));
    } catch (error) {
      if (this.isUniqueViolation(error)) {
        throw new ConflictException('User already exists');
      }

      throw error;
    }

    let delivery: 'sent' | 'pending' = 'pending';
    try {
      if (await this.outboxDispatcher.dispatchNow(outboxEventId)) {
        delivery = 'sent';
      }
    } catch {
      // The committed outbox row remains available to the background poller.
    }

    return {
      status: 'verification_required' as const,
      user: {
        id: user.id,
        login: user.login,
        email,
        isVerified: false,
      },
      delivery,
    };
  }

  async signin(dto: SigninDto) {
    const [user] = await this.database.db
      .select()
      .from(users)
      .where(eq(users.login, dto.login))
      .limit(1);

    if (!user) {
      console.log('!user');
      throw new UnauthorizedException('Invalid credentials');
    }

    const passwordValid = await bcrypt.compare(dto.password, user.passwordHash);

    if (!passwordValid) {
      console.log('!passwordValid');
      throw new UnauthorizedException('Invalid credentials');
    }

    this.assertVerified(user);
    return this.issueTokens(user);
  }

  async refresh(refreshToken: string) {
    let payload: { sub: string };

    try {
      payload = await this.jwtService.verifyAsync(refreshToken, {
        secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('Invalid refresh token');
    }

    const [user] = await this.database.db
      .select()
      .from(users)
      .where(eq(users.id, payload.sub))
      .limit(1);

    if (!user) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    this.assertVerified(user);

    const [storedToken] = await this.database.db
      .select()
      .from(refreshTokens)
      .where(eq(refreshTokens.userId, user.id))
      .limit(1);

    if (!storedToken) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    const isMatch = await bcrypt.compare(refreshToken, storedToken.tokenHash);

    if (!isMatch) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    if (storedToken.expiresAt < new Date()) {
      await this.database.db
        .delete(refreshTokens)
        .where(eq(refreshTokens.userId, user.id));

      throw new UnauthorizedException('Refresh token expired');
    }

    return this.issueTokens(user);
  }

  async verifyEmail(token: string) {
    const digest = this.digestToken(token);
    const [record] = await this.database.db
      .select({ token: emailVerificationTokens, user: users })
      .from(emailVerificationTokens)
      .innerJoin(users, eq(emailVerificationTokens.userId, users.id))
      .where(eq(emailVerificationTokens.tokenDigest, digest))
      .limit(1);

    if (!record) {
      return { verified: false as const };
    }

    if (record.user.isVerified) {
      return { verified: true as const };
    }

    if (record.token.expiresAt < new Date()) {
      return { verified: false as const };
    }

    const now = new Date();

    await this.database.db.transaction(async (tx) => {
      await tx
        .update(users)
        .set({ isVerified: true, updatedAt: now })
        .where(eq(users.id, record.user.id));
      await tx
        .update(emailVerificationTokens)
        .set({ usedAt: now })
        .where(eq(emailVerificationTokens.id, record.token.id));
    });

    return { verified: true as const };
  }

  async resendVerification(dto: ResendVerificationDto): Promise<void> {
    let email: string;

    try {
      email = this.normalizeEmail(dto.email);
    } catch {
      return;
    }

    const outboxEventId = await this.database.db.transaction(async (tx) => {
      const lockedUser = await tx.execute(sql`
        SELECT "id", "email"
        FROM "users"
        WHERE lower("email") = ${email} AND "isVerified" = false
        LIMIT 1
        FOR UPDATE
      `);
      const user = lockedUser.rows[0] as Pick<User, 'id' | 'email'> | undefined;

      if (!user) {
        return undefined;
      }

      const now = new Date();
      await tx
        .delete(emailVerificationTokens)
        .where(
          and(
            eq(emailVerificationTokens.userId, user.id),
            lt(emailVerificationTokens.expiresAt, now),
          ),
        );

      const [recentToken] = await tx
        .select({ id: emailVerificationTokens.id })
        .from(emailVerificationTokens)
        .where(
          and(
            eq(emailVerificationTokens.userId, user.id),
            gt(
              emailVerificationTokens.createdAt,
              new Date(now.getTime() - RESEND_COOLDOWN_MS),
            ),
          ),
        )
        .limit(1);

      if (recentToken) {
        return undefined;
      }

      const verification = this.buildVerification(user);
      await tx.insert(emailVerificationTokens).values(verification.token);
      await tx.insert(outboxEvents).values(verification.outbox);
      return verification.outbox.id;
    });

    if (outboxEventId) {
      try {
        await this.outboxDispatcher.dispatchNow(outboxEventId);
      } catch {
        // The resend endpoint deliberately does not reveal delivery failures.
      }
    }
  }

  private buildVerification(user: Pick<User, 'id' | 'email'>) {
    if (!user.email) {
      throw new Error('Verification email is required');
    }

    const rawToken = randomBytes(32).toString('base64url');
    const verificationUrl = new URL(
      this.configService.getOrThrow<string>('EMAIL_VERIFICATION_BASE_URL'),
    );
    verificationUrl.searchParams.set('token', rawToken);
    const expiresAt = new Date(Date.now() + TOKEN_LIFETIME_MS);
    const eventId = randomUUID();
    const expiresAtIso = expiresAt.toISOString();

    return {
      token: {
        userId: user.id,
        tokenDigest: this.digestToken(rawToken),
        expiresAt,
      },
      outbox: {
        id: eventId,
        topic: MAIL_SEND_PATTERN,
        expiresAt,
        payload: {
          eventId,
          to: user.email,
          template: 'email-verification',
          expiresAt: expiresAtIso,
          context: { verificationUrl: verificationUrl.toString() },
        },
      },
    };
  }

  private normalizeEmail(value: string): string {
    const email = typeof value === 'string' ? value.trim().toLowerCase() : '';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new BadRequestException('A valid email address is required');
    }

    return email;
  }

  private digestToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private assertVerified(user: User): void {
    if (!user.isVerified) {
      throw new HttpException(
        {
          code: EMAIL_NOT_VERIFIED,
          message: 'Email address is not verified',
          email: user.email,
        },
        HttpStatus.FORBIDDEN,
      );
    }
  }

  private isUniqueViolation(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === '23505'
    );
  }

  private async issueTokens(user: User) {
    const accessToken = await this.jwtService.signAsync(
      {
        sub: user.id,
        login: user.login,
      },
      {
        secret: this.configService.getOrThrow<string>('JWT_ACCESS_SECRET'),
        expiresIn: Number(
          this.configService.getOrThrow<string>('JWT_ACCESS_EXPIRES_IN'),
        ),
      },
    );

    const refreshToken = await this.jwtService.signAsync(
      {
        sub: user.id,
      },
      {
        secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
        expiresIn: Number(
          this.configService.getOrThrow<string>('JWT_REFRESH_EXPIRES_IN'),
        ),
      },
    );

    const tokenHash = await bcrypt.hash(refreshToken, 10);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await this.database.db
      .insert(refreshTokens)
      .values({
        userId: user.id,
        tokenHash,
        expiresAt,
      })
      .onConflictDoUpdate({
        target: refreshTokens.userId,
        set: { tokenHash, expiresAt },
      });

    return {
      user: { id: user.id, login: user.login, email: user.email },
      accessToken,
      refreshToken,
    };
  }
}
