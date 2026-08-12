# Ghost MCP Server

A Model Context Protocol (MCP) server for interacting with Ghost CMS through LLM interfaces like Claude. This server provides secure and comprehensive access to your Ghost blog, leveraging JWT authentication and a rich set of MCP tools for managing posts, users, members, tiers, offers, and newsletters.

![demo](./assets/ghost-mcp-demo.gif)

## Features

- Secure Ghost Admin API requests with `@tryghost/admin-api`
- Comprehensive entity access including posts, users, members, tiers, offers, and newsletters
- Advanced search functionality with both fuzzy and exact matching options
- Detailed, human-readable output for Ghost entities
- Robust error handling using custom `GhostError` exceptions
- Integrated logging support via MCP context for enhanced troubleshooting

## Usage

To use this with MCP clients, for instance, Claude Desktop, add the following to your `claude_desktop_config.json`:
```json
{
  "mcpServers": {
      "ghost-mcp": {
        "command": "npx",
        "args": ["-y", "@fanyangmeng/ghost-mcp"],
        "env": {
            "GHOST_API_URL": "https://yourblog.com",
            "GHOST_ADMIN_API_KEY": "your_admin_api_key",
            "GHOST_API_VERSION": "v5.0"
        }
      }
    }
}
```

## Available Resources

The following Ghost CMS resources are available through this MCP server:

- **Posts**: Articles and content published on your Ghost site.
- **Members**: Registered users and subscribers of your site.
- **Newsletters**: Email newsletters managed and sent via Ghost.
- **Offers**: Promotional offers and discounts for members.
- **Invites**: Invitations for new users or staff to join your Ghost site.
- **Roles**: User roles and permissions within the Ghost admin.
- **Tags**: Organizational tags for posts and content.
- **Tiers**: Subscription tiers and plans for members.
- **Users**: Admin users and staff accounts.
- **Webhooks**: Automated event notifications to external services.

## Available Tools

This MCP server exposes a comprehensive set of tools for managing your Ghost CMS via the Model Context Protocol. Each resource provides a set of operations, typically including browsing, reading, creating, editing, and deleting entities. Below is a summary of the available tools:

### Posts
- **Browse Posts**: List posts with optional filters, pagination, and ordering.
- **Read Post**: Retrieve a post by ID or slug.
- **Add Post**: Create a new post with title, content, and status.
- **Edit Post**: Update an existing post by ID.
- **Delete Post**: Remove a post by ID.

### Members
- **Browse Members**: List members with filters and pagination.
- **Read Member**: Retrieve a member by ID or email.
- **Add Member**: Create a new member.
- **Edit Member**: Update member details.
- **Delete Member**: Remove a member.

### Newsletters
- **Browse Newsletters**: List newsletters.
- **Read Newsletter**: Retrieve a newsletter by ID.
- **Add Newsletter**: Create a new newsletter.
- **Edit Newsletter**: Update newsletter details.
- **Delete Newsletter**: Remove a newsletter.

### Offers
- **Browse Offers**: List offers.
- **Read Offer**: Retrieve an offer by ID.
- **Add Offer**: Create a new offer.
- **Edit Offer**: Update offer details.
- **Delete Offer**: Remove an offer.

### Invites
- **Browse Invites**: List invites.
- **Add Invite**: Create a new invite.
- **Delete Invite**: Remove an invite.

### Roles
- **Browse Roles**: List roles.
- **Read Role**: Retrieve a role by ID.

### Tags
- **Browse Tags**: List tags.
- **Read Tag**: Retrieve a tag by ID or slug.
- **Add Tag**: Create a new tag.
- **Edit Tag**: Update tag details.
- **Delete Tag**: Remove a tag.

### Tiers
- **Browse Tiers**: List tiers.
- **Read Tier**: Retrieve a tier by ID.
- **Add Tier**: Create a new tier.
- **Edit Tier**: Update tier details.
- **Delete Tier**: Remove a tier.

