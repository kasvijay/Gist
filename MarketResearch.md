# Gist — Market Research & Commercialization Analysis

*Research date: 2026-04-15*

---

## Market Overview

| Segment | 2025 Value | Projected | CAGR |
|---------|-----------|-----------|------|
| AI Meeting Assistants | $1.20B | $6.28B by 2035 | 18.0% |
| AI Meeting Transcription | $3.86B | $29.45B by 2034 | 25.6% |

Key signal: Granola (local-capture, no bot) went from $250M to **$1.5B valuation** in 10 months (March 2026). Active class-action lawsuits against Otter.ai and Fireflies.ai for biometric data collection are driving enterprise buyers toward local-first tools.

---

## Competitor Comparison

| Feature | Gist | MacWhisper ($80) | Aiko ($24) | Granola ($14/mo) | Otter ($17/mo) | Krisp ($16/mo) |
|---|---|---|---|---|---|---|
| Live meeting recording | Yes | No | No | Yes | Yes (bot) | Yes |
| System audio capture | Yes | No | No | Yes | Via bot | Yes |
| Speaker diarization | Yes | Beta | No | Yes | Yes | Yes |
| On-device summarization | Yes | No | No | No (cloud) | No (cloud) | No (cloud) |
| 100% local/private | **Yes** | Yes | Yes | No | No | Partial |
| No account required | **Yes** | Yes | Yes | No | No | No |
| Mac App Store | No | Yes | Yes | No | No | No |

### Cloud Competitors Pricing

| Tool | Free Tier | Paid | Model |
|------|-----------|------|-------|
| Otter.ai | 300 min/mo | $8-30/user/mo | Subscription |
| Fireflies.ai | 800 min storage | $10-39/user/mo | Subscription |
| Granola.ai | 30 days of notes | $14-35/user/mo | Subscription |
| tl;dv | 10 lifetime AI summaries | $18-59/mo | Subscription |
| Krisp | 60 min/day | $8-15/mo | Subscription |
| Fathom | Unlimited recordings, 5 AI summaries/mo | $15-29/mo | Subscription |
| Read.ai | 5 meetings/mo | $15-40/mo | Subscription |

### On-Device Competitors

| Tool | Price | Live Recording | Diarization | Summarization |
|------|-------|---------------|-------------|---------------|
| MacWhisper | $29.99/yr or $79.99 lifetime | No | Beta | No |
| Aiko | $24 one-time | No | No | No |
| Whisper Notes | $6.99 one-time | No | No | No |
| Meetily | Free (open-source) | Yes | Yes | Yes (Ollama) |

---

## Gist's USP

**The only tool that does live meeting transcription + speaker diarization + AI summarization entirely on-device with zero cloud dependency.**

- No meeting bot joins calls
- No account, no sign-up, no cloud
- No biometric data collection risk (immune to BIPA lawsuits)
- GDPR/HIPAA compliant by design (no data transfers)
- Plain file storage (JSON + m4a) — user owns their data
- Works offline after initial model download

---

## Mac App Store Viability

**Not viable** in current form. Core Audio Taps (system audio capture) requires entitlements incompatible with App Store sandboxing. Neither Krisp nor Granola are on the App Store for this reason.

**Recommended distribution:** Direct download + Homebrew Cask (already in place).

