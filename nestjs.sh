#!/bin/bash

###########################################
# E-Commerce Backend - NestJS + Prisma
# Debian 13
# Uses existing PostgreSQL + Nginx
###########################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_step() {
    echo -e "\n${PURPLE}════════════════════════════════════════${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════${NC}\n"
}

###########################################
# PRE-FLIGHT
###########################################

clear

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║       E-COMMERCE BACKEND INSTALLER                   ║
║       NestJS + Prisma + PostgreSQL + Nginx            ║
║                                                       ║
║       Existing PostgreSQL + Nginx will be used        ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Do not run as root
if [[ $EUID -eq 0 ]]; then
    log_error "Do NOT run this script as root."
    echo ""
    echo "Run it as your normal user:"
    echo "  ./install-ecommerce-backend.sh"
    exit 1
fi

###########################################
# STEP 1 - SYSTEM UPDATE
###########################################

log_step "STEP 1: Updating System"

log_info "Updating package lists..."
sudo apt-get update

log_success "Package lists updated"

###########################################
# STEP 2 - CHECK EXISTING SERVICES
###########################################

log_step "STEP 2: Checking Existing Services"

# PostgreSQL
if command -v psql >/dev/null 2>&1; then
    PG_VERSION=$(psql --version)
    log_success "PostgreSQL found: ${PG_VERSION}"
else
    log_error "PostgreSQL client not found."
    exit 1
fi

if sudo systemctl is-active --quiet postgresql; then
    log_success "PostgreSQL service is available"
else
    log_warning "PostgreSQL main service is not active."
    log_info "Checking PostgreSQL clusters..."

    if command -v pg_lsclusters >/dev/null 2>&1; then
        pg_lsclusters
    fi

    log_info "Attempting to start PostgreSQL..."
    sudo systemctl start postgresql
fi

# Nginx
if command -v nginx >/dev/null 2>&1; then
    NGINX_VERSION=$(nginx -v 2>&1)
    log_success "Nginx found: ${NGINX_VERSION}"
else
    log_error "Nginx is not installed."
    exit 1
fi

if sudo systemctl is-active --quiet nginx; then
    log_success "Nginx is running"
else
    log_warning "Nginx is not running."
    log_info "Starting Nginx..."
    sudo systemctl start nginx
fi

###########################################
# STEP 3 - INSTALL BASIC DEPENDENCIES
###########################################

log_step "STEP 3: Installing Required Dependencies"

sudo apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    openssl

log_success "System dependencies installed"

###########################################
# STEP 4 - INSTALL NODE.JS
###########################################

log_step "STEP 4: Installing Node.js"

if command -v node >/dev/null 2>&1; then

    NODE_VERSION=$(node -v)
    log_success "Node.js already installed: ${NODE_VERSION}"

else

    log_info "Node.js not found."
    log_info "Installing Node.js 20 LTS..."

    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -

    sudo apt-get install -y nodejs

    NODE_VERSION=$(node -v)
    NPM_VERSION=$(npm -v)

    log_success "Node.js installed: ${NODE_VERSION}"
    log_success "npm installed: ${NPM_VERSION}"

fi

node -v
npm -v

###########################################
# STEP 5 - CONFIGURE NPM
###########################################

log_step "STEP 5: Configuring npm"

mkdir -p "$HOME/.npm-global"

npm config set prefix "$HOME/.npm-global"

export PATH="$HOME/.npm-global/bin:$PATH"

if ! grep -q 'npm-global/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# npm global packages" >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
fi

log_success "npm configured for user-level global packages"

###########################################
# STEP 6 - DATABASE CONFIGURATION
###########################################

log_step "STEP 6: PostgreSQL Database Configuration"

echo -e "${CYAN}Enter database configuration:${NC}"
echo ""

read -p "Database name [ecommerce_db]: " DB_NAME
DB_NAME=${DB_NAME:-ecommerce_db}

read -p "Database user [ecommerce_user]: " DB_USER
DB_USER=${DB_USER:-ecommerce_user}

while true; do

    read -rsp "Database password: " DB_PASSWORD
    echo

    read -rsp "Confirm password: " DB_PASSWORD_CONFIRM
    echo

    if [[ "$DB_PASSWORD" == "$DB_PASSWORD_CONFIRM" ]]; then
        break
    fi

    log_error "Passwords do not match."

done

