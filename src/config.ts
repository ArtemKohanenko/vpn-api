import { z } from "zod";

const envSchema = z.object({
    PORT: z.string().default("8080"),
    TOKEN: z.string().default("87654321"),  // TODO: Fix that
});

export const config = envSchema.parse({
    PORT: process.env.PORT,
    TOKEN: process.env.JWT_SECRET_KEY,
}); 