import os
import smtplib
from email.message import EmailMessage


def send_verification_email(receiver_email: str, verification_token: str):
    """Sends a verification email using Gmail."""
    sender_email = os.getenv("EMAIL_SENDER")
    app_password = os.getenv("EMAIL_PASSWORD")

    msg = EmailMessage()
    msg['Subject'] = 'Verify your Toe Pwar account'
    msg['From'] = sender_email
    msg['To'] = receiver_email

    verification_link = (
        f"https://flowfinance.onrender.com/api/auth/verify-email"
        f"?email={receiver_email}&token={verification_token}"
    )

    msg.set_content(f"""
    Welcome to Toe Pwar!

    Please verify your email address to activate your account.

    Click the link below to verify instantly:
    {verification_link}
    """)

    try:
        with smtplib.SMTP('smtp.gmail.com', 587) as server:
            server.starttls()
            server.login(sender_email, app_password)
            server.send_message(msg)
            print(f"✅ Verification email sent to {receiver_email}")
    except Exception as e:
        print(f"❌ Failed to send email: {e}")


# ── NEW ────────────────────────────────────────────────────────────────────────
def send_otp_email(receiver_email: str, otp: str):
    """Sends a 6-digit OTP for password reset via Gmail."""
    sender_email = os.getenv("EMAIL_SENDER")
    app_password = os.getenv("EMAIL_PASSWORD")

    msg = EmailMessage()
    msg['Subject'] = 'Your Toe Pwar Password Reset Code'
    msg['From'] = sender_email
    msg['To'] = receiver_email

    msg.set_content(f"""
    Hi there,

    You requested a password reset for your Toe Pwar account.

    Your verification code is:

        {otp}

    This code expires in 10 minutes.

    If you did not request this, please ignore this email — your account is safe.

    — The Toe Pwar Team
    """)

    # Rich HTML version
    msg.add_alternative(f"""\
    <html>
      <body style="font-family: Arial, sans-serif; background: #f4f4f4; padding: 40px 0;">
        <div style="max-width: 480px; margin: auto; background: #fff;
                    border-radius: 12px; padding: 40px; box-shadow: 0 4px 20px rgba(0,0,0,.08);">
          <div style="text-align:center; margin-bottom: 32px;">
            <div style="background: linear-gradient(135deg,#667eea,#764ba2);
                        width:64px; height:64px; border-radius:16px;
                        display:inline-flex; align-items:center; justify-content:center;">
              <span style="font-size:32px;">🔐</span>
            </div>
            <h1 style="margin:16px 0 4px; color:#333; font-size:22px;">Password Reset</h1>
            <p style="color:#888; margin:0;">Toe Pwar – Personal Finance AI</p>
          </div>

          <p style="color:#555; font-size:15px;">
            Use the code below to reset your password. It expires in <strong>10 minutes</strong>.
          </p>

          <div style="background:#f0f0ff; border-radius:12px; padding:24px; text-align:center; margin:24px 0;">
            <span style="font-size:40px; font-weight:bold; letter-spacing:12px;
                         color:#667eea; font-family:monospace;">{otp}</span>
          </div>

          <p style="color:#aaa; font-size:13px; text-align:center;">
            If you didn't request this, you can safely ignore this email.
          </p>
        </div>
      </body>
    </html>
    """, subtype='html')

    try:
        with smtplib.SMTP('smtp.gmail.com', 587) as server:
            server.starttls()
            server.login(sender_email, app_password)
            server.send_message(msg)
            print(f"✅ OTP email sent to {receiver_email}")
    except Exception as e:
        print(f"❌ Failed to send OTP email: {e}")
        raise  # re-raise so the caller can log it