# Validate database/user names
if [[ ! "$DB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    log_error "Invalid database name."
    exit 1
fi

if [[ ! "$DB_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    log_error "Invalid database username."
    exit 1
fi

log_info "Checking PostgreSQL database..."

DB_EXISTS=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'")

USER_EXISTS=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'")

if [[ "$USER_EXISTS" != "1" ]]; then

    log_info "Creating PostgreSQL user..."

    sudo -u postgres psql \
        -v ON_ERROR_STOP=1 \
        -c "CREATE USER \"$DB_USER\" WITH PASSWORD '$DB_PASSWORD';"

else

    log_info "PostgreSQL user already exists."

    sudo -u postgres psql \
        -v ON_ERROR_STOP=1 \
        -c "ALTER USER \"$DB_USER\" WITH PASSWORD '$DB_PASSWORD';"

fi

if [[ "$DB_EXISTS" != "1" ]]; then

    log_info "Creating PostgreSQL database..."

    sudo -u postgres psql \
        -v ON_ERROR_STOP=1 \
        -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"

else

    log_info "PostgreSQL database already exists."

fi

sudo -u postgres psql \
    -v ON_ERROR_STOP=1 \
    -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"

sudo -u postgres psql \
    -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 \
    -c "GRANT ALL ON SCHEMA public TO \"$DB_USER\";"

log_success "PostgreSQL configured"

###########################################
# STEP 7 - PROJECT
###########################################

log_step "STEP 7: Creating NestJS Project"

read -p "Project directory [ecommerce-backend]: " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-ecommerce-backend}

PROJECT_DIR="/var/www/$PROJECT_NAME"

if [[ -e "$PROJECT_DIR" ]]; then
    log_warning "Project directory already exists:"
    echo "  $PROJECT_DIR"
    read -p "Continue and use existing directory? [y/N]: " CONTINUE

    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        log_error "Installation cancelled."
        exit 1
    fi
else
    sudo mkdir -p "$PROJECT_DIR"
    sudo chown "$USER:$USER" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

log_success "Project directory: $PROJECT_DIR"

###########################################
# STEP 8 - INITIALIZE NESTJS
###########################################

log_step "STEP 8: Initializing NestJS"

if [[ ! -f package.json ]]; then

    log_info "Creating NestJS application..."

    npx @nestjs/cli new . --package-manager npm --skip-git

else

    log_info "package.json already exists. Skipping NestJS initialization."

fi

###########################################
# STEP 9 - INSTALL NESTJS PACKAGES
###########################################

log_step "STEP 9: Installing NestJS Dependencies"

npm install \
    @nestjs/config \
    @nestjs/jwt \
    @nestjs/passport \
    @nestjs/platform-express \
    @nestjs/platform-socket.io \
    @nestjs/schedule \
    @nestjs/websockets \
    passport \
    passport-jwt \
    bcrypt \
    class-transformer \
    class-validator \
    compression \
    helmet \
    socket.io

npm install \
    -D @types/bcrypt \
    @types/passport-jwt

log_success "NestJS dependencies installed"

###########################################
# STEP 10 - INSTALL PRISMA
###########################################

log_step "STEP 10: Installing Prisma"

npm install @prisma/client

npm install -D prisma

if [[ ! -f prisma/schema.prisma ]]; then

    log_info "Initializing Prisma..."

    npx prisma init --datasource-provider postgresql

else

    log_info "Prisma schema already exists."

fi

###########################################
# STEP 11 - ENVIRONMENT
###########################################

log_step "STEP 11: Creating Environment Configuration"

JWT_SECRET=$(openssl rand -base64 48)
JWT_REFRESH_SECRET=$(openssl rand -base64 48)

cat > .env << EOF
NODE_ENV=development
PORT=3000

DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}?schema=public"

JWT_SECRET=${JWT_SECRET}
JWT_EXPIRES_IN=1h

JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_REFRESH_EXPIRES_IN=7d

CORS_ORIGIN=http://localhost:3001

MAX_FILE_SIZE=5242880
UPLOAD_DIR=./uploads

DEFAULT_COMMISSION_RATE=10
EOF

chmod 600 .env

log_success ".env created"

###########################################
# STEP 12 - PRISMA SCHEMA
###########################################

log_step "STEP 12: Configuring Prisma"

cat > prisma/schema.prisma << 'EOF'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum UserRole {
  ADMIN
  AGENT
  CUSTOMER
}

model User {
  id           String   @id @default(uuid())
  username     String   @unique
  email        String   @unique
  passwordHash String   @map("password_hash")
  role         UserRole @default(CUSTOMER)
  referralCode String   @unique @map("referral_code")
  createdAt    DateTime @default(now()) @map("created_at")
  updatedAt    DateTime @updatedAt @map("updated_at")

  @@map("users")
}
EOF

###########################################
# STEP 13 - PRISMA GENERATE
###########################################

log_step "STEP 13: Generating Prisma Client"

npx prisma generate

log_success "Prisma client generated"

###########################################
# STEP 14 - TEST DATABASE CONNECTION
###########################################

log_step "STEP 14: Testing PostgreSQL Connection"

if npx prisma db execute --stdin <<< "SELECT 1;" >/dev/null 2>&1; then
    log_success "Prisma successfully connected to PostgreSQL"
else
    log_error "Prisma could not connect to PostgreSQL"
    echo ""
    echo "DATABASE_URL:"
    echo "postgresql://${DB_USER}:********@localhost:5432/${DB_NAME}?schema=public"
    exit 1
fi

###########################################
# STEP 15 - CREATE MIGRATION
###########################################

log_step "STEP 15: Creating Prisma Migration"

if [[ ! -d prisma/migrations ]] || [[ -z "$(find prisma/migrations -mindepth 1 -type d 2>/dev/null)" ]]; then

    log_info "Creating initial Prisma migration..."

    npx prisma migrate dev --name init

    log_success "Initial migration created and applied"

else

    log_info "Existing Prisma migrations detected."
    log_info "Applying migrations..."

    npx prisma migrate dev

    log_success "Existing migrations applied"

fi

###########################################
# STEP 16 - APPLICATION FILES
###########################################

log_step "STEP 16: Configuring NestJS"

cat > src/app.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
  ],
})
export class AppModule {}
EOF

