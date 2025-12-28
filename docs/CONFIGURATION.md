# Interactive Configuration Guide

This guide explains the interactive configuration process during deployment.

## Overview

The deployment script includes an **interactive configuration editor** that:
1. ✅ Auto-generates secure SECRET_KEY
2. ✅ Pre-fills your domain in all relevant fields
3. ✅ Provides sensible defaults
4. ✅ Validates configuration before starting
5. ✅ Guides you through required vs optional settings

## Configuration Flow

```
Installation Steps
    ↓
Environment File Created (with defaults)
    ↓
Nano Editor Opens Automatically
    ↓
You Configure Required Settings
    ↓
Save & Exit (Ctrl+X → Y → Enter)
    ↓
Validation Runs Automatically
    ↓
    ├─→ Valid? → Application Starts ✓
    └─→ Invalid? → Edit Again or Exit
```

## What You'll See

### 1. Pre-Installation Notice

```
============================================
IMPORTANT: Environment Configuration Required
============================================

The application REQUIRES proper configuration to run successfully!

The nano editor will now open with your environment file.
Please configure the following REQUIRED settings:

  ✓ Already configured:
    - SECRET_KEY (auto-generated)
    - ALLOWED_HOSTS (set to your domain)
    - SITE_URL (set to your domain)

  ⚠ REQUIRED - Must configure:
    - DATABASE_URL (if using external PostgreSQL)
    - EMAIL_HOST_USER & EMAIL_HOST_PASSWORD (for email functionality)

  ○ OPTIONAL - Configure if needed:
    - Cloudflare R2 credentials (for file storage)
    - M-Pesa credentials (for payments)
    - Google OAuth (for social login)
    - Sentry & PostHog (for monitoring)
    - reCAPTCHA keys (for bot protection)

Press Enter to open the editor and configure your environment...
```

### 2. Nano Editor Opens

You'll see your environment file with:
- Auto-generated SECRET_KEY ✓
- Your domain already configured ✓
- Clear sections with comments
- Placeholder values to replace

### 3. Configuration Sections

#### Already Configured ✓
```bash
# These are already set correctly:
SECRET_KEY=xh9f8hg4h8g4hg84hg84h...  # Auto-generated
ALLOWED_HOSTS=localhost,example.com,www.example.com  # Your domain
SITE_URL=https://example.com  # Your domain
```

#### Must Configure ⚠
```bash
# Required for email functionality:
EMAIL_HOST_USER=your-email@gmail.com  # ← Change this
EMAIL_HOST_PASSWORD=your-app-password  # ← Change this

# If using PostgreSQL (optional if using SQLite):
DATABASE_URL=postgresql://user:password@host:port/dbname  # ← Configure if needed
```

#### Optional (Configure if Using) ○
```bash
# Cloudflare R2 (for file storage)
CLOUDFLARE_R2_ACCESS_KEY=your-access-key
CLOUDFLARE_R2_SECRET_KEY=your-secret-key

# M-Pesa (for payments)
MPESA_CONSUMER_KEY=your-consumer-key
MPESA_CONSUMER_SECRET=your-consumer-secret

# Google OAuth (for social login)
GOOGLE_OAUTH_CLIENT_ID=your-client-id
```

### 4. After Saving

The script automatically validates your configuration:

#### If Everything is Correct ✓
```
============================================
Validating Environment Configuration
============================================

✓ Environment configuration validated

Ready to start the application!
```

#### If Required Fields Missing ✗
```
============================================
Validating Environment Configuration
============================================

✗ Configuration validation FAILED!

Critical errors found:
  ✗ ALLOWED_HOSTS contains placeholder domain
  ✗ Email not configured

⚠ Please fix these errors before continuing.

Do you want to edit the configuration again? [Y/n]:
```

#### If Optional Fields Not Configured ⚠
```
============================================
Validating Environment Configuration
============================================

⚠ Configuration warnings (non-critical):
  ⚠ Cloudflare R2 not configured (file storage may not work)
  ⚠ M-Pesa not configured (payment functionality will not work)

You can continue, but some features may not work without proper configuration.

Continue anyway? [Y/n]:
```

## Quick Configuration Scenarios

### Scenario 1: Minimal Setup (Email Only)

**Goal**: Get app running with email functionality