### Users
- **Browse Users**: List users.
- **Read User**: Retrieve a user by ID or slug.
- **Edit User**: Update user details.
- **Delete User**: Remove a user.

### Webhooks
- **Browse Webhooks**: List webhooks.
- **Add Webhook**: Create a new webhook.
- **Delete Webhook**: Remove a webhook.

> Each tool is accessible via the MCP protocol and can be invoked from compatible clients. For detailed parameter schemas and usage, see the source code in `src/tools/`.


## Error Handling

Ghost MCP Server employs a custom `GhostError` exception to handle API communication errors and processing issues. This ensures clear and descriptive error messages to assist with troubleshooting.

## Running as a remote MCP server on Azure Functions

This fork can also run as a **remote MCP server** (Streamable HTTP transport) hosted on **Azure Functions** (Flex Consumption plan), following the [official Microsoft pattern](https://learn.microsoft.com/azure/azure-functions/scenario-host-mcp-server-sdks?pivots=programming-language-typescript). The Functions host runs the server as an [MCP custom handler](https://learn.microsoft.com/azure/azure-functions/self-hosted-mcp-servers): `host.json` launches `node build/index.js`, an Express app exposing the MCP endpoint at `/mcp` in stateless mode (a fresh server + transport per request).

### Architecture

- `src/mcpServer.ts` — `createServer()` factory registering all Ghost resources, tools and prompts (shared by both entry points).
- `src/server.ts` — stdio entry point (local use with Claude Desktop, unchanged).
- `src/index.ts` — HTTP entry point (Express + `StreamableHTTPServerTransport`, stateless) used by Azure Functions.
- `host.json` — `mcp-custom-handler` configuration profile, anonymous auth at the host level (OAuth is enforced by Easy Auth, see below).
- `infra/` — Bicep modules (azd) provisioning: Flex Consumption Function App (Node 22), storage with private endpoints + VNet, App Insights/Log Analytics, user-assigned managed identity, and an **Entra ID app registration + Easy Auth** so only authenticated Microsoft Entra users can call the MCP endpoint.

### Configuration

Ghost credentials are read from environment variables / app settings — never hardcoded:

| Setting | Description |
| --- | --- |
| `GHOST_API_URL` | Base URL of your Ghost site, e.g. `https://yourblog.ghost.io` |
| `GHOST_ADMIN_API_KEY` | Admin API key (Ghost Admin → Settings → Integrations → Add custom integration) |
| `GHOST_API_VERSION` | API version, defaults to `v5.0` |

For local development, fill these values in `local.settings.json` (dummy placeholders are committed; do **not** commit real keys).

### Run locally

```bash
npm install
npm run build
func start   # Azure Functions Core Tools v4.5+
```

The MCP endpoint is then available at `http://localhost:7071/mcp`. `.vscode/mcp.json` contains `local-mcp-server` and `remote-mcp-server` configurations to test it from GitHub Copilot in VS Code.

### Deploy to Azure

Deployment uses the [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) (`azd`) with the Bicep files under `infra/`:

```bash
azd auth login
azd env new ghost-mcp-prod
azd env set GHOST_API_URL https://yourblog.ghost.io
azd env set GHOST_ADMIN_API_KEY <your_admin_api_key>
azd env set PRE_AUTHORIZED_CLIENT_IDS aebc6443-996d-45c2-90f0-388ff96faa56  # pre-authorize VS Code
azd up
```

`azd up` provisions the Flex Consumption function app, deploys the code (remote build), configures the Ghost app settings, and sets up Entra ID authentication. When it completes, note the function app name, then start the `remote-mcp-server` configuration in `.vscode/mcp.json` and enter `<your-function-app>.azurewebsites.net` when prompted.

To remove all resources: `azd down`.

## Contributing

1. Fork repository
2. Create feature branch
3. Commit changes
4. Create pull request

## License

MIT
