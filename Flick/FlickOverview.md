Flick — Product & Technical Architecture Spec

Last updated: May 11, 2026
Platforms: iOS 26+, macOS 26+
Primary platform integration: TikTok Content Posting API
Future platform integrations: Instagram, Threads, X
Architecture: SwiftUI, MVVM, Core Data + CloudKit, AVFoundation, Cloudflare R2

⸻

1. Product Summary

Flick is a native Apple-platform app for creating, scheduling, publishing, and analyzing short-form social marketing content for an iOS app.

The first version focuses on TikTok because approved API access already exists. Flick should be designed from day one as a multi-platform publishing system so Instagram, Threads, Youtube Shorts, and X can be added later without rewriting the creative pipeline, scheduler, analytics model, or account management layer.

Flick runs on both macOS and iPhone:

* Mac app: primary automation worker, scheduler, media renderer, uploader, and publisher.
* iPhone app: monitoring, approvals, light edits, account/status checks, manual actions, and performance review.
* CloudKit: syncs structured app state between devices.
* Cloudflare R2: stores generated slideshow images and publicly accessible media URLs for platform APIs that require URL-based media ingestion.
* Core Data: local-first persistence layer.
* AVFoundation: local video/slideshow rendering.

⸻

2. Product Goals

Primary Goals

1. Connect and manage multiple social accounts.
2. Generate TikTok-style slideshow creatives.
3. Overlay clean, readable text on generated or uploaded images.
4. Store slideshow images in Cloudflare R2 object storage.
5. Publish TikTok slideshows through the approved TikTok API flow.
6. Schedule posts on a defined cadence.
7. Let the Mac perform autonomous work while iPhone monitors and controls the queue.
8. Track post performance and identify the best-performing templates, hooks, trends, captions, and accounts.
9. Support a trend library based on TikTok Creative Center and manually added reference images.
10. Keep the system extensible for Instagram, Threads, and X.

Non-Goals for V1

1. Do not scrape TikTok directly.
2. Do not automate browser sessions or simulate user behavior.
3. Do not require a paid server for the core app.
4. Do not store large binary media in CloudKit.
5. Do not put sensitive API secrets, TikTok tokens, or Cloudflare R2 write credentials in CloudKit.
6. Do not optimize for Android, web, or Windows.

⸻

3. Key Product Decisions

3.1 Use Core Data + CloudKit

Use NSPersistentCloudKitContainer rather than a custom sync layer because it is mature, native, local-first, and well suited for syncing structured app state between the Mac and iPhone.

CloudKit should sync:

* accounts metadata
* content drafts
* creative templates
* trend tags
* generated asset metadata
* post queues
* publishing jobs
* analytics snapshots
* user settings
* workflow state

CloudKit should not sync:

* raw generated images
* rendered videos
* OAuth secrets
* API tokens
* Cloudflare R2 write credentials
* large temporary render files

3.2 Use Cloudflare R2 for Media

Cloudflare R2 stores generated slideshow images and potentially rendered videos.

Use Cloudflare R2 for:

* generated image assets
* manually uploaded trend/reference images
* public or signed media URLs
* TikTok slideshow image URL ingestion
* reusable asset library

Use Core Data + CloudKit for the metadata pointing to Cloudflare R2 objects.

Example metadata stored in Core Data:

Asset {
    id: UUID
    localFileURL: URL?
    remoteStoragePath: String?
    publicURL: URL?
    signedURLExpiration: Date?
    mediaType: AssetMediaType
    width: Int
    height: Int
    source: AssetSource
    trendTags: Set<TrendTag>
    createdAt: Date
    updatedAt: Date
}

3.3 TikTok Slideshow Support

Path A — True photo slideshow

Use this when publishing TikTok photo/slideshow posts.

Pipeline:

Generate images locally
→ Upload each image to Cloudflare R2
→ Ensure each URL is publicly accessible and compatible with TikTok URL ingestion
→ Initialize TikTok photo post
→ Publish or upload through TikTok Content Posting API
→ Store publish status and platform post ID

Important implementation note: TikTok photo publishing expects PULL_FROM_URL image URLs. The URLs must be publicly accessible and verified by the app/domain or URL prefix. Flick should use the Cloudflare R2 custom domain or a configured verified URL prefix for hosted media.

⸻

4. UX and Design Direction

4.1 Design Language

Flick should feel like a modern Apple productivity app:

