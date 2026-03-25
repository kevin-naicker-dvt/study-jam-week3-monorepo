import { ConfigService } from '@nestjs/config';

export function getJwtSecret(configService: ConfigService): string {
  const secret = configService.get<string>('JWT_SECRET')?.trim();
  if (!secret) {
    throw new Error(
      'JWT_SECRET is missing or empty. Set it in the environment (e.g. Kubernetes Secret studyjam-runtime, key JWT_SECRET — see k8s/10-backend.yaml).',
    );
  }
  return secret;
}
