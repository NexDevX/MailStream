# Architecture Baseline

## Goals

- Keep UI work fast without letting view code absorb business logic
- Make mailbox data sources replaceable without rewriting screens
- Keep macOS-specific behavior isolated from domain and feature code
- Preserve a clean path from local build to CI release artifacts

## Repository Layers

### Product Source

- `MailClient/App`
  - Application entrypoint
  - Dependency composition
  - Global app state
- `MailClient/Core`
  - Domain models
  - Service protocols
  - Repository contracts
  - Storage implementations
  - Logging and utilities
- `MailClient/Features`
  - Feature-facing views and feature-local presentation logic
- `MailClient/SharedUI`
  - Reusable components, theme tokens, and shared styles
- `MailClient/Platform`
  - macOS-specific bridging and desktop integration
- `MailClient/Tests`
  - Unit and integration-style tests for the app module

### Engineering Infrastructure

- `.github/workflows`
  - CI build and release automation
- `scripts`
  - Deterministic local and CI entrypoints
- `docs`
  - Architectural and release documentation
- `project.yml`
  - XcodeGen source of truth for the Xcode project
- `Makefile`
  - Consistent developer command entrypoints

## Dependency Rules

- `App` can depend on every product layer
- `Core` must not import `SwiftUI` or feature modules
- `Features` can depend on `Core`, `SharedUI`, and `Platform`
- `Platform` must not own product business logic
- `SharedUI` must stay presentation-only
- Workflows and scripts cannot become a second source of truth for app structure

## Data Flow

1. `MailClientApp` builds the dependency container
2. `AppContainer` provides repositories and long-lived services
3. `AppState` reads initial mailbox state through `MailRepository`
4. `Features` render from `AppState`
5. `MailSyncService` can later refresh repositories without changing the feature layer contract

## Current Implementations

- `MailRepository`
  - Contract for loading mailbox data
- `InMemoryMailRepository`
  - Seed-backed implementation for the current prototype
- `SeedMailboxData`
  - Static fixture source isolated from the domain model

This keeps the prototype data in the storage layer, not in the model layer.

## Release Flow

- `make package` or `./scripts/build_dmg.sh`
  - Local DMG build
- `push main`
  - GitHub Actions builds a DMG and refreshes the `latest-main` prerelease
- `push v* tag`
  - GitHub Actions builds a DMG and publishes a tagged GitHub Release

## Next Engineering Steps

- Replace `InMemoryMailRepository` with a local persistence-backed repository
- Split feature views from feature-specific view models once interactions grow
- Add signed release and notarization scripts
- Introduce lint and formatting in CI once the code surface grows
