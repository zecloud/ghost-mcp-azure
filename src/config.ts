// Read configuration values directly from process.env
export const GHOST_API_URL: string = process.env.GHOST_API_URL as string;
export const GHOST_ADMIN_API_KEY: string = process.env.GHOST_ADMIN_API_KEY as string;
export const GHOST_API_VERSION: string = process.env.GHOST_API_VERSION as string || 'v5.0'; // Default to v5.0

// Basic validation to ensure required environment variables are set.
// Throw instead of process.exit so the Azure Functions host can surface the
// error without killing the whole worker process.
if (!GHOST_API_URL) {
    throw new Error("GHOST_API_URL environment variable is not set.");
}

if (!GHOST_ADMIN_API_KEY) {
    throw new Error("GHOST_ADMIN_API_KEY environment variable is not set.");
}