CREATE TABLE "avatars" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"userId" uuid NOT NULL,
	"objectKey" varchar NOT NULL,
	"originalName" varchar NOT NULL,
	"mimeType" varchar NOT NULL,
	"size" integer NOT NULL,
	"isSelected" boolean DEFAULT false NOT NULL,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "avatars_objectKey_unique" UNIQUE("objectKey")
);
--> statement-breakpoint
ALTER TABLE "avatars" ADD CONSTRAINT "avatars_userId_users_id_fk" FOREIGN KEY ("userId") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "avatars_one_selected_per_user_idx" ON "avatars" USING btree ("userId") WHERE "avatars"."isSelected" = true;