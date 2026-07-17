# NADA — App Schema Summary

Product planning schema for **NADA (Not a Dating App!)** — *Hinge, but for friends*: prompt-based profiles, intentional likes, and matches built for hanging out — not dating.

Sections 1–3 reflect your filled answers (translated / tightened into English).  
Sections 4–11 are **example fill** inspired by Hinge’s model, adapted for friendship and hangouts. Edit freely.

---

## 1. Identity

| Field | Answer |
|-------|--------|
| App name | Not a Dating App! |
| Short name / brand | NADA! |
| One-line promise | Make friends nearby to hang out with — not for dating, only for hanging out. |
| Target platform | iOS (iPhone / iPad) |
| Language(s) | Launch in Turkish first; then English, Spanish, French, Russian, and Chinese. |

**Positioning shorthand:** Hinge, but for friends.

---

## 2. Problem & user

**Who is the target user?**  
Anyone who wants to make friends — especially people traveling, changing cities on holiday, feeling lonely, having no one to hang out with locally, or simply wanting new friends.

**What problem are we solving?**  
People often end up far from their friends, or find socializing hard. Mainstream social apps mostly deepen existing connections rather than helping you meet new people. Dating apps (Tinder, Hinge, etc.) are built for romance, so they are a poor fit for platonic hangouts — especially for women who want to avoid romantic or sexual expectations. NADA moves the experience toward relaxed, shared time with people you’d actually hang out with, and reduces that pressure.

**How do people solve this today?**  
They post on Instagram, Twitter/X, etc. that they want to hang out — which is awkward, low-signal, and not designed for matching.

**Why now?**  
Personal need, plus seeing people around you who want the same thing: fun, low-pressure hangouts with new people. That’s why this concept exists.

---

## 3. Value proposition

**Core benefit (for the user):**  
Make friends without romantic expectations.

**Difference vs competitors / alternatives:**  
A single-purpose app shaped around one job: friendship and hangouts. Faster way to connect people with similar hobbies and hangout intent (vs broadcasting on social media or filtering dating apps). Extra layer for women: safety signals and account audits based on how men use the app (e.g. share of women in their connections).

**What makes someone say “I’ll use this”?**  
- I’m on holiday, newly moved, or visiting a city for the first time — I want friends to hang out with.  
- I want new friends and shared plans, not dates.  
- I want clear anti-flirting norms and tools to report romantic pressure.

---

## 4. Scope (MVP)

*Example fill — Hinge-style discovery, adapted for friends.*

### In the first version

- [x] Sign up / sign in (email or Apple / phone TBD)
- [x] Profile setup: photos, bio, city/area, hangout interests, and **prompt answers** (Hinge-style)
- [x] Discover feed: browse nearby profiles one at a time (or card stack)
- [x] Like a whole profile **or** like/comment on a specific prompt/photo (Hinge-style “like with comment”)
- [x] Mutual match when both sides like → unlock chat
- [x] In-app chat for matched friends (text + **voicemail** / async voice messages)
- [x] Clear “friends only / not dating” framing in onboarding and profile
- [x] Basic safety: report, block, unmatch — report reasons include **flirting**
- [x] Women-focused safety: track & audit men’s **% of women** among likes/matches/connections; surface or act on skewed patterns
- [x] Location radius preference (e.g. same city / within X km)

### Explicitly out of MVP

- [x] Dating / romance mode, “looking for a relationship,” or couple features
- [x] **Video calls** (never for friendship MVP; keep hangouts IRL / off-app by mutual choice)
- [x] In-app features that encourage flirting (no “compliment romance” flows, no dating prompts)
- [x] Group hangouts / event host tools / map of public events
- [x] Paid boosts, Super Likes economy, or full subscription paywall
- [x] Full multi-language UI (ship Turkish or EN first; others later)
- [x] Android

### Notes for later versions

Group hangout invites, “I’m free this weekend” status, interest-based filters, verification badge, richer safety (photo verify), public-facing women safety prefs, and localization for ES / FR / RU / ZH.

---

## 5. User flows

*Example fill — 5 core scenarios.*

### Flow 1: Onboarding & profile

1. User opens NADA → sees friends-only positioning (“Not a Dating App”).
2. Creates an account and confirms they’re here for friendship / hangouts.
3. Adds photos, city, interests, and answers 3+ prompts (e.g. “Ideal Saturday hangout…”, “I’m always down for…”).
4. Sets discovery radius / city → lands on Discover.

### Flow 2: Discover & like (Hinge-style)

1. User browses a profile: photos + prompt answers.
2. Likes a specific prompt/photo (optionally with a short comment) or skips.
3. Profile moves on; likes are not revealed until mutual (or shown as “they liked you” later — TBD).
4. Repeat until they want to check Matches / Likes.

