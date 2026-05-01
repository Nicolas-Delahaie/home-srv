# Checklist: Adding a New Service

This document lists the steps to remember when creating a new service.

## Required Steps

1. **CrowdSec**: look for a collection that covers the service's logs
2. **Traefik labels**: add the `errp-redirect@file` middleware
3. **Volumes**: add `:ro` whenever possible. Use a **named volume** for opaque runtime data (DBs, caches, internal state) and a **bind mount** only when files inside are versioned in git or edited/inspected manually
4. **Environment variables**: if there are many, split between `env_file` and `environment`
5. **Documentation**: document the required and optional steps in the README

## Best Practices

1. Star the service's GitHub repository to track version updates
2. Prefer a single folder per service. If services are related, group them in a parent folder
3. Properly exclude sensitive values from version control — `.env` + `.gitignore`
4. Persist configurations as much as possible to keep the repository plug-and-play, pre-configured from the first pull
