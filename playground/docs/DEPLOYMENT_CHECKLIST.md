# Production Deployment Checklist

## Pre-Deployment Steps

### 1. Environment Variables (.env file)
Create `.env` file from `.env.sample` and configure:

```bash
# Generate strong passwords and keys
POSTGRES_PASSWORD=$(openssl rand -base64 32)
SECRET_KEY_BASE=$(bundle exec rails secret)
ACTIVE_RECORD_ENCRYPTION__PRIMARY_KEY=$(bundle exec rails db:encryption:init | grep primary_key)
ACTIVE_RECORD_ENCRYPTION__DETERMINISTIC_KEY=$(bundle exec rails db:encryption:init | grep deterministic_key)
ACTIVE_RECORD_ENCRYPTION__KEY_DERIVATION_SALT=$(bundle exec rails db:encryption:init | grep key_derivation_salt)
```

**⚠️ CRITICAL:** Never commit the `.env` file to version control!

### 2. Docker Compose Configuration
Copy `compose.yaml.sample` to `compose.yaml`:
```bash
cp compose.yaml.sample compose.yaml
```

Review and adjust resource limits based on your server specs:
- Database: 2 CPU / 2GB RAM (adjust in `db.deploy.resources`)
- App: 2 CPU / 2GB RAM (adjust in `app.deploy.resources`)
- Jobs: 1 CPU / 1GB RAM (adjust in `jobs.deploy.resources`)

### 3. Storage Configuration
For production, consider using external storage (S3, GCS) instead of local disk:

Edit `config/environments/production.rb`:
```ruby
# Change from :local to your storage provider
config.active_storage.service = :amazon  # or :google, etc.
```

Configure in `config/storage.yml` (uncomment and fill in credentials).

### 4. Host Authorization
Edit `config/environments/production.rb` and configure allowed hosts:
```ruby
config.hosts = [
  "yourdomain.com",
  /.*\.yourdomain\.com/  # Allow subdomains
]
```

### 5. SSL/TLS Configuration
If using a reverse proxy (nginx, Caddy, etc.) that handles SSL:
- Keep `RAILS_FORCE_SSL=false` in your environment
- Set `RAILS_ASSUME_SSL=true` if behind SSL-terminating proxy

If exposing Rails directly with SSL:
- Set `RAILS_FORCE_SSL=true`
- Configure SSL certificates in your proxy/load balancer

## Security Checks

### Required
- [x] Strong database password set
- [x] Unique SECRET_KEY_BASE generated
- [x] Encryption keys generated
- [ ] Host authorization configured
- [ ] Storage service configured (if not using local)
- [ ] CORS configured if needed
- [ ] Rate limiting configured (already in SessionsController)

