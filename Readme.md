# NESTJS + POSTGRESQL 

A NestJS + Prisma backend TEMPLATE, using PostgreSQL for data storage and Nginx as a reverse proxy. Built with JWT authentication, role-based access, and a REST API under `/api/v1`.

## Tech Stack

- **Framework:** [NestJS](https://nestjs.com/) (Node.js 20 LTS)
- **ORM:** [Prisma](https://www.prisma.io/)
- **Database:** PostgreSQL
- **Reverse Proxy:** Nginx
- **Auth:** JWT (access + refresh tokens) via `@nestjs/jwt` and `passport-jwt`
- **Validation:** `class-validator` / `class-transformer`
- **Realtime:** `@nestjs/websockets` + `socket.io`
- **Security:** `helmet`, `compression`, CORS

## Prerequisites

The install script assumes the following are already set up on the host (Debian 13):

- PostgreSQL server running, with the `psql` client available
- Nginx installed and running
- A non-root user with `sudo` privileges

Node.js 20 LTS, npm, and all application dependencies are installed automatically by the script if not already present.

## Installation

Run the installer as a **non-root user**:

```bash
chmod +x install-ecommerce-backend.sh
./install-ecommerce-backend.sh
```

The script will:

1. Update system packages and verify PostgreSQL / Nginx are running
2. Install Node.js 20 LTS and configure npm for user-level global packages
3. Prompt for a database name, database user, and password, then create/update the PostgreSQL role and database
4. Prompt for a project directory (default: `ecommerce-backend`, created under `/var/www`)
5. Scaffold a new NestJS project and install core dependencies (auth, validation, websockets, security middleware)
6. Install and initialize Prisma, generate the Prisma client
7. Create a `.env` file with a generated `DATABASE_URL` and JWT secrets
8. Define an initial Prisma schema (`User` model with `ADMIN` / `AGENT` / `CUSTOMER` roles)
9. Test the database connection and run the initial Prisma migration
10. Write a base `AppModule` and `main.ts`, then build the project
11. Optionally configure an Nginx reverse-proxy site for a domain you provide

## Environment Variables

The script generates a `.env` file (mode `600`) with the following keys:

| Variable | Description |
|---|---|
| `NODE_ENV` | Environment (`development` by default) |
| `PORT` | App port (default `3000`) |
| `DATABASE_URL` | PostgreSQL connection string used by Prisma |
| `JWT_SECRET` | Secret for access tokens (auto-generated) |
| `JWT_EXPIRES_IN` | Access token lifetime (`1h`) |
| `JWT_REFRESH_SECRET` | Secret for refresh tokens (auto-generated) |
| `JWT_REFRESH_EXPIRES_IN` | Refresh token lifetime (`7d`) |
| `CORS_ORIGIN` | Allowed CORS origin (default `http://localhost:3001`) |
| `MAX_FILE_SIZE` | Max upload size in bytes (default `5242880`, i.e. 5MB) |
| `UPLOAD_DIR` | Local upload directory (`./uploads`) |
| `DEFAULT_COMMISSION_RATE` | Default commission rate percentage (`10`) |

> `JWT_SECRET` and `JWT_REFRESH_SECRET` are generated with `openssl rand -base64 48` on each run. Treat `.env` as sensitive — it's excluded from version control by default.

## Database / Prisma

The initial schema defines a `User` model:

- `id` (UUID, primary key)
- `username`, `email` (unique)
- `passwordHash`
- `role` (`ADMIN` | `AGENT` | `CUSTOMER`, default `CUSTOMER`)
- `referralCode` (unique)
- `createdAt`, `updatedAt`

Common Prisma commands:

```bash
npx prisma studio                          # Browse data in a GUI
npx prisma migrate dev --name <name>       # Create + apply a new migration
npx prisma generate                        # Regenerate the Prisma client
```

## Running the App

```bash
cd /var/www/<project-name>

npm run start:dev   # Development, with watch mode
npm run build        # Production build
npm run start:prod   # Run the compiled build
```

By default the app listens on `127.0.0.1:3000` and serves all routes under the `/api/v1` prefix, e.g.:

```
http://127.0.0.1:3000/api/v1
```

## Deployment / Nginx

If you provide a domain during installation, the script writes an Nginx server block to:

```
/etc/nginx/sites-available/<project-name>
```

and symlinks it into `sites-enabled`, proxying `http://your-domain/` to the app on `127.0.0.1:3000` (with WebSocket upgrade headers and a 50MB max body size for uploads). After installation the API is reachable at:

```
http://<your-domain>/api/v1
```

> The script configures HTTP only. Add TLS (e.g. via Certbot) separately for production use.

## Project Structure

```
<project-name>/
├── src/
│   ├── app.module.ts
│   └── main.ts
├── prisma/
│   ├── schema.prisma
│   └── migrations/
├── uploads/
├── .env
└── package.json
```

## Notes

- Re-running the installer is idempotent where possible: it skips NestJS scaffolding, Prisma init, and migrations if they already exist, and updates the DB user's password if the user already exists.
- Uploaded files are stored locally in `./uploads` (see `UPLOAD_DIR`); consider moving this to object storage for production.