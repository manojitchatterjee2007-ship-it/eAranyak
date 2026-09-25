# Cloudflare Security & Content Protection Architecture

This document provides the Cloudflare WAF, anti-bot, rate-limiting, and cache control configuration for eআরণ্যক.

---

## 1. Overview & Content Delivery Hierarchy

```
Browser / App Client
       ↓
Cloudflare Edge WAF & Bot Management
       ↓
Rate Limiter & Hotlink Prevention
       ↓
Supabase Storage API / Edge Gateway
       ↓
Authenticated Signed Asset Delivery (120s TTL)
```

---

## 2. Recommended Cloudflare Rules Configuration

### A. Rate Limiting Rules
Configure under **Security > WAF > Rate limiting rules**:

| Rule Name | Target Path | Threshold | Action |
| :--- | :--- | :--- | :--- |
| `Protect Signed Storage Requests` | `/storage/v1/object/sign/*` | 60 requests / 1 min per IP | Block (10 min) or Managed Challenge |
| `Protect API Auth Endpoints` | `/auth/v1/*` | 20 requests / 1 min per IP | Managed Challenge |
| `Protect Magazine Assets` | `/storage/v1/object/authenticated/magazine_pages/*` | 120 requests / 1 min per IP | Rate Limit |

### B. WAF Custom Rules
Configure under **Security > WAF > Custom rules**:

#### 1. Hotlink Prevention for Protected Buckets
- **Expression**:
  ```
  (http.request.uri.path contains "/storage/v1/object/" and not http.referer contains "earanyak.pages.dev" and not http.referer contains "localhost")
  ```
- **Action**: Block

#### 2. Suspicious Scraping & Bot Mitigation
- **Expression**:
  ```
  (cf.bot_management.score < 30 and http.request.uri.path contains "/storage/v1/object/")
  ```
- **Action**: Managed Challenge

### C. Cache Rules
Configure under **Caching > Cache Rules**:

#### 1. Bypass Edge Cache for Signed Media
- **Expression**:
  ```
  (http.request.uri.path contains "/storage/v1/object/sign/" or http.request.uri.query contains "token=")
  ```
- **Setting**: Bypass Cache (Ensures expired signed URLs are re-verified by Supabase origin).

---

## 3. Manual Steps in Cloudflare Dashboard

1. Log in to your **Cloudflare Dashboard**.
2. Select the `earanyak.pages.dev` / primary domain zone.
3. Go to **Security > WAF > Rate limiting rules** and create the rate limiting rules listed above.
4. Go to **Security > Bot Management** and set **Bot Fight Mode** or **Managed Rules** to ON.
5. Go to **Caching > Cache Rules** and add the Bypass Edge Cache rule for `/storage/v1/object/sign/`.
