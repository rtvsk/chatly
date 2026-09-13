import { HttpStatus } from '@nestjs/common';
import { HTTP_CODE_METADATA } from '@nestjs/common/constants';

import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

describe('AuthController', () => {
  it('returns 202 Accepted for generic resend requests', async () => {
    const resendVerification = jest.fn().mockResolvedValue(undefined);
    const controller = new AuthController({
      resendVerification,
    } as unknown as AuthService);

    await expect(
      controller.resendVerification({ email: 'person@example.com' }),
    ).resolves.toEqual({ status: 'accepted' });
    expect(resendVerification).toHaveBeenCalledWith({
      email: 'person@example.com',
    });
    expect(
      Reflect.getMetadata(
        HTTP_CODE_METADATA,
        AuthController.prototype.resendVerification,
      ),
    ).toBe(HttpStatus.ACCEPTED);
  });
});
