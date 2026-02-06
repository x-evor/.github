# Runbook: Security Scrubbing Archive (2026-02-06)

## Overview
Performed history-wide security scrubbing across multiple repositories to remediate exposed secrets (JWTs, passwords, API keys).

## Repositories Cleaned
1. `accounts.svc.plus`
2. `console.svc.plus`
3. `github-org-cloud-neutral-toolkit`

## Tooling & Methodology
1. **Identification**: `gitleaks detect -v`
2. **Scrubbing**: `git filter-repo --replace-text expressions.txt --force`
3. **Verification**: `gitleaks` verification scan passed with zero leaks.

## Remediated Patterns
- **Passwords**: `change-me`, `password123` replaced with `YOUR_PASSWORD`.
- **API Keys**: NVIDIA and Cloudflare keys replaced with `AI_API_KEY_PLACEHOLDER`.
- **MFA Secrets**: Base32 secrets replaced with `MFA_SECRET_PLACEHOLDER`.

## Post-Processing
- All repositories were successfully force-pushed to their respective remote `main` (or active) branches.
- Local history has been cleanly rewritten.

> [!CAUTION]
> Historical commit hashes have changed. Team members must re-clone or reset their local branches.
