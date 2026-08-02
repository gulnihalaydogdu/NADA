# Firebase kurulum — NADA (Week 1)

Auth’un çalışması için **Firebase Console’da proje** + **`GoogleService-Info.plist`** gerekli.  
Bundle ID (Xcode): **`com.gulnihal.NADA`**

---

## 1. Firebase projesi oluştur

1. [Firebase Console](https://console.firebase.google.com) → Google hesabınla giriş
2. **Create a project** (veya mevcut projeyi kullan)
3. Proje adı öneri: `NADA` veya `nada-app`
4. Google Analytics: isteğe bağlı (MVP için kapalı olabilir)

---

## 2. iOS uygulaması ekle

1. Project Overview → **Add app** → **iOS**
2. **Apple bundle ID:** `com.gulnihal.NADA` (Xcode ile aynı olmalı)
3. App nickname: `NADA`
4. **Register app**
5. **`GoogleService-Info.plist` indir**
6. Dosyayı şuraya kopyala:

```
NADA/GoogleService-Info.plist
```

(Xcode sol panelde `NADA` klasöründe görünmeli. Git’e **commit etme** — `.gitignore`’da.)

7. Firebase Console’da **Continue** → **Continue to console**

---

## 3. Authentication aç

Firebase Console → **Build → Authentication → Get started**

### Email / Password
1. **Sign-in method** sekmesi
2. **Email/Password** → **Enable** → Save

### Apple (paid developer account only)
Personal Team **cannot** use Sign in with Apple. Skip until Apple Developer Program enrollment.

When ready:
1. **Apple** → **Enable** → Save in Firebase Console
2. Xcode → **Sign in with Apple** capability
3. `NADA.entitlements` → add `com.apple.developer.applesignin`
4. `NADAAuthConfig.isAppleSignInEnabled = true`

---

## 4. Firestore aç (W1-02 — `users`)

### 4a. Database oluştur

1. [Firebase Console](https://console.firebase.google.com) → projeni seç (**nada-app-33** veya plist’teki `PROJECT_ID`)
2. Sol menü → **Build** → **Firestore Database**
3. **Create database** (zaten varsa bu adımı atla)
4. **Secure rules** seç → **Next**  
   *(Test mode 30 gün açık bırakır; biz hemen kendi rules’ımızı yapıştıracağız.)*
5. **Location:** `eur3 (Europe)` veya `europe-west1` — oluşturduktan sonra değişmez, Türkiye’ye yakın olanı seç
6. **Enable** / **Create**

### 4b. Security rules yapıştır

1. Firestore sayfasında üst sekme → **Rules**
2. Editördeki **tüm metni sil**
3. Aşağıdakini **aynen** yapıştır (repo: `firebase/firestore.rules`):

```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    match /prompts/{promptId} {
      allow read: if request.auth != null;
      allow write: if false;
    }

    match /promptAnswers/{answerId} {
      allow create: if request.auth != null
                    && request.resource.data.userId == request.auth.uid;
      allow read, update, delete: if request.auth != null
                                  && resource.data.userId == request.auth.uid;
    }
  }
}
```

4. **Publish** (Yayınla)

`users` owner-only; `prompts` signed-in read; `promptAnswers` owner stub (Week 2).

### 4c. Doğrula (Console)

Tam şema: [`docs/FIRESTORE_USERS.md`](../docs/FIRESTORE_USERS.md)

1. Uygulamadan **yeni hesap** ile kayıt ol (email/şifre)
2. Firestore → **Data** sekmesi
3. **`users`** koleksiyonu → `{uid}` dokümanı görünmeli

Beklenen alanlar:

| Alan | Örnek |
|------|--------|
| `intent` | `"friendsOnly"` |
| `friendsIntentCompleted` | `false` → intent sonrası `true` |
| `locale` | `"en_TR"` |
| `createdAt` | timestamp |
| `email` | kayıt email’i (varsa) |
| `displayName` | Apple adı (varsa) |
| `gender`, `city` | null (Week 2’de dolar) |

**Firestore console linki** (PROJECT_ID’ni değiştir):

`https://console.firebase.google.com/project/PROJECT_ID/firestore`

Terminal’de proje ID’ni görmek için: `./scripts/check-firebase-setup.sh`

---

## 5. Doğrulama

Terminal (proje kökü):

```bash
./scripts/check-firebase-setup.sh
```

Xcode:
1. **Product → Clean Build Folder** (⇧⌘K)
2. Run (⌘R)
3. **Kayıt ol** → test email + şifre (min 6 karakter)

---

## 6. Sık hatalar

| Belirti | Çözüm |
|---------|--------|
| “Firebase yapılandırılmamış…” | `GoogleService-Info.plist` `NADA/` içinde mi? Dosya adı tam böyle mi? |
| Bundle ID mismatch | Firebase’deki bundle ID = `com.gulnihal.NADA` |
| Email auth failed | Authentication → Email/Password enabled mi? |
| Apple auth failed | Paid Apple Developer account required; MVP uses email only |
| Build: Missing FirebaseFirestore | File → Packages → Resolve Package Versions |
| Firestore permission denied | Firestore rules + Authentication uid eşleşiyor mu? |
| User doc yok | Firestore Database oluşturuldu mu? Console’da `users` koleksiyonuna bak |
| Storage permission denied | Storage Rules publish edildi mi? Blaze açık mı? Path `users/{uid}/photos/` mi? |
| Missing FirebaseStorage | File → Packages → Resolve Package Versions |

---

## 7. Storage — profil fotoğrafı (W1-05)

Blaze plan gerekir (Free Trial kredisi yeterli). Bucket örneği: `gs://nada-app-33.firebasestorage.app`.

### 7a. Storage aç (yoksa)

1. Console → **Build → Storage** → Get started
2. Location: **EU** (bucket oluşturulunca değişmez)
3. Rules’ı bir sonraki adımda kendi dosyamızla değiştireceğiz

### 7b. Security rules yapıştır

1. Storage → **Rules**
2. Tüm metni sil; repo’daki `firebase/storage.rules` içeriğini yapıştır:

```
rules_version = '2';

service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/photos/{fileName} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
                   && request.auth.uid == userId
                   && request.resource.size < 5 * 1024 * 1024
                   && request.resource.contentType.matches('image/.*');
    }
  }
}
```

3. **Publish**

### 7c. Doğrula

1. Uygulama → Profile → avatar’a dokun → fotoğraf seç
2. Storage → Files → `users/{uid}/photos/profile.jpg`
3. Firestore → `users/{uid}` → `photoURL` dolu olmalı
4. Uygulamayı kapatıp aç → avatar hâlâ görünmeli

Detay: [`docs/FIRESTORE_USERS.md`](FIRESTORE_USERS.md) (Storage bölümü)

---

## 8. Bits catalog — `prompts` (W1-06)

Detay: [`docs/FIRESTORE_PROMPTS.md`](FIRESTORE_PROMPTS.md) · seed: `firebase/prompts.seed.json`

1. Firestore → **Rules** → `firebase/firestore.rules` yapıştır → **Publish**  
   (`prompts` read-only for signed-in users; `promptAnswers` stub)
2. Firestore → **Data** → collection `prompts` → 5 dokümanı seed JSON’dan ekle  
   (Document ID = `id`; alanlar: `text`, `category`, `isActive`, `sortOrder`, `locale`)
3. Uygulama → Profile → **Bits** bölümünde 5 soru listelenmeli

---

## 9. Notlar

- Project ID: `nada-app-33`
- Storage: `gs://nada-app-33.firebasestorage.app`
