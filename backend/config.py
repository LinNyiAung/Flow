import json
import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    MONGODB_URL = os.getenv("MONGODB_URL")
    DATABASE_NAME = os.getenv("DATABASE_NAME")
    SECRET_KEY = os.getenv("SECRET_KEY")
    ALGORITHM = "HS256"
    # 30 days
    ACCESS_TOKEN_EXPIRE_MINUTES = 43200 
    
    # AI Chatbot settings
    OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
    OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    
    # NEW: Gemini settings
    GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
    GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

    EMAIL_SENDER = os.getenv("EMAIL_SENDER")
    EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD")
    
    
    FIREBASE_CREDENTIALS_PATH: str = os.getenv(
        "FIREBASE_CREDENTIALS_PATH", 
        "toepwar-ai-firebase-adminsdk-fbsvc-cc42c07a7c.json"
    )
    
    # NEW: Allow passing the credentials as a raw JSON string
    FIREBASE_CREDENTIALS_JSON: dict = None
    
    _json_str = os.getenv("FIREBASE_CREDENTIALS_JSON_STR")
    if _json_str:
        try:
            FIREBASE_CREDENTIALS_JSON = json.loads(_json_str)
        except json.JSONDecodeError:
            print("❌ Error decoding FIREBASE_CREDENTIALS_JSON_STR")
    
    MAX_CHAT_HISTORY = int(os.getenv("MAX_CHAT_HISTORY", "20"))

    # Public base URL of this API (used in e-mail verification links)
    PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "https://flowfinance.onrender.com").rstrip("/")

    # Optional one-time super-admin bootstrap (only used when the admins collection is empty)
    ADMIN_BOOTSTRAP_EMAIL = os.getenv("ADMIN_BOOTSTRAP_EMAIL")
    ADMIN_BOOTSTRAP_PASSWORD = os.getenv("ADMIN_BOOTSTRAP_PASSWORD")
    ADMIN_BOOTSTRAP_NAME = os.getenv("ADMIN_BOOTSTRAP_NAME", "Super Admin")

    # ---- Client IP behind a reverse proxy (used by the admin login lockout) ----
    # The lockout is keyed by (email, client IP). Behind a proxy/load balancer the TCP
    # peer (request.client.host) is the proxy, so every admin would share one IP and a
    # few bad logins from anyone would lock everyone out. Options (default: trust nothing,
    # use the TCP peer):
    #
    # TRUSTED_PROXY_IPS: comma-separated IPs and/or CIDRs of your own proxies, e.g.
    #   "10.0.0.0/8,127.0.0.1". When the TCP peer is one of them, the client IP is taken
    #   from X-Forwarded-For by walking it right-to-left and skipping trusted proxies (the
    #   first untrusted hop is the client). Requests whose peer is not a trusted proxy
    #   ignore X-Forwarded-For.
    #
    # TRUST_FORWARDED_FOR=true: always use the RIGHT-MOST X-Forwarded-For entry, i.e. the
    #   address appended by the immediate proxy. Use this on platforms whose proxy
    #   addresses are not known/stable, e.g. Render (the app is only reachable through
    #   Render's proxy, which appends the connecting client's IP to X-Forwarded-For).
    #   Entries left of it are whatever the client sent and are ignored, so clients can't
    #   spoof their lockout key. If your platform chains SEVERAL proxies of its own (the
    #   right-most entry would then be another internal proxy), use TRUSTED_PROXY_IPS
    #   instead. Never enable this when the app is directly reachable without the proxy.
    #
    # Both settings: addresses are normalised (IPv4-mapped IPv6 "::ffff:a.b.c.d" -> IPv4,
    # ports like "1.2.3.4:5678" / "[2001:db8::1]:443" stripped); unparseable
    # X-Forwarded-For entries are never trusted (the TCP peer is used instead).
    TRUSTED_PROXY_IPS = [
        ip.strip() for ip in (os.getenv("TRUSTED_PROXY_IPS") or "").split(",") if ip.strip()
    ]
    TRUST_FORWARDED_FOR = (os.getenv("TRUST_FORWARDED_FOR") or "").strip().lower() in ("1", "true", "yes", "on")

    # ---- CORS ----
    # CORS_ALLOWED_ORIGINS: comma-separated list of browser origins allowed to call the
    #   API, e.g. "https://admin.example.com,http://localhost:5173". Default "*" (any
    #   origin) for backward compatibility; set it to the admin panel's origin(s) in
    #   production. Credentials (cookies / HTTP auth) are NOT allowed cross-origin:
    #   authentication is the Authorization: Bearer header, which CORS permits without
    #   allow_credentials, so a wildcard can never reflect arbitrary origins with
    #   credentials. Mobile apps are not affected by CORS.
    CORS_ALLOWED_ORIGINS = [
        o.strip().rstrip("/")
        for o in (os.getenv("CORS_ALLOWED_ORIGINS") or "*").split(",")
        if o.strip()
    ] or ["*"]

settings = Settings()