# PostgreSQL 17 Deployment Guide

Complete deployment guide for the PostgreSQL 17 enterprise setup script. This document covers manual deployment, automated deployment, cloud provider-specific instructions, and post-deployment configuration.

---

## Table of Contents

1. [Deployment Options](#deployment-options)
2. [Manual Deployment](#manual-deployment-interactive)
3. [Automated Deployment](#automated-deployment-unattended)
4. [Cloud Provider Guides](#cloud-provider-specific-deployment)
5. [Configuration Reference](#configuration-variables-reference)
6. [Post-Deployment](#post-deployment-tasks)
7. [Production Checklist](#production-deployment-checklist)
8. [Troubleshooting](#deployment-troubleshooting)

---

## Deployment Options

Choose the deployment method that best fits your use case:

| Method | Use Case | Time | Complexity |
|--------|----------|------|------------|
| **Manual Interactive** | Single server, learning, development | 10-15 min | Low |
| **Automated (Cloud-Init)** | Cloud VPS, reproducible setups | 5 min | Medium |
| **Terraform** | Infrastructure as Code, multi-server | Variable | High |
| **Ansible** | Configuration management, fleet deployment | Variable | High |
| **Docker** | Containerized environments | 5 min | Medium |

---

## Manual Deployment (Interactive)

Best for: One-off servers, learning the setup, development environments.

### Prerequisites

```bash
# Ensure you're on Ubuntu 22.04 or 24.04
lsb_release -a

# Update system packages
sudo apt update && sudo apt upgrade -y

# Ensure you have sufficient disk space (minimum 40GB free)
df -h
```

### Step 1: Connect to Your VPS

```bash
# SSH into your server
ssh root@your-vps-ip

# Or using key-based auth
ssh -i ~/.ssh/your-key.pem root@your-vps-ip
```

### Step 2: Download the Script

**Option A: Direct Download (Recommended)**
```bash
wget https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh
```

**Option B: Clone Repository**
```bash
apt install -y git
git clone https://github.com/andreas-tuko/vps-postgres-setup.git
cd vps-postgres-setup
```

**Option C: Upload via SCP**
```bash
# From your local machine
scp setup-postgres17.sh root@your-vps-ip:/root/
```

### Step 3: Make Executable and Run

```bash
chmod +x setup-postgres17.sh
sudo ./setup-postgres17.sh
```

### Step 4: Answer Interactive Prompts

The script will ask you a series of questions. Here are recommended answers for different scenarios:

#### Scenario 1: Single Application Database (Most Common)

```
DATABASE CONFIGURATION
├─ Listen addresses: 0.0.0.0
├─ Port: 5432
├─ Max connections: 200
└─ Memory settings: [Accept defaults]

SECURITY CONFIGURATION
├─ Allowed IPs: <your_app_server_ip>/32,<your_office_ip>/32
├─ Enable SSL: yes
├─ Enable firewall: yes
├─ Enable Fail2Ban: yes
└─ SSH port: 22

BACKUP CONFIGURATION
├─ Enable backups: yes
├─ Schedule: daily
├─ Retention: 14
├─ Compression: yes
└─ Remote backup: yes (if using S3)

HIGH AVAILABILITY
├─ WAL archiving: yes (recommended)
├─ Replication: no (unless you have standby server)

CONNECTION POOLING
├─ Enable PgBouncer: yes
├─ Port: 6432
├─ Pool mode: transaction
├─ Max client conn: 1000
└─ Default pool size: 25

MONITORING
├─ Enable monitoring: yes
├─ Log slow queries: yes (1000ms)
├─ Log connections: yes
└─ Retention: 30 days
```

#### Scenario 2: Development/Testing Server

```
DATABASE CONFIGURATION
├─ Listen addresses: localhost
├─ Port: 5432
├─ Max connections: 100
└─ Memory settings: [Accept defaults]

SECURITY CONFIGURATION
├─ Allowed IPs: 127.0.0.1/32
├─ Enable SSL: no
├─ Enable firewall: yes
├─ Enable Fail2Ban: yes
└─ SSH port: 22

BACKUP CONFIGURATION
├─ Enable backups: yes
├─ Schedule: daily
├─ Retention: 7
├─ Compression: yes
└─ Remote backup: no

HIGH AVAILABILITY
├─ WAL archiving: no
├─ Replication: no

CONNECTION POOLING
├─ Enable PgBouncer: yes
└─ [Accept defaults for other settings]

MONITORING
├─ Enable monitoring: yes
└─ [Accept defaults]
```

#### Scenario 3: High-Traffic Production Server

```
DATABASE CONFIGURATION
├─ Listen addresses: 0.0.0.0
├─ Port: 5432
├─ Max connections: 500
└─ Memory settings: [Review and adjust based on workload]

SECURITY CONFIGURATION
├─ Allowed IPs: <load_balancer_ip>/32,<app_servers_cidr>
├─ Enable SSL: yes
├─ Enable firewall: yes
├─ Enable Fail2Ban: yes
└─ SSH port: 22

BACKUP CONFIGURATION
├─ Enable backups: yes
├─ Schedule: hourly
├─ Retention: 30
├─ Compression: yes
└─ Remote backup: yes (S3)

HIGH AVAILABILITY
├─ WAL archiving: yes
├─ WAL destination: s3://your-bucket/wal-archive/
├─ Replication: yes
└─ Replication slots: 2

CONNECTION POOLING
├─ Enable PgBouncer: yes
├─ Port: 6432
├─ Pool mode: transaction
├─ Max client conn: 5000
└─ Default pool size: 50

MONITORING
├─ Enable monitoring: yes
├─ Log slow queries: yes (500ms)
├─ Log connections: yes
└─ Retention: 90 days
```

### Step 5: Verify Installation

```bash
# Check setup log
tail -50 /var/log/postgresql-setup/setup.log

# Run status check
sudo pg-status.sh

# Test connection
sudo -u postgres psql -c "SELECT version();"
```

---

## Automated Deployment (Unattended)

Best for: Cloud VPS provisioning, CI/CD pipelines, Infrastructure as Code.

### Method 1: Cloud-Init (User Data)

Most cloud providers support cloud-init. This method is ideal for DigitalOcean, AWS EC2, Linode, Vultr, etc.

#### Complete Cloud-Init Example

```yaml
#cloud-config

# Update system first
package_update: true
package_upgrade: true

# Write configuration file before running setup
write_files:
  - path: /etc/postgresql-setup.state
    permissions: '0600'
    content: |
      # PostgreSQL Enterprise Setup State File
      DB_LISTEN_ADDRESSES="0.0.0.0"
      DB_PORT="5432"
      DB_MAX_CONNECTIONS="200"
      DB_SHARED_BUFFERS="2048"
      DB_EFFECTIVE_CACHE="6144"
      DB_WORK_MEM="16"
      DB_MAINTENANCE_WORK_MEM="512"
      
      ALLOWED_IPS="10.0.1.100/32,10.0.2.0/24"
      ENABLE_SSL="yes"
      SSL_CERT_FILE="/etc/ssl/postgresql/server.crt"
      SSL_KEY_FILE="/etc/ssl/postgresql/server.key"
      ENABLE_FIREWALL="yes"
      ENABLE_FAIL2BAN="yes"
      SSH_PORT="22"
      
      ENABLE_BACKUPS="yes"
      BACKUP_SCHEDULE="daily"
      BACKUP_RETENTION_DAYS="14"
      BACKUP_COMPRESSION="yes"
      REMOTE_BACKUP_ENABLED="yes"
      REMOTE_BACKUP_TYPE="s3"
      S3_BUCKET="s3://my-postgres-backups/production/"
      S3_REGION="us-east-1"
      
      ENABLE_WAL_ARCHIVING="yes"
      WAL_ARCHIVE_DESTINATION="s3://my-postgres-backups/wal-archive/"
      ENABLE_REPLICATION="no"
      REPLICATION_SLOTS="0"
      
      ENABLE_PGBOUNCER="yes"
      PGBOUNCER_PORT="6432"
      PGBOUNCER_POOL_MODE="transaction"
      PGBOUNCER_MAX_CLIENT_CONN="1000"
      PGBOUNCER_DEFAULT_POOL_SIZE="25"
      
      ENABLE_MONITORING="yes"
      MONITORING_RETENTION_DAYS="30"
      LOG_DESTINATION="csvlog"
      LOG_MIN_DURATION="1000"
      LOG_CONNECTIONS="on"
      LOG_DISCONNECTIONS="on"
      
      SETUP_DATE="$(date)"
      SETUP_COMPLETE="false"

  - path: /root/.aws/credentials
    permissions: '0600'
    content: |
      [default]
      aws_access_key_id = YOUR_AWS_ACCESS_KEY
      aws_secret_access_key = YOUR_AWS_SECRET_KEY

  - path: /root/.aws/config
    permissions: '0600'
    content: |
      [default]
      region = us-east-1
      output = json

runcmd:
  # Download and run setup script
  - wget -O /root/setup-postgres17.sh https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh
  - chmod +x /root/setup-postgres17.sh
  - /root/setup-postgres17.sh 2>&1 | tee /var/log/cloud-init-postgres-setup.log
  
  # Create initial database and user
  - sleep 10
  - /usr/local/bin/pg-create-db-user.sh myapp myapp_user --owner-only
  
  # Send notification (optional)
  - 'curl -X POST -H "Content-Type: application/json" -d "{\"text\":\"PostgreSQL setup completed on $(hostname)\"}" YOUR_WEBHOOK_URL'

# Optionally set timezone
timezone: America/New_York

# Final message
final_message: "PostgreSQL 17 setup completed in $UPTIME seconds"
```

#### Minimal Cloud-Init Example

```yaml
#cloud-config

write_files:
  - path: /etc/postgresql-setup.state
    permissions: '0600'
    content: |
      DB_LISTEN_ADDRESSES="0.0.0.0"
      DB_PORT="5432"
      DB_MAX_CONNECTIONS="200"
      ALLOWED_IPS="0.0.0.0/0"
      ENABLE_SSL="no"
      ENABLE_FIREWALL="yes"
      ENABLE_FAIL2BAN="yes"
      SSH_PORT="22"
      ENABLE_BACKUPS="yes"
      BACKUP_SCHEDULE="daily"
      BACKUP_RETENTION_DAYS="7"
      BACKUP_COMPRESSION="yes"
      REMOTE_BACKUP_ENABLED="no"
      ENABLE_WAL_ARCHIVING="no"
      ENABLE_REPLICATION="no"
      ENABLE_PGBOUNCER="yes"
      PGBOUNCER_PORT="6432"
      PGBOUNCER_POOL_MODE="transaction"
      PGBOUNCER_MAX_CLIENT_CONN="1000"
      PGBOUNCER_DEFAULT_POOL_SIZE="25"
      ENABLE_MONITORING="yes"
      LOG_DESTINATION="csvlog"
      LOG_MIN_DURATION="1000"
      LOG_CONNECTIONS="on"
      LOG_DISCONNECTIONS="on"

runcmd:
  - wget -O /root/setup.sh https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh
  - chmod +x /root/setup.sh
  - /root/setup.sh
```

### Method 2: Terraform

Create infrastructure and deploy PostgreSQL in one workflow.

#### Terraform Configuration

**main.tf**
```hcl
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  default     = "nyc3"
}

variable "allowed_ips" {
  description = "IPs allowed to access PostgreSQL"
  type        = list(string)
  default     = ["10.0.1.100/32"]
}

provider "digitalocean" {
  token = var.do_token
}

# SSH Key
resource "digitalocean_ssh_key" "postgres" {
  name       = "PostgreSQL Server Key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Droplet
resource "digitalocean_droplet" "postgres" {
  image    = "ubuntu-24-04-x64"
  name     = "postgres-production"
  region   = var.region
  size     = "s-4vcpu-8gb"  # 4 vCPU, 8GB RAM
  ssh_keys = [digitalocean_ssh_key.postgres.id]
  
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    allowed_ips = join(",", var.allowed_ips)
  })
  
  tags = ["database", "postgresql", "production"]
}

# Firewall
resource "digitalocean_firewall" "postgres" {
  name = "postgres-firewall"
  
  droplet_ids = [digitalocean_droplet.postgres.id]
  
  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ips
  }
  
  # PostgreSQL
  inbound_rule {
    protocol         = "tcp"
    port_range       = "5432"
    source_addresses = var.allowed_ips
  }
  
  # PgBouncer
  inbound_rule {
    protocol         = "tcp"
    port_range       = "6432"
    source_addresses = var.allowed_ips
  }
  
  # Allow all outbound
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Volume for database storage
resource "digitalocean_volume" "postgres_data" {
  region      = var.region
  name        = "postgres-data"
  size        = 100  # 100GB
  description = "PostgreSQL data volume"
}

resource "digitalocean_volume_attachment" "postgres_data" {
  droplet_id = digitalocean_droplet.postgres.id
  volume_id  = digitalocean_volume.postgres_data.id
}

output "postgres_ip" {
  value       = digitalocean_droplet.postgres.ipv4_address
  description = "Public IP of PostgreSQL server"
}

output "connection_string" {
  value       = "postgresql://user:password@${digitalocean_droplet.postgres.ipv4_address}:6432/database"
  description = "PgBouncer connection string"
  sensitive   = true
}
```

**cloud-init.yaml** (template)
```yaml
#cloud-config

write_files:
  - path: /etc/postgresql-setup.state
    permissions: '0600'
    content: |
      DB_LISTEN_ADDRESSES="0.0.0.0"
      DB_PORT="5432"
      ALLOWED_IPS="${allowed_ips}"
      ENABLE_SSL="yes"
      ENABLE_FIREWALL="no"  # Using DigitalOcean firewall
      ENABLE_FAIL2BAN="yes"
      ENABLE_BACKUPS="yes"
      BACKUP_SCHEDULE="daily"
      ENABLE_PGBOUNCER="yes"

runcmd:
  - wget -O /root/setup.sh https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh
  - chmod +x /root/setup.sh
  - /root/setup.sh
```

**Deploy:**
```bash
terraform init
terraform plan
terraform apply

# Get outputs
terraform output postgres_ip
terraform output connection_string
```

### Method 3: Ansible Playbook

**playbook.yml**
```yaml
---
- name: Deploy PostgreSQL 17 Enterprise
  hosts: postgres_servers
  become: yes
  
  vars:
    pg_listen_addresses: "0.0.0.0"
    pg_port: 5432
    pg_max_connections: 200
    allowed_ips: "10.0.1.100/32,10.0.2.0/24"
    enable_ssl: "yes"
    enable_backups: "yes"
    backup_schedule: "daily"
    enable_pgbouncer: "yes"
    s3_bucket: "s3://my-backups/postgres/"
    aws_access_key: "{{ lookup('env', 'AWS_ACCESS_KEY_ID') }}"
    aws_secret_key: "{{ lookup('env', 'AWS_SECRET_ACCESS_KEY') }}"
  
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
    
    - name: Create state file
      copy:
        dest: /etc/postgresql-setup.state
        mode: '0600'
        content: |
          DB_LISTEN_ADDRESSES="{{ pg_listen_addresses }}"
          DB_PORT="{{ pg_port }}"
          DB_MAX_CONNECTIONS="{{ pg_max_connections }}"
          ALLOWED_IPS="{{ allowed_ips }}"
          ENABLE_SSL="{{ enable_ssl }}"
          ENABLE_FIREWALL="yes"
          ENABLE_FAIL2BAN="yes"
          SSH_PORT="22"
          ENABLE_BACKUPS="{{ enable_backups }}"
          BACKUP_SCHEDULE="{{ backup_schedule }}"
          BACKUP_RETENTION_DAYS="14"
          BACKUP_COMPRESSION="yes"
          REMOTE_BACKUP_ENABLED="yes"
          REMOTE_BACKUP_TYPE="s3"
          S3_BUCKET="{{ s3_bucket }}"
          S3_REGION="us-east-1"
          ENABLE_PGBOUNCER="{{ enable_pgbouncer }}"
          PGBOUNCER_PORT="6432"
          PGBOUNCER_POOL_MODE="transaction"
          ENABLE_MONITORING="yes"
    
    - name: Create AWS credentials
      copy:
        dest: /root/.aws/credentials
        mode: '0600'
        content: |
          [default]
          aws_access_key_id = {{ aws_access_key }}
          aws_secret_access_key = {{ aws_secret_key }}
    
    - name: Download setup script
      get_url:
        url: https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh
        dest: /root/setup-postgres17.sh
        mode: '0755'
    
    - name: Run setup script
      command: /root/setup-postgres17.sh
      register: setup_output
      changed_when: "'Setup completed' in setup_output.stdout"
    
    - name: Display setup output
      debug:
        var: setup_output.stdout_lines
    
    - name: Create application database
      command: /usr/local/bin/pg-create-db-user.sh myapp myapp_user --owner-only
      environment:
        PGPASSWORD: "{{ app_db_password }}"
```

**inventory.ini**
```ini
[postgres_servers]
prod-postgres-01 ansible_host=203.0.113.10 ansible_user=root

[postgres_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

**Run:**
```bash
ansible-playbook -i inventory.ini playbook.yml
```

### Method 4: Bash Script (Pre-seeded)

Simple bash script for quick automated deployment:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
VPS_IP="203.0.113.10"
SSH_KEY="~/.ssh/id_rsa"
ALLOWED_IPS="10.0.1.100/32"
S3_BUCKET="s3://my-backups/postgres/"

# Create state file content
STATE_FILE_CONTENT='DB_LISTEN_ADDRESSES="0.0.0.0"
DB_PORT="5432"
DB_MAX_CONNECTIONS="200"
ALLOWED_IPS="'"${ALLOWED_IPS}"'"
ENABLE_SSL="yes"
ENABLE_FIREWALL="yes"
ENABLE_FAIL2BAN="yes"
ENABLE_BACKUPS="yes"
BACKUP_SCHEDULE="daily"
BACKUP_RETENTION_DAYS="14"
REMOTE_BACKUP_ENABLED="yes"
S3_BUCKET="'"${S3_BUCKET}"'"
ENABLE_PGBOUNCER="yes"
PGBOUNCER_PORT="6432"'

# Upload and run
ssh -i "${SSH_KEY}" root@"${VPS_IP}" << 'ENDSSH'
  # Create state file
  cat > /etc/postgresql-setup.state << 'EOF'
${STATE_FILE_CONTENT}
EOF
  
  # Download and run setup
  wget -O /root/setup.sh https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh
  chmod +x /root/setup.sh
  /root/setup.sh
  
  # Verify
  /usr/local/bin/pg-status.sh
ENDSSH

echo "PostgreSQL setup completed on ${VPS_IP}"
```

---

## Cloud Provider-Specific Deployment

### DigitalOcean

```bash
# Install doctl
snap install doctl
doctl auth init

# Create droplet with cloud-init
doctl compute droplet create postgres-prod \
  --image ubuntu-24-04-x64 \
  --size s-4vcpu-8gb \
  --region nyc3 \
  --user-data-file cloud-init.yaml \
  --ssh-keys $(doctl compute ssh-key list --format ID --no-header) \
  --wait

# Get IP
doctl compute droplet get postgres-prod --format PublicIPv4 --no-header
```

### AWS EC2

```bash
# Launch instance with user data
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \  # Ubuntu 24.04 (verify current AMI)
  --instance-type t3.xlarge \
  --key-name your-key-pair \
  --security-group-ids sg-xxxxxxxxx \
  --subnet-id subnet-xxxxxxxxx \
  --user-data file://cloud-init.yaml \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=postgres-prod}]' \
  --block-device-mappings '[
    {
      "DeviceName": "/dev/sda1",
      "Ebs": {
        "VolumeSize": 100,
        "VolumeType": "gp3",
        "Iops": 3000,
        "DeleteOnTermination": false
      }
    }
  ]'
```

### Linode

```bash
# Install Linode CLI
pip3 install linode-cli

# Create Linode
linode-cli linodes create \
  --label postgres-prod \
  --region us-east \
  --type g6-standard-4 \
  --image linode/ubuntu24.04 \
  --root_pass 'secure_root_password' \
  --authorized_keys "$(cat ~/.ssh/id_rsa.pub)" \
  --stackscript_data '{"user_data": "'"$(base64 cloud-init.yaml)"'"}'
```

### Vultr

```bash
# Via Vultr API
curl "https://api.vultr.com/v2/instances" \
  -X POST \
  -H "Authorization: Bearer ${VULTR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "region": "ewr",
    "plan": "vc2-4c-8gb",
    "os_id": 1743,
    "user_data": "'"$(base64 -w 0 cloud-init.yaml)"'"
  }'
```

### Hetzner Cloud

```bash
# Install hcloud CLI
brew install hcloud  # or: snap install hcloud

# Create server
hcloud server create \
  --name postgres-prod \
  --type cx31 \
  --image ubuntu-24.04 \
  --ssh-key your-key \
  --user-data-from-file cloud-init.yaml \
  --location nbg1
```

---

## Configuration Variables Reference

Complete list of all configuration variables:

### Database Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `DB_LISTEN_ADDRESSES` | string | `0.0.0.0` | Comma-separated IPs to listen on. Use `localhost` for local only, `*` or `0.0.0.0` for all interfaces |
| `DB_PORT` | integer | `5432` | PostgreSQL port |
| `DB_MAX_CONNECTIONS` | integer | `200` | Maximum concurrent connections |
| `DB_SHARED_BUFFERS` | integer | auto | Shared memory buffer size (MB). Auto-calculated as 25% of RAM |
| `DB_EFFECTIVE_CACHE` | integer | auto | Estimated OS cache size (MB). Auto-calculated as 75% of RAM |
| `DB_WORK_MEM` | integer | auto | Memory per query operation (MB) |
| `DB_MAINTENANCE_WORK_MEM` | integer | auto | Memory for maintenance operations (MB) |

### Security Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ALLOWED_IPS` | string | `127.0.0.1/32` | Comma-separated CIDRs allowed to connect. Example: `10.0.1.5/32,192.168.0.0/24` |
| `ENABLE_SSL` | yes/no | `yes` | Enable SSL/TLS for encrypted connections |
| `SSL_CERT_FILE` | path | `/etc/ssl/postgresql/server.crt` | Path to SSL certificate |
| `SSL_KEY_FILE` | path | `/etc/ssl/postgresql/server.key` | Path to SSL private key |
| `ENABLE_FIREWALL` | yes/no | `yes` | Configure UFW firewall |
| `ENABLE_FAIL2BAN` | yes/no | `yes` | Enable Fail2Ban intrusion prevention |
| `SSH_PORT` | integer | `22` | SSH port for firewall rules |

### Backup Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ENABLE_BACKUPS` | yes/no | `yes` | Enable automated backups |
| `BACKUP_SCHEDULE` | string | `daily` | Backup frequency: `hourly`, `daily`, `weekly` |
| `BACKUP_RETENTION_DAYS` | integer | `14` | Days to keep local backups |
| `BACKUP_COMPRESSION` | yes/no | `yes` | Use compressed custom format |
| `REMOTE_BACKUP_ENABLED` | yes/no | `no` | Upload backups to cloud storage |
| `REMOTE_BACKUP_TYPE` | string | `s3` | Cloud storage type: `s3`, `azure`, `gcs` |
| `S3_BUCKET` | string | - | S3 bucket URI (e.g., `s3://bucket-name/path/`) |
| `S3_REGION` | string | `us-east-1` | AWS region |

### High Availability

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ENABLE_WAL_ARCHIVING` | yes/no | `no` | Enable Write-Ahead Log archiving |
| `WAL_ARCHIVE_DESTINATION` | string | - | Local path or S3 URI for WAL files |
| `ENABLE_REPLICATION` | yes/no | `no` | Configure for streaming replication |
| `REPLICATION_SLOTS` | integer | `2` | Number of replication slots |

### Connection Pooling

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ENABLE_PGBOUNCER` | yes/no | `yes` | Install and configure PgBouncer |
| `PGBOUNCER_PORT` | integer | `6432` | PgBouncer listen port |
| `PGBOUNCER_POOL_MODE` | string | `transaction` | Pool mode: `session`, `transaction`, `statement` |
| `PGBOUNCER_MAX_CLIENT_CONN` | integer | `1000` | Maximum client connections |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | integer | `25` | Default pool size per database/user |

### Monitoring & Logging

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ENABLE_MONITORING` | yes/no | `yes` | Enable metrics collection |
| `MONITORING_RETENTION_DAYS` | integer | `30` | Days to keep metrics |
| `LOG_DESTINATION` | string | `csvlog` | Log format: `stderr`, `csvlog`, `syslog` |
| `LOG_MIN_DURATION` | integer | `1000` | Log queries slower than N milliseconds (0 for all) |
| `LOG_CONNECTIONS` | on/off | `on` | Log connection attempts |
| `LOG_DISCONNECTIONS` | on/off | `on` | Log disconnections |

---

## Post-Deployment Tasks

### 1. Secure the Postgres User

```bash
# Set a strong password for postgres superuser
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'generate_strong_password_here';"

# Store password in password manager
```

### 2. Create Application Database

```bash
# Interactive creation
sudo pg-create-db-user.sh myapp myapp_user

# Enter password when prompted
# Password will be automatically added to PgBouncer
```

### 3. Configure Application Connection

Update your application's environment variables:

```bash
# .env file
DATABASE_URL=postgresql://myapp_user:password@localhost:6432/myapp
```

### 4. Test Connections

```bash
# Test direct connection
psql -h localhost -p 5432 -U myapp_user -d myapp

# Test PgBouncer connection
psql -h localhost -p 6432 -U myapp_user -d myapp

# Test from application server (if different)
psql -h postgres-server-ip -p 6432 -U myapp_user -d myapp
```

### 5. Configure AWS Credentials (if using S3 backups)

```bash
# Create AWS credentials file
sudo mkdir -p /root/.aws
sudo cat > /root/.aws/credentials << EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
EOF

sudo chmod 600 /root/.aws/credentials

# Test S3 access
sudo aws s3 ls s3://your-bucket-name/
```

### 6. Run Initial Backup

```bash
# Run manual backup
sudo pg-backup.sh

# Verify backup was created
ls -lh /var/backups/postgresql/

# Verify S3 upload (if configured)
sudo aws s3 ls s3://your-bucket/postgresql-backups/$(hostname)/
```

### 7. Set Up Monitoring Alerts

```bash
# Create monitoring check script
cat > /usr/local/bin/pg-health-check.sh << 'EOF'
#!/bin/bash
# Check PostgreSQL health and send alerts

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
  echo "ALERT: PostgreSQL is down!" | mail -s "PostgreSQL Down" admin@example.com
  exit 1
fi

# Check disk space (alert if >80%)
DISK_USAGE=$(df /var/lib/postgresql | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
  echo "ALERT: Disk usage is ${DISK_USAGE}%" | mail -s "PostgreSQL Disk Alert" admin@example.com
fi

# Check connection count
CONN_COUNT=$(sudo -u postgres psql -tAc "SELECT count(*) FROM pg_stat_activity;")
if [ "$CONN_COUNT" -gt 180 ]; then
  echo "ALERT: High connection count: ${CONN_COUNT}" | mail -s "PostgreSQL Connection Alert" admin@example.com
fi
EOF

chmod +x /usr/local/bin/pg-health-check.sh

# Add to cron (every 5 minutes)
echo "*/5 * * * * root /usr/local/bin/pg-health-check.sh" | sudo tee /etc/cron.d/pg-health-check
```

### 8. Document Your Setup

Create a runbook:

```bash
# Create documentation directory
sudo mkdir -p /opt/postgresql-docs

# Document your configuration
sudo cat > /opt/postgresql-docs/RUNBOOK.md << 'EOF'
# PostgreSQL Production Runbook

## Server Information
- Hostname: postgres-prod-01
- IP Address: 203.0.113.10
- PostgreSQL Version: 17
- PgBouncer Port: 6432

## Databases
- myapp (owner: myapp_user)

## Maintenance Schedule
- Backups: Daily at 2:00 AM
- Vacuum: Weekly on Sundays at 3:00 AM
- Updates: Monthly (second Tuesday)

## Emergency Contacts
- DBA: dba@example.com
- On-Call: +1-555-0100

## Common Tasks
[Link to tasks in README.md]
EOF
```

---

## Production Deployment Checklist

Before going live, verify:

### Security
- [ ] Changed postgres superuser password
- [ ] Reviewed and restricted `ALLOWED_IPS`
- [ ] SSL/TLS enabled and tested
- [ ] Firewall rules verified (`sudo ufw status`)
- [ ] Fail2Ban active (`sudo fail2ban-client status`)
- [ ] SSH key-based auth enabled (password auth disabled)
- [ ] Non-standard SSH port configured (optional)

### Backups
- [ ] Automated backups configured
- [ ] Backup retention policy set
- [ ] Remote backups configured (S3/cloud)
- [ ] WAL archiving enabled (if needed)
- [ ] Test restore performed successfully
- [ ] Backup monitoring/alerts configured

### Performance
- [ ] Memory settings tuned for workload
- [ ] Connection pooling configured (PgBouncer)
- [ ] Autovacuum settings reviewed
- [ ] Query logging configured
- [ ] Slow query threshold set appropriately

### Monitoring
- [ ] Status monitoring enabled
- [ ] Disk space alerts configured
- [ ] Connection count monitoring
- [ ] Log aggregation configured
- [ ] External monitoring integrated (optional)

### High Availability
- [ ] Replication configured (if multi-server)
- [ ] Failover procedure documented
- [ ] Backup server tested

### Documentation
- [ ] Connection strings documented
- [ ] Runbook created
- [ ] Credentials stored in password manager
- [ ] On-call contacts defined
- [ ] Maintenance windows scheduled

### Testing
- [ ] Application can connect via PgBouncer
- [ ] SSL connections work
- [ ] Backup and restore tested
- [ ] Failover tested (if HA setup)
- [ ] Load testing performed

---

## Deployment Troubleshooting

### Setup Script Fails

**Problem:** Script exits with error during installation.

```bash
# Check setup log
tail -100 /var/log/postgresql-setup/setup.log

# Check system logs
sudo journalctl -xe

# Common issues:
# 1. Insufficient disk space
df -h

# 2. Network connectivity
ping -c 3 apt.postgresql.org

# 3. Permission denied
ls -la /etc/postgresql-setup.state
```

### Cloud-Init Not Running

**Problem:** Script doesn't run automatically on cloud VPS.

```bash
# Check cloud-init status
cloud-init status

# View cloud-init logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# Re-run cloud-init
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode config
sudo cloud-init modules --mode final
```

### S3 Backup Upload Fails

**Problem:** Backups don't upload to S3.

```bash
# Test AWS credentials
sudo aws s3 ls

# Check IAM permissions (need: s3:PutObject, s3:GetObject, s3:ListBucket)
sudo aws s3 cp /tmp/test.txt s3://your-bucket/test.txt

# Verify bucket exists
sudo aws s3 mb s3://your-bucket-name
```

### Cannot Connect from Application

**Problem:** Application can't connect to PostgreSQL.

```bash
# 1. Check PostgreSQL is running
sudo systemctl status postgresql

# 2. Check listening addresses
sudo netstat -tlnp | grep 5432

# 3. Test local connection
sudo -u postgres psql -c "SELECT 1;"

# 4. Check pg_hba.conf
sudo cat /etc/postgresql/17/main/pg_hba.conf

# 5. Check firewall
sudo ufw status
sudo iptables -L -n | grep 5432

# 6. Test from application server
telnet postgres-ip 5432
psql -h postgres-ip -U username -d database
```

### High Memory Usage

**Problem:** PostgreSQL consuming too much memory.

```bash
# Check memory usage
free -h
sudo ps aux | grep postgres | head -20

# Review shared_buffers setting
sudo grep shared_buffers /etc/postgresql/17/main/postgresql.conf

# Reduce if needed
sudo vim /etc/postgresql/17/main/postgresql.conf
# Set: shared_buffers = 2GB (for example)

sudo pg-restart.sh
```

---

## Support

For issues or questions:

1. Check [README.md](README.md) for general usage
2. Review setup logs: `/var/log/postgresql-setup/setup.log`
3. Open an issue on GitHub
4. Consult [PostgreSQL documentation](https://www.postgresql.org/docs/17/)

---

**Last Updated:** February 2024  
**Script Version:** 1.0.0