* minimal
* clean
* calm
* information-dense only where needed
* fast to scan
* native controls first
* Liquid Glass throughout
* strong use of hierarchy, spacing, and previews
* no “growth-hacker dashboard clutter”

4.2 iOS 26+ and macOS 26+

Use the latest Apple APIs and design guidance for Liquid Glass.

Guidelines:

* Prefer standard SwiftUI components that automatically adopt the current platform look.
* Use custom Liquid Glass effects sparingly for cards, controls, inspector panels, and floating toolbars.
* Maintain high contrast and legibility.
* Avoid decorative glass where text readability matters.
* Keep destructive publishing actions visually distinct.
* Support light/dark mode.
* Support Dynamic Type where reasonable.
* Keep the iPhone app focused on triage, approvals, monitoring, and quick edits.

4.3 Main Navigation

Use a shared app structure across iOS and macOS, with platform-specific presentation.

Recommended tabs/sections:

1. Dashboard
2. Create
3. Queue
4. Trends
5. Analytics
6. Accounts
7. Settings

Dashboard

Purpose: current system health and high-level status.

Shows:

* posts scheduled today
* posts awaiting approval
* failed jobs
* best-performing recent post
* active Mac worker status
* connected accounts status
* sync status
* TikTok API health/status
* quick action: “Generate batch”

Create

Purpose: generate and edit creatives.

Features:

* generate slideshow from prompt
* generate from trend template
* generate from app feature
* generate from previous winner
* edit slide text
* reorder slides
* replace image
* preview TikTok slideshow
* preview rendered MP4
* save as draft
* send to queue

Queue

Purpose: control scheduled publishing.

Features:

* calendar/list view
* per-account queue
* cadence rules
* approval state
* retries
* failed job diagnostics
* pause/resume automation
* post now
* duplicate and remix

Trends

Purpose: manage inspiration and creative patterns.

Features:

* manually add trend
* add images/screenshots
* assign trend tags
* record source URL
* record notes
* classify style
* link trends to generated creatives
* mark trend as active, testing, archived, or winning

Trend tags can include:

* hook format
* visual layout
* niche
* emotion
* content angle
* CTA style
* slide count
* pacing
* text density
* app feature promoted
* audience segment

Analytics

Purpose: learn what works.

Shows:

* top posts by views
* top posts by engagement rate
* top hooks
* top templates
* top trend tags
* best posting times
* account comparison
* generated vs manually edited performance
* slideshow vs video performance
* historical performance per app feature
* recommended next experiments

Accounts

Purpose: manage connected social accounts.

Features:

* TikTok OAuth connection
* account status
* scopes
* token status
* publish permissions
* rate/cadence limits
* default privacy settings
* platform-specific settings

Settings

Purpose: app-level configuration.

Features:

* Cloudflare R2 credentials/config
* storage bucket and object prefixes
* worker device role
* API credentials status
* local render directory
* default cadence
* notification preferences
* CloudKit sync diagnostics
* export/import diagnostics

⸻

5. System Architecture

Flick iOS App                         Flick macOS App
────────────────                     ────────────────────────────────
SwiftUI UI                            SwiftUI UI
MVVM ViewModels                       MVVM ViewModels
Core Data local store                 Core Data local store
CloudKit sync                         CloudKit sync
Monitoring/actions                    Scheduler + automation worker
Light editing                         AVFoundation rendering
Approval controls                     TikTok publishing
                                      Cloudflare R2 media upload
                 Shared App Layer
────────────────────────────────────────────────────────────────
Models / Core Data entities
Repositories
Platform adapters
Scheduler models
Creative pipeline models
Analytics models
Trend library
Sync diagnostics

5.1 macOS as the Primary Worker

The Mac should be the reliable automation device.

Responsibilities:

* scheduled generation
* batch rendering
* background queue processing
* Cloudflare R2 uploads
* TikTok publishing
* analytics polling
* retry processing
* local file cleanup

The iPhone should not be relied on for long-running autonomous scheduled publishing because iOS background execution is constrained. The iPhone can enqueue actions and approve jobs; the Mac executes them when online.

5.2 iPhone as Monitor and Controller

The iPhone app should support:

* approve/reject posts
* pause automation
* review previews
* edit captions/hooks
* assign trend tags
* inspect analytics
* trigger generation request
* retry failed job
* change schedule
* receive notifications

⸻

6. Code Architecture

6.1 Pattern

Use MVVM with repository/service boundaries.

