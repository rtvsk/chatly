CREATE TYPE "public"."outbox_event_status_enum" AS ENUM('pending', 'processing', 'published', 'dead');--> statement-breakpoint
CREATE TABLE "outbox_events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"topic" varchar NOT NULL,
	"payload" jsonb,
	"status" "outbox_event_status_enum" DEFAULT 'pending' NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"availableAt" timestamp DEFAULT now() NOT NULL,
	"lockedUntil" timestamp,
	"expiresAt" timestamp NOT NULL,
	"publishedAt" timestamp,
	"lastError" text,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	"updatedAt" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "outbox_events_dispatch_idx" ON "outbox_events" USING btree ("status","availableAt","lockedUntil");