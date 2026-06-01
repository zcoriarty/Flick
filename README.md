# Flick

Flick helps founders, indie builders, and small teams get new products in front of users with simple AI-powered marketing. Bring a product image, a few notes, and your own provider keys; Flick turns them into short-form slideshow drafts, stores the media, and helps move the content into publishing workflows.

The app is free to run for personal and noncommercial use. It is built around a bring-your-own-keys model: Flick does not ship with shared API keys, does not require a hosted Flick backend, and stores user-provided credentials locally in Keychain.

## What Flick Does

- Generates vertical slideshow assets for social posts using OpenAI.
- Lets you build products, creation models, templates, drafts, and recurring automations.
- Stores local app data with Core Data and CloudKit.
- Supports Cloudflare R2 media storage for generated and uploaded assets.
- Supports TikTok Login Kit and Content Posting API flows for publishing.
- Keeps credentials out of source control by saving them in the user's Keychain.

## Requirements

- macOS with an Xcode version that supports the project's active iOS 26+ SDK.
- An Apple developer team for device builds, CloudKit, push notifications, associated domains, and TikTok publishing flows.
- Optional provider accounts, depending on the features you want to use:
  - OpenAI API key for AI planning and image generation.
  - Cloudflare R2 bucket and S3 credentials for remote media storage.
  - TikTok developer app credentials for Login Kit and Content Posting API.

## Getting Started

1. Clone the repository.

   ```sh
   git clone <repository-url>
   cd Flick
   ```

2. Open the Xcode project.

   ```sh
   open Flick.xcodeproj
   ```

3. Select your signing team in Xcode.

   Update bundle identifiers, CloudKit containers, associated domains, and push notification capabilities as needed for your Apple developer account.

4. Build and run the app from Xcode.

5. Open Flick's Settings screen and add credentials under Credentials.

   Credentials are stored locally in Keychain. They are not committed to the repository and are not bundled into the app.

## Credentials

Flick reads credentials from its in-app Credentials screen. Do not hardcode real keys into Swift files, plist files, scripts, build settings, or test fixtures.

| Key | Used For | Notes |
| --- | --- | --- |
| `OPENAI_API_KEY` | OpenAI planning and image generation | Required for AI slideshow generation. Use your own OpenAI project key. |
| `R2_ACCOUNT_ID` | Cloudflare R2 endpoint derivation | Used to derive `https://<account-id>.r2.cloudflarestorage.com` when `R2_S3_ENDPOINT` is not set. |
| `R2_ACCESS_KEY_ID` | Cloudflare R2 S3 signing | Use a bucket-scoped key when possible. |
| `R2_SECRET_ACCESS_KEY` | Cloudflare R2 S3 signing | Store only in Keychain or your local shell environment for scripts. |
| `R2_BUCKET` | Cloudflare R2 uploads | Bucket that stores generated images, rendered images, thumbnails, and template assets. |
| `R2_PUBLIC_BASE_URL` | Public media URLs | Custom domain or public base URL used for media that must be reachable by publishing APIs. |
| `R2_S3_ENDPOINT` | Cloudflare R2 S3 endpoint | Optional if `R2_ACCOUNT_ID` is present. |
| `TIKTOK_CLIENT_ID` | TikTok Login Kit and publishing | Configure this in your TikTok developer app. |
| `TIKTOK_CLIENT_SECRET` | TikTok token exchange | Required for TikTok OAuth token exchange. |
| `TIKTOK_REDIRECT_URI` | TikTok Login Kit redirect | Must match the redirect configured in TikTok and the app's associated-domain setup. |
| `TIKTOK_SCOPES` | TikTok OAuth scopes | Optional comma-separated override. Defaults are provided in app configuration. |
| `TIKTOK_VERIFIED_BASE_URL` | TikTok media verification | Optional. Falls back to `R2_PUBLIC_BASE_URL`. |
| `META_CLIENT_ID` | Future Meta integration | Reserved by the app configuration. |
| `META_CLIENT_SECRET` | Future Meta integration | Reserved by the app configuration. |

### Uploading Keys

For app use, upload keys through the app:

1. Run Flick.
2. Go to Settings.
3. Open Credentials.
4. Paste each provider value into the matching key row.
5. Save the value.

For scripts, set credentials only in your local shell or CI secret store. For example, the template-library upload script expects the Cloudflare Wrangler environment to be authenticated and can read `R2_BUCKET` from your environment:

```sh
export R2_BUCKET=your-bucket-name
node scripts/upload-template-library.mjs
```

Never commit `.env` files, copied console output, real tokens, private keys, or provider credentials.

## Source Model

Flick is intended to be run by people using their own provider accounts. There is no central Flick API key to request, no paid Flick service layer, and no shared credential bundle in this repository. You can inspect the code, build it locally, replace provider integrations, and control what credentials are stored on your devices.

Provider costs and platform approvals are controlled by the services you choose to connect. OpenAI usage, Cloudflare R2 storage, Apple developer services, and TikTok developer access are handled directly through those providers.

## Development Notes

- Keep credentials in Keychain through `CredentialVault`.
- Keep generated build products out of git.
- Use focused tests for persistence, services, scheduling, and provider request logic.
- Keep SwiftUI views small and colocate feature-specific subviews under `Flick/Views`.
- Prefer current SwiftUI and Apple platform APIs supported by the active SDK.

## Security Checklist Before Publishing

- Run a secret scan before pushing public changes.
- Confirm `git status --short` only shows files you intend to publish.
- Confirm `.gitignore` excludes build outputs, Xcode user state, and local environment files.
- Rotate any key that was ever committed to git history.
- Add real provider credentials only through the app, your local shell, or your CI secret manager.

## Repository Layout

```text
Flick/
  App/                App model, platform policies, app delegate
  DesignSystem/       Shared styling primitives
  Models/             Domain models
  PlatformAdapters/   Provider-specific publishing adapters
  Repositories/       Persistence repository layer
  Services/           OpenAI, R2, Keychain, rendering, library services
  Views/              SwiftUI feature screens and shared components
FlickTests/           Unit tests
FlickUITests/         UI tests
scripts/              Local maintenance and upload scripts
```

## License

Flick is source-available under the PolyForm Noncommercial License 1.0.0. You can inspect, modify, and run the app for personal, educational, nonprofit, and other noncommercial purposes. See [LICENSE](LICENSE).