Model downloads from HuggingFace are allowed (Apple's own "Diffusers" app does this on the App Store), but system audio capture is the blocker.

---

## Recommended Pricing Strategy

| Tier | Price | Features |
|------|-------|----------|
| **Free** | $0 | Unlimited recording + transcription + diarization (all local, no cost to serve) |
| **Pro** (one-time) | **$24.99** | Summarization, cross-session search, export formats (Markdown/SRT/DOCX), unlimited history |
| **Subscription** (future, optional) | $4.99/mo | Calendar integration, Slack/Notion push, multi-device sync |

**Why one-time, not subscription:** No server costs. Privacy-conscious users distrust subscriptions. MacWhisper ($80 lifetime) and Aiko ($24) prove one-time works.

---

## Feature Gap — What to Add

### High Impact (should build)

1. **Cross-session search** — full-text search across all transcripts, on-device
2. **Export formats** — Markdown, SRT subtitles, plain text, DOCX (currently JSON only)
3. **Editable transcripts** — let users correct errors
4. **Calendar-aware auto-recording** — detect when Zoom/Teams/Meet starts

### Differentiating (leverages privacy positioning)

5. **Encrypted vault** — encrypt sessions at rest with user passphrase
6. **Speaker enrollment** — record voice samples to pre-identify speakers
7. **Spotlight integration** — index transcripts for native macOS search
8. **Shortcuts/AppleScript support** — automation workflows

### Enterprise/Premium (future)

9. **Compliance mode** — for legal, healthcare, finance
10. **Custom vocabulary** — company-specific terms and names
11. **iOS companion app** — review transcripts on phone
12. **CRM integration** — push notes to Salesforce/HubSpot

---

## Privacy Lawsuits Creating Opportunity

- **Cruz v. Fireflies.AI Corp. (Dec 2025)** — biometric voiceprint collection under Illinois BIPA
- **Otter.ai class action (Aug 2025)** — using transcripts to train AI without consent
- **67% of healthcare compliance officers** concerned about cloud AI tools creating HIPAA violations
- **73% of EU enterprises** prioritize data sovereignty over convenience
- Local-first tools are immune to these legal risks

---

---

## Distribution & Monetization — How to Charge

### Payment Platform Comparison

| Platform | Fees | Merchant of Record | License Keys | Swift SDK | India Payouts |
|----------|------|-------------------|-------------|-----------|---------------|
| **LemonSqueezy** | 5% + $0.50 | Yes (full) | Built-in with activation limits | [swift-lemon-squeezy-license](https://github.com/kevinhermawan/swift-lemon-squeezy-license) | Conditional (needs pre-May 2024 Stripe or PayPal) |
| **Paddle** | 5% + $0.50 | Yes (strongest tax coverage) | Built-in via Mac SDK | [Paddle Mac Framework V4](https://github.com/PaddleHQ/Mac-Framework-V4) | Yes (explicitly supported) |
| **Gumroad** | 10% flat | Yes (since 2024) | Built-in, API verification | [GumroadLicenseValidator](https://github.com/dkasaj/GumroadLicenseValidator) | Yes (direct bank, Wise, Payoneer) |
| **Stripe** (direct) | 2.9% + $0.30 | **No** (you handle tax) | Must build your own | None | Yes, but massive extra work |

**Recommendation:** Start with **LemonSqueezy** (lowest fees, full MoR, Swift SDK exists). If India bank payouts are blocked, use **Paddle** (confirmed India support, native Mac SDK with built-in license UI).

**Why MoR matters:** The platform is legally the seller. They collect VAT/sales tax/GST from customers worldwide and remit it. You just receive payouts. Without MoR (Stripe), you must handle global tax compliance yourself.

### How It Works: Homebrew + License Key

1. User installs via `brew install --cask gist` (free version)
2. App works fully for transcription + diarization (free tier)
3. User clicks "Upgrade to Pro" in Settings → opens your LemonSqueezy/Paddle checkout page
4. After purchase, they receive a license key via email
5. User enters license key in app → validated via API → stored in Keychain
6. Pro features (summarization, search, exports) are unlocked

This is exactly how **MacWhisper** monetizes — Homebrew distributes, Gumroad sells licenses.

### License Key Validation — Recommended Hybrid Approach

**First activation:** Validate online against LemonSqueezy/Paddle API.

**Subsequent launches:** Check cached result in Keychain. If last validation was within 30 days, allow use without network.

**Periodic re-validation:** Every 30 days, silently re-validate in background. If network fails, allow 7-14 day grace period.

**Refund detection:** On re-validation, check if purchase was refunded → deactivate.

### Implementation in Swift

**Using LemonSqueezy Swift SDK:**
```swift
import LemonSqueezyLicense

let client = LemonSqueezyLicense(apiKey: "your-api-key")

// Activate
let result = try await client.activate(key: licenseKey, instanceName: "User's Mac")

// Validate (periodic)
let status = try await client.validate(key: licenseKey, instanceId: instanceId)
```

**Secure storage in Keychain** (not UserDefaults — UserDefaults is plaintext):
```swift
// Store license activation in Keychain
KeychainHelper.save(key: "license_key", data: keyData)
KeychainHelper.save(key: "last_validated", data: dateData)
```

**Feature gating pattern:**
```swift
class LicenseManager: ObservableObject {
    @Published var tier: AppTier = .free  // .free or .pro
    var isPro: Bool { tier == .pro }
}

// In SwiftUI views:
if licenseManager.isPro {
    SummarizationView()  // Pro feature
} else {
    UpgradePromptView()
}
```

**Using Paddle Mac SDK (alternative):**
```swift
// Paddle SDK handles the entire flow — UI, activation, validation, trials
let paddle = Paddle.sharedInstance(with: paddleConfig)
let product = PADProduct(productId: "your-product-id")
paddle.showProductAccessDialog(with: product)
// SDK handles license entry, activation, and caching internally
```

### Offline-Only Validation (No Server, Alternative)

If you want zero network dependency even for licensing, use **Ed25519 cryptographic signing** with Apple CryptoKit:

```swift
import CryptoKit

// Generate license offline: sign "email|product|expiry" with private key
// App embeds public key, verifies signature locally
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
let isValid = publicKey.isValidSignature(signature, for: licenseData)
```

**Pros:** Zero network needed. No server costs. Fits the "fully local" brand.
**Cons:** Cannot revoke licenses or enforce device limits. Shared keys can't be stopped.

### Anti-Piracy — Keep It Simple

Community consensus from indie Mac devs: **"Make it easy to buy, don't over-invest in DRM."**

- A determined hacker can always bypass client-side checks
- Most pirates would never have paid anyway
- Over-aggressive DRM harms legitimate users

**Recommended (Level 1):**
- Online license activation via LemonSqueezy/Paddle API
- Store result in Keychain
- Code-sign your app (already doing this)
- 3 device activations per key (managed by platform)

**Don't bother with:** Binary obfuscation, hardware binding, anti-tampering checks. Not worth the effort for an indie app.

---

## Tax & Legal (India-Specific)

### What the Payment Platform Handles (as MoR)

- Collects VAT/sales tax/GST from international customers
- Remits those taxes to correct authorities worldwide
- Handles refunds and chargebacks
- Issues invoices to customers

### What You Handle

1. **Income tax:** Declare all payouts as income. Pay per your slab.
2. **GST registration:** Required if turnover exceeds Rs. 20 lakhs. Voluntary registration below threshold lets you claim Input Tax Credit.
3. **GST on exports:** Software exports are **zero-rated**. File Letter of Undertaking (LUT) annually for zero-rated exports — no IGST charged.
4. **FEMA compliance:** Receiving foreign exchange for software services is permitted through proper banking channels.
5. **Professional tax:** Applicable in Karnataka.

**Key point:** Using LemonSqueezy/Paddle as MoR means they handle all customer-facing tax. You only handle Indian income tax and GST compliance on your end. Consult a CA familiar with software exports — this is routine in Bengaluru.

### Receiving Payouts

| Platform | India Bank Transfer | Alternative |
|----------|-------------------|-------------|
| Gumroad | Yes (direct) | Wise, Payoneer |
| LemonSqueezy | Conditional (pre-May 2024 Stripe) | PayPal |
| Paddle | Yes (explicitly supported) | Multi-currency |

---

## Key Takeaway

Gist is well-positioned in a market where privacy concerns are becoming a primary buying criterion. The combination of live recording + diarization + summarization, all on-device, is unique. Distribute via Homebrew/DMG, charge ~$25 one-time for Pro via LemonSqueezy or Paddle, and prioritize cross-session search + exports as next features.
