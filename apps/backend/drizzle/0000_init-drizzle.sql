CREATE TYPE "public"."chats_type_enum" AS ENUM('direct', 'group');--> statement-breakpoint
CREATE TYPE "public"."friendships_status_enum" AS ENUM('pending', 'accepted', 'rejected');--> statement-breakpoint
CREATE TABLE "chat_participants" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"chatId" uuid NOT NULL,
	"userId" uuid NOT NULL,
	"lastReadMessageId" varchar,
	"joinedAt" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "chat_participants_chatId_userId_key" UNIQUE("chatId","userId")
);
--> statement-breakpoint
CREATE TABLE "chats" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"type" "chats_type_enum" DEFAULT 'direct' NOT NULL,
	"lastMessageId" varchar,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	"updatedAt" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "friendships" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"requesterId" uuid NOT NULL,
	"receiverId" uuid NOT NULL,
	"status" "friendships_status_enum" DEFAULT 'pending' NOT NULL,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	"updatedAt" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "friendships_requesterId_receiverId_key" UNIQUE("requesterId","receiverId")
);
--> statement-breakpoint
CREATE TABLE "messages" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"chatId" uuid NOT NULL,
	"senderId" uuid NOT NULL,
	"text" text NOT NULL,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	"updatedAt" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "refresh_tokens" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tokenHash" varchar NOT NULL,
	"expiresAt" timestamp NOT NULL,
	"userId" uuid NOT NULL,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "refresh_tokens_userId_key" UNIQUE("userId")
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"login" varchar NOT NULL,
	"passwordHash" varchar NOT NULL,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	"updatedAt" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "users_login_unique" UNIQUE("login")
);
--> statement-breakpoint
ALTER TABLE "chat_participants" ADD CONSTRAINT "chat_participants_chatId_chats_id_fk" FOREIGN KEY ("chatId") REFERENCES "public"."chats"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chat_participants" ADD CONSTRAINT "chat_participants_userId_users_id_fk" FOREIGN KEY ("userId") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_requesterId_users_id_fk" FOREIGN KEY ("requesterId") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_receiverId_users_id_fk" FOREIGN KEY ("receiverId") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_chatId_chats_id_fk" FOREIGN KEY ("chatId") REFERENCES "public"."chats"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_senderId_users_id_fk" FOREIGN KEY ("senderId") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_userId_users_id_fk" FOREIGN KEY ("userId") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;