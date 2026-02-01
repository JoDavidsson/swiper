# Swiper – Ingestion compliance

- **Allowlist**: Crawling only for explicitly allowlisted sources (domains/path prefixes).
- **Robots**: When robotsRespect=true, respect robots.txt (e.g. urllib.robotparser).
- **Rate limiting**: Per-source rateLimitRps; no burst bypass.
- **Identity**: User-Agent SwiperBot/0.1 (contact: johannes@branchandleaf.se).
- **No bypass**: No anti-bot, CAPTCHA solving, login, or paywall circumvention.
- **Prefer feeds**: Primary ingestion is feeds (CSV/JSON/XML); crawl secondary, allowlisted only.
