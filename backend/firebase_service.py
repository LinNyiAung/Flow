import firebase_admin
from firebase_admin import credentials, messaging
from config import settings
import os

_firebase_app = None

def initialize_firebase():
    """Initialize Firebase Admin SDK"""
    global _firebase_app
    
    if _firebase_app is not None:
        return _firebase_app
    
    try:
        cred = None
        
        # PRIORITY 1: Try loading from Environment Variable (Best for Production/Render/Heroku)
        if settings.FIREBASE_CREDENTIALS_JSON:
            print("🔥 Loading Firebase creds from ENV variable...")
            cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_JSON)
            
        # PRIORITY 2: Try loading from local file (Best for Local Dev)
        elif os.path.exists(settings.FIREBASE_CREDENTIALS_PATH):
            print(f"🔥 Loading Firebase creds from file: {settings.FIREBASE_CREDENTIALS_PATH}")
            cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
            
        else:
            print(f"⚠️  Firebase credentials not found.")
            return None
        
        _firebase_app = firebase_admin.initialize_app(cred)
        print("✅ Firebase Admin SDK initialized successfully")
        return _firebase_app
        
    except Exception as e:
        print(f"❌ Firebase initialization error: {e}")
        return None


def send_fcm_notification(
    fcm_token: str,
    title: str,
    body: str,
    data: dict = None
) -> bool:
    """Send FCM push notification to a specific device"""
    if _firebase_app is None:
        print("⚠️  Firebase not initialized, skipping FCM notification")
        return False
    
    try:
        # Build the message
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=data or {},
            token=fcm_token,
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    sound='default',
                    channel_id='flow_finance_notifications',
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound='default',
                        badge=1,
                    ),
                ),
            ),
        )
        
        # Send the message
        response = messaging.send(message)
        print(f'✅ FCM notification sent successfully: {response}')
        return True
        
    except messaging.UnregisteredError:
        print(f'❌ FCM token is invalid or unregistered: {fcm_token}')
        # TODO: Remove this token from database
        return False
    except Exception as e:
        print(f'❌ FCM error: {e}')
        return False


def send_fcm_to_multiple(
    fcm_tokens: list[str],
    title: str,
    body: str,
    data: dict = None
) -> dict:
    """Send FCM notification to multiple devices using send_each_for_multicast"""
    if _firebase_app is None:
        print("⚠️  Firebase not initialized, skipping FCM notifications")
        return {"success": 0, "failure": len(fcm_tokens)}
    
    if not fcm_tokens:
        return {"success": 0, "failure": 0}
    
    try:
        # Create MulticastMessage
        multicast_message = messaging.MulticastMessage(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=data or {},
            tokens=fcm_tokens,
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    sound='default',
                    channel_id='flow_finance_notifications',
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound='default',
                        badge=1,
                    ),
                ),
            ),
        )
        
        # Send using send_each_for_multicast (correct method for v7.x)
        response = messaging.send_each_for_multicast(multicast_message)
        
        print(f'✅ FCM multicast sent: {response.success_count} success, {response.failure_count} failure')
        
        # Log any failures for debugging
        if response.failure_count > 0:
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    print(f'❌ Failed to send to token {idx}: {resp.exception}')
        
        return {
            "success": response.success_count,
            "failure": response.failure_count,
        }
        
    except Exception as e:
        print(f'❌ FCM multicast error: {e}')
        import traceback
        traceback.print_exc()
        return {"success": 0, "failure": len(fcm_tokens)}