**Configure**:
```bash
# Email settings
EMAIL_HOST_USER=myapp@gmail.com
EMAIL_HOST_PASSWORD=abcd efgh ijkl mnop  # Gmail app password

# Everything else: Leave as default or placeholder
```

**Result**: App runs, emails work, other features disabled

---

### Scenario 2: Full Production Setup

**Goal**: All features enabled

**Configure**:
```bash
# Email
EMAIL_HOST_USER=myapp@gmail.com
EMAIL_HOST_PASSWORD=your-app-password

# Database (PostgreSQL)
DATABASE_URL=postgresql://dbuser:securepass@db.example.com:5432/mydb

# Cloudflare R2
CLOUDFLARE_R2_ACCESS_KEY=abc123...
CLOUDFLARE_R2_SECRET_KEY=xyz789...
CLOUDFLARE_R2_BUCKET=myapp-private

# M-Pesa
MPESA_CONSUMER_KEY=xyz123...
MPESA_CONSUMER_SECRET=abc789...
MPESA_PASSKEY=your-passkey
MPESA_SHORTCODE=123456

# Google OAuth
GOOGLE_OAUTH_CLIENT_ID=123-abc.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=your-secret

# Monitoring
SENTRY_DSN=https://your-dsn@sentry.io/123
POSTHOG_API_KEY=your-key

# reCAPTCHA
RECAPTCHA_PUBLIC_KEY=your-site-key
RECAPTCHA_PRIVATE_KEY=your-secret-key
```

**Result**: All features enabled and working

---

### Scenario 3: Testing/Staging Setup

**Goal**: Test environment without external services

**Configure**:
```bash
# Email (use Mailtrap or similar)
EMAIL_HOST=smtp.mailtrap.io
EMAIL_HOST_USER=your-mailtrap-username
EMAIL_HOST_PASSWORD=your-mailtrap-password
EMAIL_PORT=2525

# Database: Use default SQLite (don't change DATABASE_URL)

# M-Pesa: Use sandbox
MPESA_CONSUMER_KEY=sandbox-key
MPESA_CONSUMER_SECRET=sandbox-secret
BASE_URL=https://sandbox.safaricom.co.ke

# Everything else: Leave as placeholder
```

**Result**: Safe testing environment

## Editing Tips

### Navigation in Nano
- **Arrow Keys**: Move cursor
- **Page Up/Down**: Scroll
- **Ctrl+K**: Cut line
- **Ctrl+U**: Paste line
- **Ctrl+W**: Search
- **Ctrl+X**: Exit (will prompt to save)

### Saving Changes
1. Press `Ctrl+X`
2. Nano asks: "Save modified buffer?"
3. Press `Y` for Yes
4. Press `Enter` to confirm filename

### Common Mistakes to Avoid
❌ Leaving quotes around values: `EMAIL_HOST_USER="myemail@gmail.com"`
✓ No quotes needed: `EMAIL_HOST_USER=myemail@gmail.com`

❌ Adding spaces around `=`: `EMAIL_HOST_USER = myemail`
✓ No spaces: `EMAIL_HOST_USER=myemail@gmail.com`

❌ Using same value for different keys: Copy-paste errors
✓ Each credential should be unique

## Service-Specific Guides

### Gmail Setup

1. **Enable 2-Factor Authentication**
   - Go to: https://myaccount.google.com/security
   - Enable 2-Step Verification

2. **Generate App Password**
   - Go to: https://myaccount.google.com/apppasswords
   - Select "Mail" and your device
   - Copy the 16-character password (format: xxxx xxxx xxxx xxxx)

3. **Configure**:
   ```bash
   EMAIL_HOST=smtp.gmail.com
   EMAIL_HOST_USER=yourname@gmail.com
   EMAIL_HOST_PASSWORD=abcdefghijklmnop  # 16 chars, no spaces
   EMAIL_PORT=587
   ```

### Cloudflare R2 Setup

1. **Create Buckets**
   - Private bucket: `myapp-private`
   - Public bucket: `myapp-public`
   - Backup bucket: `myapp-backups`

2. **Generate API Tokens**
   - Go to: R2 → Manage R2 API Tokens
   - Create token with appropriate permissions
   - Copy Access Key ID and Secret Access Key