View
↓
ViewModel
↓
Repository / Use Case
↓
Service / Adapter
↓
Core Data, CloudKit, Cloudflare R2, TikTok, AVFoundation

6.2 Suggested Xcode Project Layout

Flick.xcodeproj
│
├── FlickShared/
│   ├── App/
│   ├── DesignSystem/
│   ├── Models/
│   ├── Persistence/
│   ├── Repositories/
│   ├── Services/
│   ├── PlatformAdapters/
│   ├── CreativePipeline/
│   ├── Rendering/
│   ├── Scheduling/
│   ├── Analytics/
│   ├── Trends/
│   └── Utilities/
│
├── FlickiOS/
│   ├── iOSApp.swift
│   ├── iOSNavigation/
│   ├── iOSViews/
│   └── iOSCapabilities/
│
├── FlickMac/
│   ├── MacApp.swift
│   ├── MacNavigation/
│   ├── MacViews/
│   ├── MenuBarWorker/
│   └── MacCapabilities/
│
└── FlickTests/
    ├── PersistenceTests/
    ├── SchedulerTests/
    ├── RendererTests/
    ├── PlatformAdapterTests/
    └── AnalyticsTests/

6.3 Dependency Direction

The shared layer should not depend on the iOS or macOS app targets.

Use protocols for platform-specific dependencies:

protocol SocialPlatformPublishing {
    var platform: SocialPlatform { get }
    func validateAccount(_ account: ConnectedAccount) async throws -> PlatformAccountStatus
    func publish(_ job: PublishingJob) async throws -> PublishResult
    func fetchAnalytics(for post: PublishedPost) async throws -> PlatformAnalyticsSnapshot
}
protocol MediaStorageProviding {
    func uploadAsset(_ asset: LocalMediaAsset, path: String) async throws -> RemoteMediaAsset
    func publicURL(for path: String) async throws -> URL
    func signedURL(for path: String, expiresIn: TimeInterval) async throws -> URL
}
protocol SlideshowRendering {
    func renderVideo(from slideshow: SlideshowDraft, options: RenderOptions) async throws -> RenderedVideo
    func renderImages(from slideshow: SlideshowDraft, options: ImageRenderOptions) async throws -> [RenderedImage]
}

6.4 Native-First Frameworks

Use native Apple frameworks by default:

* SwiftUI
* Core Data
* CloudKit
* AVFoundation
* Core Image
* Core Graphics
* PhotosUI
* AuthenticationServices
* CryptoKit
* Swift Charts
* UserNotifications
* BackgroundTasks where useful
* OSLog

Third-party packages should be minimal and justified.

Likely acceptable third-party dependencies:

1. Optional: OpenAI/AI provider SDK
    * Only if direct URLSession calls become repetitive or hard to maintain.
2. Optional: ZIP/export helper
    * Only if native compression is insufficient.

Avoid adding third-party packages for UI, charts, networking, scheduling, or persistence unless there is a strong reason.

⸻

7. Data Model

7.1 Core Entities

Workspace

Represents the local user’s Flick workspace.

Fields:

* id
* name
* createdAt
* updatedAt
* defaultCadence
* automationPaused
* primaryWorkerDeviceID

Device

Tracks each synced device.

Fields:

* id
* name
* platform
* isPrimaryWorker
* lastSeenAt
* capabilities
* appVersion

ConnectedAccount

Represents a connected social account.

Fields:

* id
* platform
* displayName
* platformUserID
* avatarURL
* scopes
* status
* isPublishingEnabled
* defaultPrivacyLevel
* lastValidatedAt
* createdAt
* updatedAt

Important: OAuth tokens should live in Keychain on the device that needs them. CloudKit should sync only metadata and capability state.

Campaign

Represents a marketing campaign or app feature push.

Fields:

* id
* name
* goal
* appFeature
* audience
* status
* createdAt
* updatedAt

Trend

Represents a trend or style pattern.

Fields:

* id
* name
* source
* sourceURL
* notes
* status
* tags
* createdAt
* updatedAt

TrendTag

Fields:

* id
* name
* category
* color
* createdAt

Suggested categories:

* hook
* template
* visual style
* niche
* app feature
* emotion
* CTA
* pacing
* text density
* platform

Asset

Represents generated, uploaded, or reference media.

Fields:

* id
* mediaType
* source
* localFilePath
* storageBucket
* storagePath
* publicURL
* signedURLExpiration
* width
* height
* duration
* fileSize
* checksum
* trendTags
* createdAt
* updatedAt