### Recommended
- [ ] Set up firewall rules (only allow necessary ports)
- [ ] Enable automatic security updates on host OS
- [ ] Set up SSL/TLS certificates (Let's Encrypt recommended)
- [ ] Configure backup strategy for database and storage
- [ ] Set up monitoring and alerting

## Docker Configuration Review

### Health Checks ✅
- Database: PostgreSQL health check configured
- App: HTTP health check on `/up` endpoint
- Retry and timeout settings configured

### Resource Management ✅
- CPU and memory limits set for all services
- Resource reservations configured
- Prevents resource exhaustion

### Logging ✅
- JSON file driver configured
- Log rotation: max 3 files × 10MB
- Prevents disk space issues

### Restart Policies ✅
- Database: `unless-stopped`
- App: `unless-stopped`
- Jobs: `unless-stopped`
- Migrator: `no` (runs once)

## Deployment Commands

### First Time Deployment

```bash
# 1. Set up environment variables
cp .env.sample .env
# Edit .env and fill in all required values (see .env.sample for details)

# 2. Build and start services
docker compose up -d --build

# 3. Wait for database to be ready (check health status)
docker compose ps db
# Wait until health status shows "healthy"

# 4. Run database migrations
docker compose exec app ./bin/rails db:prepare

# 5. Seed initial data
docker compose exec app ./bin/rails db:seed
# This creates:
#   - LLM provider configurations
#   - System presets
#   - Demo user (demo@example.com / password)
#   - Example character (Alice)

# 6. Check logs
docker compose logs -f app

# 7. Verify services are healthy
docker compose ps

# 8. Access the application
# Open http://localhost:8080 in your browser
# Sign in with demo@example.com / password
```

**First Run Checklist:**
- [ ] Environment variables configured in `.env`
- [ ] Database healthy and migrated
- [ ] Seeds loaded successfully
- [ ] Can access http://localhost:8080
- [ ] Can sign in with demo account
- [ ] Configure LLM provider API key in Settings

### Updates
```bash
# 1. Pull latest code
git pull

# 2. Rebuild and restart
docker compose up -d --build

# 3. Check logs for errors
docker compose logs -f app
```

### Database Backups
```bash
# Backup
docker compose exec db pg_dumpall -U postgres > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore
docker compose exec -T db psql -U postgres < backup_YYYYMMDD_HHMMSS.sql
```

## Monitoring

### Check Service Status
```bash
docker compose ps
docker compose logs app --tail=100
docker compose logs jobs --tail=100
docker compose logs db --tail=100
```

### Check Resource Usage
```bash
docker stats
```

### Access Rails Console
```bash
docker compose exec app ./bin/rails console
```

## Troubleshooting

### Services Won't Start
1. Check logs: `docker compose logs`
2. Verify `.env` file exists and has all required variables
3. Check disk space: `df -h`
4. Check memory: `free -m`

### Database Connection Issues
1. Verify `POSTGRES_PASSWORD` matches in `.env`
2. Wait for database health check: `docker compose ps db`
3. Check database logs: `docker compose logs db`

### Image Upload Issues
1. Verify libvips is installed in container (already in Dockerfile)
2. Check storage volume permissions
3. Review ActiveStorage configuration

### Performance Issues
1. Check resource usage: `docker stats`
2. Review and adjust resource limits in compose.yaml
3. Monitor database query performance
4. Consider scaling horizontally (multiple app containers)

### Seeds Failed or Missing Data
1. Check if migrations ran: `docker compose exec app ./bin/rails db:version`
2. Re-run seeds: `docker compose exec app ./bin/rails db:seed`
3. For production (skip demo data): `docker compose exec app SKIP_DEMO_DATA=1 ./bin/rails db:seed`
4. Check seed output for errors

### Cannot Sign In
1. Verify seeds created demo user: `docker compose exec app ./bin/rails runner "puts User.count"`
2. Check if demo user exists: `docker compose exec app ./bin/rails runner "puts User.find_by(email: 'demo@example.com').inspect"`
3. Reset demo user password:
   ```bash
   docker compose exec app ./bin/rails runner "
     u = User.find_by!(email: 'demo@example.com')
     u.password = 'password'
     u.password_confirmation = 'password'
     u.save!
   "
   ```
4. Check SECRET_KEY_BASE is set and consistent

### LLM API Not Working
1. Verify API key configured in Settings → LLM Providers
2. Check provider is set as default
3. Test connection using "Test Connection" button
4. Check logs for API errors: `docker compose logs app | grep LLM`
5. Verify network connectivity to LLM provider

## Production Hardening (Advanced)

### Additional Security Measures
- [ ] Run containers as non-root user (already configured in Dockerfile)
- [ ] Use Docker secrets for sensitive data
- [ ] Enable AppArmor/SELinux profiles
- [ ] Scan images for vulnerabilities
- [ ] Implement network segmentation
- [ ] Set up Web Application Firewall (WAF)

### High Availability
- [ ] Set up load balancer
- [ ] Configure database replication
- [ ] Implement Redis for ActionCable (if scaling)
- [ ] Use external storage (S3/GCS) for uploads
- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Configure alerting (PagerDuty/OpsGenie)

## Notes

- The current setup uses local disk storage for uploads. For production with multiple app instances, use S3/GCS.
- SolidQueue and SolidCache use separate PostgreSQL databases for isolation.
- The setup uses Thruster as a reverse proxy (built into Rails 8).
- PostgreSQL 18 with pgvector extension is used for vector similarity searches.