cat > src/main.ts << 'EOF'
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors();

  app.setGlobalPrefix('api/v1');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
    }),
  );

  const port = process.env.PORT || 3000;

  await app.listen(port, '127.0.0.1');

  console.log(`🚀 Server running on http://127.0.0.1:${port}/api/v1`);
}

bootstrap();
EOF

mkdir -p uploads

log_success "NestJS configured"

###########################################
# STEP 17 - BUILD
###########################################

log_step "STEP 17: Building Application"

npm run build

log_success "NestJS build successful"

###########################################
# STEP 18 - NGINX CONFIGURATION
###########################################

log_step "STEP 18: Nginx Configuration"

read -p "Enter API domain (example: api.example.com): " API_DOMAIN

if [[ -z "$API_DOMAIN" ]]; then
    log_warning "No domain supplied."
    log_warning "Skipping Nginx configuration."
else

    NGINX_CONFIG="/etc/nginx/sites-available/$PROJECT_NAME"

    sudo tee "$NGINX_CONFIG" > /dev/null << EOF
server {
    listen 80;
    server_name ${API_DOMAIN};

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:3000;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    if [[ ! -L "/etc/nginx/sites-enabled/$PROJECT_NAME" ]]; then
        sudo ln -s "$NGINX_CONFIG" "/etc/nginx/sites-enabled/$PROJECT_NAME"
    fi

    sudo nginx -t
    sudo systemctl reload nginx

    log_success "Nginx configured for ${API_DOMAIN}"

fi

###########################################
# FINAL
###########################################

clear

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║             ✓ INSTALLATION COMPLETE                  ║
║                                                       ║
║       NestJS + Prisma + PostgreSQL + Nginx            ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${CYAN}System:${NC}"
echo "  Node.js:   $(node -v)"
echo "  npm:       $(npm -v)"
echo "  PostgreSQL: $(psql --version | awk '{print $3}')"
echo "  Nginx:      $(nginx -v 2>&1 | cut -d/ -f2)"

echo ""
echo -e "${CYAN}Project:${NC}"
echo "  Location: $PROJECT_DIR"
echo "  Port:     3000"
echo "  Database: $DB_NAME"
echo "  DB User:  $DB_USER"

echo ""
echo -e "${CYAN}Prisma:${NC}"
echo "  Migration: prisma/migrations/"
echo "  Schema:    prisma/schema.prisma"

echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo ""
echo "  cd $PROJECT_DIR"
echo ""
echo "  npm run start:dev"
echo ""
echo "  npx prisma studio"
echo ""
echo "  npx prisma migrate dev --name <migration-name>"
echo ""
echo "  npx prisma generate"
echo ""
echo "  npm run build"
echo ""

if [[ -n "$API_DOMAIN" ]]; then
    echo -e "${GREEN}API:${NC}"
    echo "  http://${API_DOMAIN}/api/v1"
    echo ""
fi

echo -e "${GREEN}Done.${NC}"