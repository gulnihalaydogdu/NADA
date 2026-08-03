# Firestore — Bits catalog (`prompts`) — W1-06

User-facing name: **Bits**. Internal collection/API: `prompts` / `Prompt`.

**Code:** `NADA/Core/Models/Prompt.swift`, `NADA/Core/Firestore/FirestorePromptService.swift`  
**Seed:** `firebase/prompts.seed.json`  
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

## Seed in Console (one-time)

1. Firebase Console → **Firestore** → **Data**
2. **Start collection** → Collection ID: `prompts`
3. For each object in `firebase/prompts.seed.json`:
   - Document ID = `id` field
   - Add fields `text`, `category`, `isActive`, `sortOrder`, `locale` (types: string / string / boolean / number / string)
4. Publish updated **Rules** from `firebase/firestore.rules` (includes `prompts` + `promptAnswers`)

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
→ `where isActive == true` + `locale == en`, sorted by `sortOrder`.

Smoke: Profile tab → **Bits** section lists the 5 seeded questions.

---

## `promptAnswers` stub (Week 2)

Collection: `promptAnswers/{answerId}`

| Field | Type |
|-------|------|
| `userId` | string |
| `promptId` | string |
| `answerText` | string |
| `sortOrder` | number |

Rules: owner create/read/update/delete. No client write in Week 1.
