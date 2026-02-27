import os
import smtplib
from email.message import EmailMessage

def send_verification_email(receiver_email: str, verification_token: str):
    """Sends a verification email using a free Gmail account."""
    
    # Replace these with your actual credentials
    sender_email = os.getenv("EMAIL_SENDER")
    app_password = os.getenv("EMAIL_PASSWORD")
    
    msg = EmailMessage()
    msg['Subject'] = 'Verify your Flow Finance account'
    msg['From'] = sender_email
    msg['To'] = receiver_email
    
    # In production, change localhost to your actual frontend domain
    verification_link = f"https://flowfinancetest.onrender.com/api/auth/verify-email?email={receiver_email}&token={verification_token}"
    
    msg.set_content(f"""
    Welcome to Flow Finance!
    
    Please verify your email address to activate your account. 
    
    Verification Token: {verification_token}
    
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