SlideshowDraft

Fields:

* id
* title
* campaign
* template
* slides
* caption
* hashtags
* targetPlatforms
* status
* createdAt
* updatedAt

Slide

Fields:

* id
* index
* imageAsset
* overlayText
* textPosition
* textStyle
* duration
* transition
* createdAt
* updatedAt

CreativeTemplate

Fields:

* id
* name
* description
* platform
* slideCount
* styleJSON
* defaultTextRules
* tags
* createdAt
* updatedAt

PublishingJob

Fields:

* id
* platform
* account
* draft
* scheduledAt
* status
* requiresApproval
* approvedAt
* approvedByDeviceID
* attemptCount
* lastAttemptAt
* lastError
* platformPublishID
* createdAt
* updatedAt

Statuses:

* draft
* queued
* awaitingApproval
* approved
* rendering
* uploadingMedia
* publishing
* published
* failed
* canceled
* paused

PublishedPost

Fields:

* id
* platform
* account
* platformPostID
* platformURL
* publishedAt
* draft
* campaign
* template
* trendTags
* caption
* createdAt
* updatedAt

AnalyticsSnapshot

Fields:

* id
* publishedPost
* capturedAt
* views
* likes
* comments
* shares
* saves
* engagementRate
* watchTime
* completionRate
* profileVisits
* follows
* rawJSON

Not every platform will expose every metric. Store platform-specific raw payloads for future backfill.

⸻

8. Sync Strategy

8.1 Core Data + CloudKit

Use a shared Core Data model for iOS and macOS.

Recommended setup:

* NSPersistentCloudKitContainer
* persistent history tracking enabled
* remote change notifications enabled
* automatic lightweight migration
* clear merge policies
* CloudKit private database for single-user sync

8.2 Conflict Strategy

Use “last writer wins” only for simple fields.

For critical workflow state, use explicit status transitions:

awaitingApproval → approved → rendering → uploadingMedia → publishing → published

Do not allow the iPhone and Mac to both process the same publishing job. Use a lightweight claim/lease model:

PublishingJob {
    workerDeviceID: UUID?
    workerLeaseExpiresAt: Date?
}

Before the Mac processes a job:

1. Check that status is eligible.
2. Claim the job with workerDeviceID.
3. Set workerLeaseExpiresAt.
4. Save and sync.
5. Process only if the claim remains valid.

8.3 Sync Health UI

Add a sync status component:

* last CloudKit import
* last CloudKit export
* pending changes
* account iCloud availability
* primary worker device online/offline
* sync errors

⸻

9. Cloudflare R2 Storage Architecture

9.1 Bucket

Use a single R2 bucket for all app media. Separate media classes with object-key prefixes rather than separate buckets.

Recommended prefixes:

generated-slides/
rendered-image-sequences/
reference-images/
thumbnails/

9.2 Path Structure

/workspaces/{workspaceID}/campaigns/{campaignID}/drafts/{draftID}/slides/{slideID}.png
/workspaces/{workspaceID}/campaigns/{campaignID}/drafts/{draftID}/rendered/{renderID}.mp4
/workspaces/{workspaceID}/trends/{trendID}/references/{assetID}.png

9.3 URL Strategy

Support both:

* public URLs
* signed URLs

For TikTok photo publishing, public or otherwise TikTok-accessible URLs are required. Signed URLs may work only if TikTok can fetch them before expiration and if the URL/prefix verification requirements are satisfied.

Preferred production setup:

Cloudflare R2 bucket
→ custom domain
→ stable public URL for publish-time media

9.4 Credentials

The app stores Cloudflare R2 credentials in Keychain for local upload workflows.

Never ship:

* unrestricted Cloudflare account tokens
* long-lived R2 write credentials outside Keychain
* unrestricted admin credentials
* TikTok client secret in an insecure client context

For anything requiring privileged credentials, prefer a tiny serverless function later. V1 should avoid privileged backend flows unless absolutely necessary.

⸻

10. TikTok Integration

10.1 TikTok Account Flow

Flick should support:

* OAuth connect
* token storage in Keychain
* scope validation
* account metadata sync
* publishing capability checks
* privacy/interaction settings refresh

10.2 TikTok Publishing Modes

Support:

1. Photo direct post
2. Photo upload for user completion
3. Video direct post
4. Video upload for user completion