### Flow 3: Match & first chat

1. Other person likes back → mutual match.
2. Both get a match notification; chat unlocks.
3. Opening message can reference the liked prompt (Hinge-style icebreaker).
4. They chat (text and/or voicemail) to plan a hangout — coffee, walk, museum, etc.
5. Moving to Instagram / WhatsApp / etc. is allowed only as a **mutual** choice; NADA does not push off-app contact. Flirting should not be viable as an in-app product path.

### Flow 4: Safety — report / block

1. From profile or chat, user opens safety menu.
2. Blocks and/or reports with a reason — including **“Flirting”** (romantic / dating pressure), harassment, fake profile, spam, other.
3. Chat ends; user no longer appears in Discover for them.
4. Flirting (and related) reports feed moderation; men’s women-connection ratio can trigger **account review**.

### Flow 5: Edit profile & preferences

1. User opens Profile / Settings.
2. Updates photos, prompts, interests, or location radius.
3. Changes apply to how they appear and who they see.

---

## 6. Screen inventory

| Screen | Purpose | Entry | Exit |
|--------|---------|-------|------|
| Welcome / splash | Brand + “friends only” promise | App launch | Sign up / Sign in |
| Sign up / Sign in | Create or access account | Welcome | Onboarding or Discover |
| Onboarding (intent) | Confirm hangout/friends intent | After auth | Profile setup |
| Profile setup (photos) | Add photos | Onboarding | Prompts setup |
| Profile setup (prompts) | Answer Hinge-style prompts | Photos step | Preferences |
| Preferences | City, radius, interests | Prompts step | Discover |
| Discover (feed) | Browse profiles / prompts | Tab bar / after setup | Profile detail, Likes, Matches |
| Profile detail | Full profile view | Discover / Likes | Like, Skip, Report, Chat (if matched) |
| Likes you / Sent likes | See incoming or outgoing likes | Tab bar | Profile detail / Match |
| Matches | List of mutual matches | Tab bar / notification | Chat |
| Chat thread | Text + voicemail with a match (no video call) | Matches / notification | Matches, Profile, Report |
| My profile | Edit own profile | Tab bar | Edit screens, Settings |
| Settings | Account, privacy, logout | My profile | Preference edits, delete account |
| Safety prefs (women) | Optional women-focused safety visibility / filters (e.g. prefer users with balanced connection patterns) | Settings / Preferences | Discover prefs applied |
| Report / Block sheet | Reasons include Flirting, harassment, fake, spam, other | Profile / Chat | Previous screen |
| Moderation queue (ops) | Review reports + men with skewed women-% among connections | Internal tools | Warn / limit / ban |

---

## 7. Data schema summary

### Entities

| Entity | Short description | Main fields |
|--------|-------------------|-------------|
| User | Account holder | id, displayName, gender, birthYear (or age range), bio, city, createdAt, locale, moderationStatus |
| Photo | Profile images | id, userId, url, sortOrder, isPrimary |
| Prompt | Catalog of prompt questions | id, textKey, category, isActive |
| PromptAnswer | User’s answer to a prompt | id, userId, promptId, answerText, sortOrder |
| Interest | Hangout / hobby tags | id, labelKey |
| UserInterest | User ↔ interest | userId, interestId |
| Preference | Discovery + safety prefs | userId, radiusKm, city, showMe, intent=friendsOnly, womenSafetyFilters? |
| Like | Like on profile or prompt/photo | id, fromUserId, toUserId, targetType (profile/prompt/photo), targetId, comment?, createdAt |
| Match | Mutual like | id, userAId, userBId, createdAt, unmatchedAt? |
| Message | Text chat message | id, matchId, senderId, body, createdAt, readAt? |
| VoiceMessage | Async voicemail (not live call) | id, matchId, senderId, audioUrl, durationSec, createdAt, listenedAt? |
| ConnectionStats | Per-user connection gender mix (for audit) | userId, womenShareAmongLikes, womenShareAmongMatches, sampleSize, computedAt, flaggedForReview? |
| Block | User blocked another | blockerId, blockedId, createdAt |
| Report | Safety report | id, reporterId, reportedUserId, reason (incl. **flirting**), details, createdAt, status |

### Relationships

| From | Relation | To | Note |
|------|----------|----|------|
| User | 1–n | Photo | Ordered gallery |
| User | 1–n | PromptAnswer | Typically 3+ answers |
| Prompt | 1–n | PromptAnswer | Shared prompt catalog |
| User | n–n | Interest | Via UserInterest |
| User | 1–1 | Preference | Discovery prefs |
| User | 1–n | Like (sent) | Outgoing likes |
| User | 1–n | Like (received) | Incoming likes |
| Match | 1–n | Message | Text unlocks after mutual like |
| Match | 1–n | VoiceMessage | Async voicemail only — no video call entity |
| User | 1–1 | ConnectionStats | Women-% among likes/matches for men; used in audits |
| User | n–n | User (Block) | Via Block |

