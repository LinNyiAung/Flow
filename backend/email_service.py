import os
import smtplib
from email.message import EmailMessage
from html import escape
from urllib.parse import quote, urlencode

from notification_service import translate

LANGS = ("en", "my")


def _card(icon: str, heading: str, intro: str, middle: str, footer: str) -> str:
    """The shared card layout. Every text is escaped here; `middle` is built by the caller from trusted markup."""
    return f"""\
<html>
  <body style="font-family: Arial, sans-serif; background: #f4f4f4; padding: 40px 0;">
    <div style="max-width: 480px; margin: auto; background: #fff;
                border-radius: 12px; padding: 40px; box-shadow: 0 4px 20px rgba(0,0,0,.08);">
      <div style="text-align:center; margin-bottom: 32px;">
        <div style="background: linear-gradient(135deg,#667eea,#764ba2);
                    width:64px; height:64px; border-radius:16px;
                    display:inline-flex; align-items:center; justify-content:center;">
          <span style="font-size:32px;">{icon}</span>
        </div>
        {heading}
        <p style="color:#888; margin:0;">Toe Pwar – Personal Finance AI</p>
      </div>
{intro}
{middle}
{footer}
    </div>
  </body>
</html>
"""


def _heading(text: str) -> str:
    return f'<h1 style="margin:16px 0 4px; color:#333; font-size:22px;">{escape(text)}</h1>'


def _intro(text: str) -> str:
    return f'      <p style="color:#555; font-size:15px;">{escape(text)}</p>'


def _footer(text: str) -> str:
    return f'      <p style="color:#aaa; font-size:13px; text-align:center;">{escape(text)}</p>'


def build_verification_email(receiver_email: str, verification_token: str) -> EmailMessage:
    """The verification email: English then Myanmar texts, one button labelled "EN / MY", the link also printed as text."""
    msg = EmailMessage()
    msg['Subject'] = " / ".join(translate("email_verify_subject", lang) for lang in LANGS)
    msg['From'] = os.getenv("EMAIL_SENDER")
    msg['To'] = receiver_email

    base_url = os.getenv("PUBLIC_BASE_URL", "https://toepwar-t9vc.onrender.com").rstrip("/")
    query = urlencode({"email": receiver_email, "token": verification_token}, quote_via=quote)
    link = f"{base_url}/api/auth/verify-email?{query}"
    link_html = escape(link, quote=True)
    button = " / ".join(translate("email_verify_button", lang) for lang in LANGS)

    def texts(key):
        return [translate(f"email_verify_{key}", lang) for lang in LANGS]

    headings, intros, footers = texts("heading"), texts("intro"), texts("footer")

    msg.set_content("\n\n".join([
        "\n\n".join([headings[0], intros[0]]),
        "\n\n".join([headings[1], intros[1]]),
        f"{button}:\n{link}",
        "\n\n".join(footers),
    ]) + "\n")

    middle = f"""\
      <div style="text-align:center; margin:28px 0;">
        <a href="{link_html}" style="display:inline-block; background:#667eea; background-image:linear-gradient(135deg,#667eea,#764ba2);
                  color:#ffffff; text-decoration:none; font-weight:bold; font-size:16px;
                  padding:14px 28px; border-radius:10px;">{escape(button)}</a>
      </div>
      <p style="color:#888; font-size:12px; text-align:center; word-break:break-all;">{link_html}</p>"""
    body = "\n".join([
        _intro(headings[0]).replace("color:#555; font-size:15px;", "color:#333; font-size:18px; font-weight:bold;"),
        _intro(intros[0]),
        _intro(headings[1]).replace("color:#555; font-size:15px;", "color:#333; font-size:18px; font-weight:bold;"),
        _intro(intros[1]),
    ])
    msg.add_alternative(_card("✉️", _heading(headings[0]), body, middle,
                              "\n".join(_footer(f) for f in footers)), subtype='html')
    return msg


def build_reset_email(receiver_email: str, otp: str, lang: str) -> EmailMessage:
    """The password-reset email in the person's language, with the code in its fixed box."""
    msg = EmailMessage()
    msg['Subject'] = translate("email_reset_subject", lang)
    msg['From'] = os.getenv("EMAIL_SENDER")
    msg['To'] = receiver_email

    heading = translate("email_reset_heading", lang)
    intro = translate("email_reset_intro", lang)
    footer = translate("email_reset_footer", lang)

    msg.set_content(f"{heading}\n\n{intro}\n\n    {otp}\n\n{footer}\n")

    middle = f"""\
      <div style="background:#f0f0ff; border-radius:12px; padding:24px; text-align:center; margin:24px 0;">
        <span style="font-size:40px; font-weight:bold; letter-spacing:12px;
                     color:#667eea; font-family:monospace;">{escape(otp)}</span>
      </div>"""
    msg.add_alternative(_card("🔐", _heading(heading), _intro(intro), middle, _footer(footer)), subtype='html')
    return msg


def send_verification_email(receiver_email: str, verification_token: str):
    """Sends a verification email using Gmail."""
    sender_email = os.getenv("EMAIL_SENDER")
    app_password = os.getenv("EMAIL_PASSWORD")

    try:
        msg = build_verification_email(receiver_email, verification_token)
        with smtplib.SMTP('smtp.gmail.com', 587) as server:
            server.starttls()
            server.login(sender_email, app_password)
            server.send_message(msg)
            print(f"✅ Verification email sent to {receiver_email}")
    except Exception as e:
        print(f"❌ Failed to send email: {e}")


# ── NEW ────────────────────────────────────────────────────────────────────────
def send_otp_email(receiver_email: str, otp: str, lang: str = "en"):
    """Sends a 6-digit OTP for password reset via Gmail."""
    sender_email = os.getenv("EMAIL_SENDER")
    app_password = os.getenv("EMAIL_PASSWORD")

    try:
        msg = build_reset_email(receiver_email, otp, lang)
        with smtplib.SMTP('smtp.gmail.com', 587) as server:
            server.starttls()
            server.login(sender_email, app_password)
            server.send_message(msg)
            print(f"✅ OTP email sent to {receiver_email}")
    except Exception as e:
        print(f"❌ Failed to send OTP email: {e}")
        raise  # re-raise so the caller can log it
