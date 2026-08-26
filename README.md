# Dumpify

Android firmware dump tool powered by GitHub Actions.

## Quick Start

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/anonytry/Dumpify/master/bootstrap.sh)"
```

## First Time Setup

1. Fork this repository
2. Go to your fork → Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `USER_TOKEN`
5. Value: Your GitHub token (with `repo` scope)
6. Click "Add secret"

## How to Use

After first time setup, just run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/anonytry/Dumpify/master/bootstrap.sh)"
```

Enter:
- Your forked repo URL
- Your GitHub token (for trigger only, not stored)
- OTA/ROM URL

Wait for results. Fingerprint and device info appear in the Actions run summary.

## How It Works

1. Bootstrap script triggers GitHub Actions in your fork
2. Actions download and extract the OTA
3. Extracted files pushed to your repo as a new branch
4. Dump link printed on your terminal
5. Fingerprint + device info shown in the Actions run summary
6. Cleanup - everything clean

## Supported File Types

- `.zip`, `.tgz`, `.tar.gz`
- `.img` (raw images)
- `.mbn`, `.ozip`
- OTA packages from major manufacturers

## Repository Structure

```
YourRepo/
├── master (code)
├── google-husky-15-... (dump branch)
├── samsung-a55-14-... (dump branch)
└── ...
```

## Token Security

- Your token is NEVER stored in files
- Used only for API call to trigger workflow
- GitHub Actions masks tokens in logs (***)
- Token scope: `repo` (required for workflow trigger)

## Credits

Based on [dumpyara](https://github.com/Jiovanni-dump/dumpyara) by Jiovanni-dump.