### Persistence

- [ ] Device only (local)
- [x] Cloud / server
- [ ] Hybrid (local + sync)
- [ ] Undecided — detail: —

*Assumption for MVP example:* profiles, likes, matches, and chat live on a backend; device caches recent chats/profiles for UX.

---

## 8. Business rules

**Validation / required fields:**  
Minimum age (e.g. 18+). Gender required (needed for women-% audits and women safety prefs). At least 1 photo (preferably 2+). At least 3 prompt answers. Display name and city required. Intent must be friends/hangouts (no dating option in MVP).

**Limits:**  
Like comment max length (e.g. 140–200 chars). Daily like soft cap optional later. Max photos (e.g. 6). Chat only after Match. Voicemail max duration (e.g. 30–60 sec). **No video calls** in product. Location shown as city / approximate area — not precise pin in MVP.

**Anti-flirting (product + policy):**  
In-app UX should make flirting a poor fit (friend prompts, hangout framing, report path). Taking the conversation **off-app** (WhatsApp, IG, etc.) is a **mutual decision** between users — NADA neither forbids nor promotes it; it is outside product control once they leave. Report reason **“Flirting”** covers romantic/dating pressure in likes, comments, chat, or voicemail.

**Women-focused safety audit:**  
For men (and similar), compute **share of women** among people they like / match / keep as connections. Extremely high women-% (threshold TBD) with enough sample size → flag for **account review** (warn, rate-limit likes, restrict Discover, or ban). Optional: women can prefer discovering users with healthier/balanced patterns (privacy-preserving signal, not raw %).

**Permissions / roles:**  
All users are peers in-app. Moderators/ops review reports + ConnectionStats flags.

**Delete / archive rules:**  
Unmatch hides chat and removes from Matches. Block implies unmatch + mutual hide from Discover. Account delete removes profile from discovery; messages/voicemails may be tombstoned per privacy policy. Reports + audit flags retained for safety review.

**Other rules:**  
Copy and UI must reinforce “not dating.” No “looking for relationship” fields. Prompt catalog skewed to hangouts, hobbies, and platonic vibes (Hinge-like UX, friend-coded content).

---

## 9. Technical assumptions

| Topic | Decision / note |
|-------|-----------------|
| Account / login required? | Yes — needed for profile, likes, matches, chat. |
| Offline use | Limited: browse cached profiles/chats; likes/messages queue or fail gracefully when offline. |
| Push notifications | Yes — new match, new message / voicemail, (optional) new like. |
| External API / backend | Yes — auth, profiles, discovery, likes, matches, text + voicemail, moderation, ConnectionStats jobs. |
| Device permissions | Photos for profile; approximate location for discovery; **microphone** for voicemail only. **No video call / live camera session.** |
| Paid / subscription | Free MVP; monetization later (boosts, extra likes) if needed. |
| Analytics / telemetry | Funnel: signup → profile complete → first like → first match → first message. Safety: flirting-report rate; men flagged by women-% threshold. |

---

## 10. Success criteria (MVP is “done” when)

1. A new user can create a friends-only profile with photos + prompts and appear in Discover.
2. Two users can like each other (prompt-level like optional) and form a Match.
3. Matched users can exchange **text and voicemail** in-app; **video call is not available**.
4. User can report/block with reasons including **Flirting**; blocked users stop appearing for each other.
5. Onboarding and empty states clearly communicate “hang out / friends — not dating.”
6. Backend can compute men’s women-% among connections and flag accounts for review when skewed.

---

## 11. Open questions

- [ ] Auth method for v1: Apple + email, or phone OTP?
- [ ] Show “Someone liked you” before mutual match (Hinge-like), or only notify on match?
- [ ] Exact location model: city only vs approximate radius vs neighborhood?
- [ ] Gender filters / “who I want to meet” — include in MVP or keep fully open?
- [ ] Launch language: Turkish-only UI first, or bilingual TR+EN?
- [ ] Age display: exact age vs age range vs hidden?
- [ ] Do we allow group chats / third person later, or always 1:1?
- [ ] Women-% audit: exact threshold, min sample size, and whether women see a soft signal vs ops-only flag?
- [ ] Voicemail in MVP day-one, or text-first then voice in v1.1?
- [ ] How do we handle non-binary / prefer-not-to-say in women-% stats without breaking audits?

---

## How to use this doc

1. Treat sections 4–11 as a **Hinge-for-friends** starting draft — change anything that doesn’t match your vision.
2. Keep the MVP list short; keep “out of MVP” honest.
3. When screen inventory + data schema feel solid, move on to SwiftUI skeleton and backend shape.
