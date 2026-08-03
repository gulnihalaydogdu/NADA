# Firestore — Bits catalog (`prompts`) — W1-06 / W2-02

User-facing name: **Bits**. Internal collection/API: `prompts` / `Prompt`.

**Code:** `NADA/Core/Models/Prompt.swift`, `NADA/Core/Firestore/FirestorePromptService.swift`  
**Seed:** `firebase/prompts.seed.json` (28 EN prompts)  
**Rules:** `firebase/firestore.rules`

---

## `prompts/{promptId}` fields

| Field | Type | Notes |
|-------|------|--------|
| *(document id)* | string | Stable slug, e.g. `ideal-saturday` |
| `text` | string | English question shown in UI |
| `category` | string | `hangout` / `hobby` / `gamesMemes` / `newInTown` / `energy` |
| `isActive` | boolean | Only `true` returned by fetch |
| `sortOrder` | number | Ascending display order |
| `locale` | string | MVP: `"en"` |

---

## Seed in Console (one-time / when seed grows)

### Shortcut — script (recommended)

From the repo root:

```bash
cd /Users/gulnihal/Documents/NADA/NADA
npm install
```

**Auth (pick one):**

1. Firebase Console → Project settings → **Service accounts** → **Generate new private key**  
   Then:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/nada-app-33-....json"
   npm run seed:prompts
   ```

2. Or with gcloud ADC:
   ```bash
   gcloud auth application-default login
   export GCLOUD_PROJECT=nada-app-33
   npm run seed:prompts
   ```

This **merges** all docs from `firebase/prompts.seed.json` into `prompts/{id}` (safe to re-run).

### Manual (slow)

1. Firebase Console → **Firestore** → **Data**
2. Collection ID: `prompts`
3. For each object in `firebase/prompts.seed.json`:
   - Document ID = `id` field
   - Add fields `text`, `category`, `isActive`, `sortOrder`, `locale` (types: string / string / boolean / number / string)
4. Publish **Rules** from `firebase/firestore.rules` (includes `prompts` + `promptAnswers`)

Example doc `ideal-saturday`:

| Field | Value |
|-------|--------|
| text | Ideal Saturday hangout… |
| category | hangout |
| isActive | true |
| sortOrder | 1 |
| locale | en |

---

## Client fetch

`FirestorePromptService.fetchActivePrompts(locale: "en")`  
→ active + `locale == en`, sorted by `sortOrder`.

Smoke: Profile → **Bits** lists seeded questions (28 after full seed).

---

## `promptAnswers/{answerId}` (W2-03)

Document ID: `{userId}_{promptId}` (stable upsert).

| Field | Type | Notes |
|-------|------|--------|
| `userId` | string | Must match `auth.uid` |
| `promptId` | string | Catalog prompt id |
| `answerText` | string | Trimmed; **1…150** characters |
| `sortOrder` | number | Display order among the user’s answers (0…2) |

**Limits (client):** max **3** answers per user; one answer per prompt.

**Code:** `FirestorePromptService` — `fetchAnswers` / `upsertAnswer` / `deleteAnswer`  
**Auth:** `AuthManager.fetchBitAnswers` / `saveBitAnswer` / `deleteBitAnswer`

Rules: owner create/read/update/delete; create/update require the fields above.