Initial implementation should prioritize the approved flow available to the current TikTok developer app.

10.3 Creator Info Requirement

Before direct publishing, Flick should query creator/account publishing info and use the returned options to populate the final publish settings screen.

10.4 TikTok Post Settings

Per job:

* account
* privacy level
* disable comments
* disable duet
* disable stitch
* commercial content / brand organic flags
* caption
* hashtags
* scheduled time
* publish mode
* approval state

10.5 TikTok Error Handling

Persist structured failures:

* auth expired
* missing scope
* rate limit
* media URL inaccessible
* URL ownership unverified
* invalid privacy setting
* unaudited client/private-only limitation
* platform processing failed
* unknown server error

Each failed job should show:

* what happened
* whether it is retryable
* suggested fix
* raw platform error in advanced details

⸻

11. Platform Adapter Design

Do not hard-code TikTok into the scheduler or creative pipeline.

Use this model:

enum SocialPlatform: String, Codable {
    case tiktok
    case instagram
    case threads
    case x
}
protocol SocialPlatformAdapter {
    var platform: SocialPlatform { get }
    func connectAccount() async throws -> ConnectedAccount
    func validateAccount(_ account: ConnectedAccount) async throws -> PlatformAccountStatus
    func prepareMedia(_ draft: SlideshowDraft, mode: PublishMode) async throws -> PreparedPlatformMedia
    func publish(_ job: PublishingJob) async throws -> PublishResult
    func fetchAnalytics(_ post: PublishedPost) async throws -> AnalyticsSnapshot
}

11.1 TikTokAdapter

V1.

Responsibilities:

* TikTok OAuth
* creator info query
* photo slideshow publish/upload
* video upload/direct post
* status polling
* analytics fetch where API access permits

11.2 InstagramAdapter

Future.

Design expectations:

* likely Graph API based
* support image, video, carousel, Reels where approved
* metrics integration
* may require professional/creator/business account constraints

11.3 ThreadsAdapter

Future.

Design expectations:

* text-first and media support
* useful for adapting TikTok hooks into short text posts
* may share some Meta auth infrastructure with Instagram

11.4 XAdapter

Future.

Design expectations:

* text/image/video post creation
* media upload before post creation
* pricing-aware behavior because X API usage is pay-per-use
* no assumptions that X will be free or cheap for automation

⸻

12. Creative Generation Pipeline

12.1 Pipeline

Input
→ Strategy Brief
→ Hook Ideas
→ Slide Outline
→ Image Prompts
→ Image Generation
→ Text Overlay
→ Quality Checks
→ Asset Upload
→ Draft Preview
→ Approval
→ Queue
→ Publish
→ Analytics
→ Iteration

12.2 Strategy Brief

Each generation should know:

* app being promoted
* feature being promoted
* audience
* pain point
* tone
* trend/template
* CTA
* target account
* platform
* desired slide count

12.3 Slide Model

Each slide should store both visual and semantic intent:

Slide {
    index
    role: hook | problem | proof | demo | benefit | cta
    imageAsset
    prompt
    overlayText
    textStyle
    transition
    duration
}

12.4 Quality Checks

Before queueing:

* correct aspect ratio
* no missing image URL
* no empty overlay text
* readable text contrast
* caption length within platform limits
* no prohibited or risky terms
* CTA present when required
* storage URLs available
* publish settings valid

⸻

13. Trends System

13.1 Sources

V1 trend sources:

* TikTok Creative Center
* manual trend entries
* uploaded screenshots/images
* manually pasted TikTok links
* high-performing Flick posts

Do not scrape TikTok directly.

13.2 Trend Object

Trend {
    name
    source
    sourceURL
    referenceAssets
    tags
    notes
    examples
    status
    performanceSummary
}

13.3 Trend Statuses

* new
* active
* testing
* winning
* declining
* archived

13.4 Trend Tagging

Allow flexible tagging:

“bold hook”
“messy notes”
“before/after”
“fake text message”
“app screenshot”
“listicle”
“rage-bait”
“cozy productivity”
“5-slide”
“high text density”
“founder POV”

13.5 Trend-to-Creative Link

Every generated draft should optionally link to:

* source trend
* trend tags
* template
* campaign
* app feature

This enables analytics like:

“Slideshows tagged before/after and app screenshot outperform founder POV by 42% on saves.”

⸻

14. Analytics and Learning Loop

14.1 Analytics Goals