3. **Get Account ID**
   - Found in: Cloudflare dashboard → R2 → Overview
   - Format: `abc123def456...`

4. **Configure**:
   ```bash
   CLOUDFLARE_R2_ACCESS_KEY=your-access-key-id
   CLOUDFLARE_R2_SECRET_KEY=your-secret-access-key
   CLOUDFLARE_R2_BUCKET=myapp-private
   CLOUDFLARE_R2_BUCKET_ENDPOINT=https://abc123def456.r2.cloudflarestorage.com
   ```

### M-Pesa Setup (Kenya)

1. **Register on Daraja**
   - Go to: https://developer.safaricom.co.ke/
   - Create account and register app

2. **Get Sandbox Credentials** (for testing)
   - Consumer Key
   - Consumer Secret
   - Passkey (from test credentials)

3. **Configure**:
   ```bash
   # For testing (sandbox)
   MPESA_CONSUMER_KEY=your-sandbox-consumer-key
   MPESA_CONSUMER_SECRET=your-sandbox-consumer-secret
   MPESA_PASSKEY=your-sandbox-passkey
   MPESA_SHORTCODE=174379  # Sandbox shortcode
   BASE_URL=https://sandbox.safaricom.co.ke
   CALLBACK_URL=https://yourdomain.com/api/mpesa/callback
   ```

4. **For Production**:
   - Apply for production access
   - Use production credentials
   - Change BASE_URL to production URL

### PostgreSQL Database Setup

1. **Create Database**
   ```sql
   CREATE DATABASE myapp_db;
   CREATE USER myapp_user WITH PASSWORD 'secure_password';
   GRANT ALL PRIVILEGES ON DATABASE myapp_db TO myapp_user;
   ```

2. **Get Connection Details**
   - Host: Your database server IP/hostname
   - Port: Usually 5432
   - Database: myapp_db
   - Username: myapp_user
   - Password: secure_password

3. **Configure**:
   ```bash
   DATABASE_URL=postgresql://myapp_user:secure_password@db.example.com:5432/myapp_db
   ```

## Reconfiguring Later

If you need to change configuration after installation:

```bash
cd /opt/apps/esc
./reconfig.sh
```

This will:
1. Open nano editor with your current configuration
2. Let you make changes
3. Offer to restart the application
4. Apply new configuration

## Validation Details

The script checks:

### Critical (Must Pass)
- ✅ SECRET_KEY is set and not default
- ✅ ALLOWED_HOSTS doesn't contain placeholder
- ✅ Basic syntax is correct

### Warnings (Can Continue)
- ⚠ Email not configured
- ⚠ Database uses placeholder values
- ⚠ External services not configured

## Troubleshooting Configuration

### "Validation Failed" Error

**Problem**: Configuration has critical errors

**Solution**:
1. Review error messages
2. Edit configuration again when prompted
3. Fix the specific issues mentioned
4. Save and let validation run again

### Features Not Working

**Problem**: Application runs but specific features don't work

**Solution**:
1. Check application logs: `./logs.sh web`
2. Verify credentials for that service
3. Reconfigure: `./reconfig.sh`
4. Test the specific feature again

### Can't Remember What to Configure

**Solution**:
1. Check `.env.example` in the repo for reference
2. Read comments in your `.env.docker` file
3. Consult this guide for service-specific instructions
4. Start minimal (email only) and add services as needed

## Security Best Practices

1. **Never share your `.env.docker` file**
   - Contains sensitive credentials
   - Backup securely, don't commit to git

2. **Use strong passwords**
   - Generate random passwords
   - Don't reuse passwords across services

3. **Rotate credentials regularly**
   - Change passwords every 3-6 months
   - Update API keys if compromised

4. **Use different credentials for staging/production**
   - Separate databases
   - Separate API keys
   - Different email accounts if possible

5. **Backup your configuration**
   ```bash
   cp /opt/apps/esc/.env.docker ~/env-backup-$(date +%Y%m%d).txt
   ```

## Summary

The interactive configuration system:
- ✅ Makes deployment easy and guided
- ✅ Validates configuration before starting
- ✅ Prevents common mistakes
- ✅ Provides clear error messages
- ✅ Allows easy reconfiguration

Just follow the prompts, configure what you need, and the script handles the rest!

---

**Need Help?** Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.