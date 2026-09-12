import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { eq } from 'drizzle-orm';

import { DatabaseService } from '../database/database.service';
import { refreshTokens, users } from '../database/schema';
import type { User } from '../database/schema';
import { SigninDto } from './dto/signin.dto';
import { SignupDto } from './dto/signup.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async signup(dto: SignupDto) {
    if (dto.password !== dto.repeatPassword) {
      throw new BadRequestException('Passwords do not match');
    }

    const [existingUser] = await this.database.db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.login, dto.login))
      .limit(1);

    if (existingUser) {
      throw new ConflictException('User already exists');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    const [user] = await this.database.db
      .insert(users)
      .values({
        login: dto.login,
        passwordHash,
      })
      .returning();

    return this.issueTokens(user);
  }

  async signin(dto: SigninDto) {
    const [user] = await this.database.db
      .select()
      .from(users)
      .where(eq(users.login, dto.login))
      .limit(1);

    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const passwordValid = await bcrypt.compare(dto.password, user.passwordHash);

    if (!passwordValid) {
      throw new UnauthorizedException('Invalid credentials');
    }

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
        set: {
          tokenHash,
          expiresAt,
        },
      });

    return {
      user: {
        id: user.id,
        login: user.login,
      },
      accessToken,
      refreshToken,
    };
  }
}