Flick should answer:

* Which posts are winning?
* Which templates are winning?
* Which hooks are winning?
* Which trend tags are winning?
* Which accounts are growing fastest?
* Which posting times work best?
* Which app features generate the most engagement?
* Which creative variants should we remix?

14.2 Ranking Metrics

Use multiple ranking views:

* views
* likes
* comments
* shares
* saves
* engagement rate
* views per hour
* saves per view
* follows per post
* app-store CTA proxy metrics if available later

14.3 Analytics Refresh

The Mac worker should poll analytics on a cadence:

1 hour after publish
6 hours after publish
24 hours after publish
3 days after publish
7 days after publish

Store each refresh as an AnalyticsSnapshot, not just the latest values. This allows growth curves over time.

14.4 Iteration Features

From any post, support:

* remix
* duplicate template
* generate 5 variants
* reuse hook
* reuse visual style
* reuse trend tags
* compare against campaign average
* archive losing pattern

⸻

15. Scheduling and Automation

15.1 Cadence Rules

Support per-account rules:

CadenceRule {
    account
    postsPerDay
    allowedTimeWindows
    minimumGap
    requireApproval
    maxRetries
    pauseOnErrorCount
}

15.2 Approval Modes

Support:

1. Manual only
    * nothing posts without approval
2. Approve generated batch
    * user approves posts, scheduler handles timing
3. Trusted templates
    * certain templates can auto-post
4. Fully autonomous
    * only after enough safeguards exist

V1 should default to manual approval.

15.3 Worker Loop

The Mac worker periodically:

1. Syncs Core Data changes.
2. Finds due jobs.
3. Claims one job.
4. Validates account and media.
5. Renders if needed.
6. Uploads assets if needed.
7. Publishes.
8. Stores result.
9. Schedules analytics refresh.
10. Releases job claim.

⸻

16. Notifications

16.1 iPhone Notifications

Notify for:

* approval needed
* post published
* post failed
* account token expired
* analytics milestone reached
* primary worker offline too long
* generation batch complete

16.2 macOS Notifications

Notify for:

* worker paused
* failed queue
* TikTok auth required
* Cloudflare R2 upload errors
* CloudKit sync errors

⸻

17. Security and Privacy

17.1 Secret Storage

Use Keychain for:

* TikTok access/refresh tokens
* platform tokens
* Cloudflare R2 write credentials
* AI provider API keys if user-supplied

CloudKit stores only metadata.

17.2 Cloudflare R2 Security

Use bucket-scoped write credentials and a custom domain carefully.

Recommended rule:

* app can upload only to workspace-scoped paths
* app can read only workspace-scoped paths
* public access limited to publishable media buckets if needed
* private/reference buckets use signed URLs

17.3 Audit Trail

Store events:

* account connected
* token refresh failed
* job approved
* job published
* job failed
* automation paused/resumed
* media uploaded
* settings changed

⸻

18. Native Rendering

18.1 Image Rendering

Use:

* Core Graphics
* Core Image
* SwiftUI snapshotting where appropriate

Generate 1024×1536 image assets by default.

18.2 Video Rendering

Use AVFoundation to compose:

* slide images
* durations
* transitions
* text overlays
* optional audio
* export MP4/H.264

18.3 Template Rendering

A template should define:

* canvas size
* safe areas
* background behavior
* text layout
* font style
* slide roles
* transition style
* CTA placement

Store template rendering instructions as versioned JSON so templates can evolve without breaking old drafts.

⸻

19. Reliability Requirements

19.1 Offline-First

The app should work offline for:

* browsing drafts
* editing drafts
* reviewing analytics already synced
* creating local drafts
* organizing trends

Online required for:

* CloudKit sync
* Cloudflare R2 upload
* TikTok publishing
* analytics polling
* external trend research

19.2 Idempotency

Publishing must be carefully guarded against duplicate posts.

Use:

* platform publish ID
* job status transitions
* worker lease
* attempt count
* result persistence before retry
* platform status polling where available

19.3 Diagnostics

Build diagnostics from the start:

* CloudKit sync log
* worker log
* publishing log
* Cloudflare R2 upload log
* platform API response log
* local file cleanup log

⸻

20. Suggested Milestones

Milestone 1 — Foundation

* Shared SwiftUI app shell
* iOS + macOS targets
* Core Data model
* CloudKit sync
* Dashboard, Queue, Trends, Analytics placeholders
* device registration
* sync diagnostics

