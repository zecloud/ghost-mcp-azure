#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from './mcpServer';
import './ghostApi'; // Validates Ghost configuration at startup

// Set up and connect to the standard I/O transport
async function startServer() {
    // stdio runs on the user's own machine: local image upload is allowed.
    const server = createServer({ allowImageUpload: true });
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("Ghost MCP TypeScript Server running on stdio"); // Log to stderr
}

// Start the server
startServer().catch((error: any) => {
    console.error("Fatal error starting server:", error);
    process.exit(1);
});
