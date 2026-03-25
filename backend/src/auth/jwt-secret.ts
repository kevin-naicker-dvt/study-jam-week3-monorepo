import { ConfigService } from '@nestjs/config';

export function getJwtSecret(configService: ConfigService): string {
  const secret = configService.get<string>('JWT_SECRET')?.trim();
  if (!secret) {
    throw new Error(
      'JWT_SECRET is missing or empty. Set it in the environment (e.g. Kubernetes Secret studyjam-k8s-runtime, key JWT_SECRET — see backend/kubernetes/deployment-backend.yaml).',
    );
  }
  return secret;
}
