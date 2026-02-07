# Contributing to VPS Postgres Setup

First off, thank you for considering contributing to this project! It's people like you that make the open-source community such an amazing place to learn, inspire, and create.

## 📌 Core Philosophy: Idempotency
The most important rule for this project is **Idempotency**.
- This script is designed to be run multiple times on the same server without breaking anything.
- **Rule:** If a user runs the script a second time, it should detect existing configurations and skip/update them safely, rather than overwriting them blindly or failing.

## 🐛 Reporting Bugs
Bugs are tracked as GitHub issues. When filing an issue, please include:
- **OS Version:** (e.g., Ubuntu 24.04 LTS)
- **Script Output:** Copy-paste the relevant logs or error messages.
- **State File:** If safe, share the contents of `/etc/pg-setup.conf` (redact sensitive keys).

## 💡 Suggesting Enhancements
1. **Check existing issues** to see if your idea has already been discussed.
2. **Open a new issue** describing the improvement.
3. **Context:** Explain *why* this change is beneficial (e.g., "Improves security," "Reduces memory usage").

## 🛠 Pull Requests
1. **Fork the repo** and create your branch from `main`.
2. **Test your changes:**
   - Run the script on a **fresh** Ubuntu 24.04 VM or LXC container.
   - Run the script **twice** to verify idempotency.
   - Verify that PostgreSQL and PgBouncer services are active (`systemctl status postgresql pgbouncer`).
3. **Code Style:**
   - Use `bash` best practices.
   - Use `log()` for outputting messages.
   - Ensure variables are quoted to prevent word splitting.
4. **Documentation:** If you add a new feature, update `README.md` and the relevant prompts in the script.

## 🧪 Testing Locally
The easiest way to test changes is using a local VM (VirtualBox) or a cloud instance (DigitalOcean/AWS/Hetzner) that you can destroy afterwards.

**Sanity Check List:**
- [ ] Does `setup-postgres17.sh` run without errors on a fresh install?
- [ ] Does it run without errors on a *second* pass?
- [ ] Can you connect to port `5432` (Postgres) and `6432` (PgBouncer)?
- [ ] Do the backup/restore scripts (`/usr/local/bin/pg_*`) work?

## 📜 License
By contributing, you agree that your contributions will be licensed under the MIT License.
