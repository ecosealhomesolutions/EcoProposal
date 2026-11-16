# EcoProposal — App Store Submission Guide

## Overview

EcoProposal is an internal iPad/iPhone app for Eco Seal Home Solutions field sales representatives. It creates, edits, and delivers professional proposals with job photos, hand-drawn sketches, takeoff measurements, and PDF export. Proposals can be saved to OneDrive via Microsoft 365 sign-in.

---

## Pre-Submission Checklist

### 1. Apple Developer Account
- [ ] Active Apple Developer Program membership ($99/yr) at [developer.apple.com](https://developer.apple.com)
- [ ] Team member with **Account Holder** or **Admin** role to sign the app

### 2. Bundle Identifier & App ID
- Current bundle ID: `ESHS.EcoProposal`
- [ ] App ID registered at **Certificates, Identifiers & Profiles → Identifiers**
- [ ] Custom URL scheme `msauth.ESHS.EcoProposal` is listed (already in Info.plist)

### 3. Signing & Capabilities
- [ ] Distribution certificate created (iOS Distribution)
- [ ] App Store provisioning profile created for `ESHS.EcoProposal`
- [ ] In Xcode: **Signing & Capabilities → Team** set to your Apple Developer team
- [ ] Automatically manage signing: **enabled** (recommended) or manually with the above profile

### 4. Version & Build Numbers
In Xcode → Project → EcoProposal target → General:
- **Version** (Marketing Version): e.g. `1.0.0`
- **Build** (Current Project Version): e.g. `1` (increment for every upload to App Store Connect)

### 5. App Icons
- [ ] All required icon sizes present in `Assets.xcassets/AppIcon.appiconset/`
  - 1024×1024 px PNG required for App Store (no alpha channel, no rounded corners)
  - Verify with Xcode's asset catalog editor — any missing size shows a warning

### 6. Required Usage Description Strings (already in Info.plist)
| Key | Purpose shown to user |
|---|---|
| `NSCameraUsageDescription` | Job-site photo capture |
| `NSPhotoLibraryUsageDescription` | Attaching existing photos |

No other entitlements or privacy keys should be needed unless new features are added.

### 7. Encryption Export Compliance
`ITSAppUsesNonExemptEncryption` is set to `false` in Info.plist. This means the app uses only standard OS encryption (HTTPS/TLS) and **no export compliance documentation is required**.

---

## Microsoft Entra ID (Azure AD) Setup

The app signs users into their Eco Seal Microsoft 365 account via MSAL. The Entra ID app registration must remain configured before submission:

| Setting | Value |
|---|---|
| Client ID | `d55834c2-ac29-41a5-8f3f-d790d093dc6c` |
| Tenant ID | `62613112-06d4-43c2-8be9-5eefa4b63e77` (single-tenant) |
| Redirect URI | `msauth.ESHS.EcoProposal://auth` |
| Scopes | `Files.ReadWrite`, `User.Read` |

- [ ] Confirm the redirect URI above is listed under **Authentication → Mobile and desktop applications** in the Entra ID app registration
- [ ] The app is **single-tenant** (only Eco Seal employees can sign in) — no additional Azure approval needed

---

## Build & Archive

1. In Xcode, select the **EcoProposal** scheme and target **Any iOS Device (arm64)**
2. **Product → Archive**
3. Once complete, the Organizer window opens automatically
4. Select the archive → **Distribute App → App Store Connect → Upload**
5. Follow the prompts (distribution certificate + provisioning profile will be applied)

---

## App Store Connect Setup

Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) and create a new app.

### App Information
| Field | Suggested value |
|---|---|
| Name | EcoProposal |
| Subtitle | Proposals for Eco Seal Reps |
| Bundle ID | ESHS.EcoProposal |
| Primary Language | English (U.S.) |
| Category | Business |

### Distribution Method
- **Internal testing only (TestFlight):** fastest path; up to 100 internal testers; no App Review required; builds expire in 90 days
- **Private App (Custom Apps):** distribute only to Eco Seal employees via Apple Business Manager; requires Apple Business Manager enrollment; recommended for long-term internal deployment
- **Public App Store:** available to anyone; full App Review required; not recommended for an internal tool

**Recommendation:** Start with **Internal TestFlight** for rollout, then move to **Custom App** via Apple Business Manager for production distribution.

### Screenshots
App Review (and TestFlight internal review) require at least one screenshot per device class used:
- iPhone 6.9" (required) — 1320×2868 or 1290×2796 px
- iPad Pro 13" (recommended, since this is primarily a tablet app) — 2064×2752 or 2048×2732 px

Use the iOS Simulator or a physical device to capture screenshots showing:
1. Proposal list view
2. Proposal editor with line items
3. Photo / sketch / takeoff section
4. PDF preview

### Privacy Policy
App Store Connect requires a Privacy Policy URL even for internal apps.
- Host a simple page (or a PDF on your company website) describing what data the app collects (camera photos, OneDrive files, name/email from Microsoft 365 account)
- Enter the URL in **App Privacy → Privacy Policy URL**

### App Privacy Questionnaire (Data Types)
Based on the app's behavior, declare the following:

| Data type | Collected? | Linked to identity? | Used for tracking? |
|---|---|---|---|
| Photos / videos | Yes — job site photos | No | No |
| Name | Yes — from Microsoft account | Yes | No |
| Email address | Yes — from Microsoft account | Yes | No |
| User ID | Yes — MSAL account ID | Yes | No |
| Files / docs | Yes — OneDrive proposals | No | No |

All data is used solely for app functionality; select **"Data Used to Operate the App"** for each category.

---

## Before Submitting for Review

- [ ] Build runs cleanly on a physical iPhone and iPad (`Product → Run` on device)
- [ ] OneDrive sign-in works end-to-end (Settings → OneDrive → Sign in with Microsoft 365)
- [ ] Proposals generate and share a PDF without crashes
- [ ] Camera and photo library pickers show the correct permission prompts
- [ ] No hard-coded test credentials or debug-only logging that would expose internal data
- [ ] Review Notes for App Review: explain this is an internal B2B tool for Eco Seal Solutions employees and that the Microsoft 365 sign-in requires a company account — provide a demo account or note that reviewers should contact you for access

---

## Known Pre-Shipping Items to Resolve

The following are noted in the source code as deferred to a future phase:

1. **SwiftData schema migration** — the app currently wipes local data on schema mismatch instead of migrating. Add a `VersionedSchema` migration plan before shipping to reps with real proposal data.
2. **Quickbase sync** — the Quickbase integration is placeholder ("coming soon"). The settings screen is visible but non-functional; either hide it or complete the integration before submission.
3. **Quickbase token in Keychain** — `QuickbaseConfig.userToken` is stored in `UserDefaults` rather than the Keychain. Move it before enabling Quickbase sync.

---

## Useful Links

- App Store Connect: https://appstoreconnect.apple.com
- Certificates, Identifiers & Profiles: https://developer.apple.com/account/resources
- Apple Business Manager (Custom Apps): https://business.apple.com
- MSAL iOS redirect URI format: https://learn.microsoft.com/en-us/entra/identity-platform/redirect-uris-ios
