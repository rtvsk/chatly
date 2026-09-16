import 'dotenv/config';
import { defineConfig } from 'drizzle-kit';

const required = (name: string) => {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
};

export default defineConfig({
  dialect: 'postgresql',
  schema: './apps/api/src/database/schema.ts',
  out: './drizzle',
  dbCredentials: {
    host: required('DATABASE_HOST'),
    port: Number(required('DATABASE_PORT')),
    user: required('DATABASE_USER'),
    password: required('DATABASE_PASSWORD'),
    database: required('DATABASE_NAME'),
  },
  schemaFilter: ['public'],
  tablesFilter: [
    'users',
    'refresh_tokens',
    'email_verification_tokens',
    'outbox_events',
    'chats',
    'chat_participants',
    'messages',
    'friendships',
    'avatars',
  ],
  strict: true,
  verbose: true,
});