Milestone 2 — Asset Library

* Cloudflare R2 S3-compatible upload integration
* image upload
* reference image import
* asset metadata sync
* trend tags
* image preview grid

Milestone 3 — Slideshow Builder

* create slideshow draft
* add/reorder slides
* overlay text
* save templates
* preview on iPhone and Mac
* export rendered images

Milestone 4 — TikTok Account Integration

* OAuth connect
* account metadata
* token storage
* scope validation
* creator info query
* account status UI

Milestone 5 — TikTok Publishing

* photo slideshow publishing path
* video fallback path
* job queue
* approval flow
* error handling
* publish result persistence

Milestone 6 — Scheduler

* cadence rules
* Mac worker
* job claiming
* retries
* pause/resume automation
* notifications

Milestone 7 — Analytics

* analytics polling
* snapshots
* Analytics tab
* best-performing posts
* template/tag performance
* remix from winner

Milestone 8 — Creative Intelligence

* template-based generation
* trend-to-draft generation
* winning pattern detection
* recommended experiments

Milestone 9 — Future Platform Prep

* Instagram adapter stub
* Threads adapter stub
* X adapter stub
* shared publishing capability model
* platform-specific validation UI

⸻

21. Open Questions

1. Will TikTok accept the Cloudflare R2 custom-domain image URLs directly, or do we need a narrower verified URL prefix?
2. Which TikTok scopes are approved on the existing developer app?
user.info.basic
user.info.basic
Read a user's profile info (open id, avatar, display name ...)
Included in Login Kit
video.publish
video.publish
Directly post content to a user's TikTok profile.
Included in Content Posting API
video.upload
video.upload
Share content to creator's account as a draft to further edit and post in TikTok.
Included in Content Posting API
user.info.profile
user.info.profile
Read access to profile_web_link, profile_deep_link, bio_description, is_verified.
4. Should generation be local, API-based, or configurable?
- For generation we can use OpenAI since we have the API key
5. Will Flick use direct R2 credentials only, or move uploads behind a serverless broker later?
- V1 uses direct bucket-scoped R2 credentials stored in Keychain.
6. Should iPhone be allowed to publish directly, or should all publishing route through the Mac worker?
- It can publish directly, but can not have background processes like we can on mac

⸻

22. Implementation Notes

Recommended Defaults

* Mac is primary worker.
* iPhone is monitor/controller.
* Manual approval required for V1 posts.
* Store media in Cloudflare R2.
* Store metadata in Core Data + CloudKit.
* Store secrets in Keychain.
* Use TikTok first.
* Do not scrape TikTok.
* Keep platform adapters isolated.
* Build with future Instagram, Threads, and X integrations in mind.

Architectural Principle

Flick should not be “a TikTok automation app.”

It should be:

A native Apple-platform creative operations system for generating, publishing, measuring, and iterating on short-form marketing content.

TikTok is simply the first platform adapter.

Do not have needless fallbacks.

⸻

23. Reference Links

These should be checked again during implementation because platform APIs and Apple platform guidance can change.

Apple

* Liquid Glass overview: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
* Applying Liquid Glass to custom views: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
* Core Data + CloudKit container: https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer
* Setting up Core Data with CloudKit: https://developer.apple.com/documentation/CoreData/setting-up-core-data-with-cloudkit
* Understanding NSPersistentCloudKitContainer sync: https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer
* Debugging NSPersistentCloudKitContainer sync: https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer

TikTok

* Content Posting API get started: https://developers.tiktok.com/doc/content-posting-api-get-started-upload-content
* Photo post API reference: https://developers.tiktok.com/doc/content-posting-api-reference-photo-post
* TikTok Creative Center: https://ads.tiktok.com/business/creativecenter

Cloudflare R2

* R2 S3-compatible API: https://developers.cloudflare.com/r2/get-started/s3/
* R2 public buckets and custom domains: https://developers.cloudflare.com/r2/buckets/public-buckets/

Future Platforms

* Instagram content publishing: https://developers.facebook.com/docs/instagram-platform/content-publishing/
* Threads API: https://developers.facebook.com/docs/threads/
* Threads publishing: https://developers.facebook.com/docs/threads/reference/publishing/
* X create post API: https://docs.x.com/x-api/posts/create-post
* X media API: https://docs.x.com/x-api/media/introduction
* X pricing: https://docs.x.com/x-api/getting-started/pricing
