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

### Apple
1. **Apple** → **Enable** → Save  
2. iOS native Sign in with Apple için ek Service ID (MVP) genelde gerekmez; Xcode’da capability zaten var (`NADA.entitlements`).

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
  }
}
```

4. **Publish** (Yayınla)

Bu rule: giriş yapmış kullanıcı yalnızca `users/{kendi-uid}` dokümanını okuyup yazabilir.

### 4c. Doğrula (Console)

1. Uygulamadan **yeni hesap** ile kayıt ol (veya Apple ile giriş)
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
4. veya **Apple ile devam et** (gerçek cihaz veya simülatör + Apple ID)

---

## 6. Sık hatalar

| Belirti | Çözüm |
|---------|--------|
| “Firebase yapılandırılmamış…” | `GoogleService-Info.plist` `NADA/` içinde mi? Dosya adı tam böyle mi? |
| Bundle ID mismatch | Firebase’deki bundle ID = `com.gulnihal.NADA` |
| Email auth failed | Authentication → Email/Password enabled mi? |
| Apple auth failed | Authentication → Apple enabled mi? Gerçek cihazda dene. |
| Build: Missing FirebaseFirestore | File → Packages → Resolve Package Versions |
| Firestore permission denied | Firestore rules + Authentication uid eşleşiyor mu? |
| User doc yok | Firestore Database oluşturuldu mu? Console’da `users` koleksiyonuna bak |

---

## 7. Sonraki adım (Week 1 backend)

Auth + Firestore user çalışınca:
- **Storage** → profil fotoğrafları (W1-05)
- **Bits catalog** seed (W1-06)

Console linklerini buraya not al (opsiyonel):

- Project ID: `________________`
- Console URL: `________________`
