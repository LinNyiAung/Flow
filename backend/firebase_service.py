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
                    channel_id='toe_pwar_notifications',
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


def _stringify_data(data: dict | None) -> dict:
    """FCM data payload values must all be strings."""
    return {str(k): ("" if v is None else str(v)) for k, v in (data or {}).items()}


def send_fcm_data_message(fcm_token: str, data: dict = None) -> bool:
    """
    Send a data-only ("silent") FCM message: no Notification block, no badge, no
    sound. The app receives it in its message handler and can refresh state.
    Blocking — call via run_in_threadpool from async code.
    """
    if _firebase_app is None:
        print("⚠️  Firebase not initialized, skipping FCM data message")
        return False

    try:
        message = messaging.Message(
            data=_stringify_data(data),
            token=fcm_token,
            android=messaging.AndroidConfig(priority='high'),
            apns=messaging.APNSConfig(
                headers={
                    'apns-push-type': 'background',
                    'apns-priority': '5',
                },
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(content_available=True),
                ),
            ),
        )
        response = messaging.send(message)
        print(f'✅ FCM data message sent successfully: {response}')
        return True

    except messaging.UnregisteredError:
        print('❌ FCM token is invalid or unregistered (data message)')
        return False
    except Exception as e:
        print(f'❌ FCM data message error: {e}')
        return False


FCM_MULTICAST_LIMIT = 500


def send_fcm_to_multiple(
    fcm_tokens: list[str],
    title: str,
    body: str,
    data: dict = None
) -> dict:
    """
    Send FCM notification to multiple devices using send_each_for_multicast,
    in chunks of at most 500 tokens (the FCM multicast limit).
    Blocking — call via run_in_threadpool from async code.
    """
    if not fcm_tokens:
        return {"success": 0, "failure": 0}

    if _firebase_app is None:
        print("⚠️  Firebase not initialized, skipping FCM notifications")
        return {"success": 0, "failure": len(fcm_tokens)}

    payload_data = _stringify_data(data)
    total_success = 0
    total_failure = 0

    for start in range(0, len(fcm_tokens), FCM_MULTICAST_LIMIT):
        chunk = fcm_tokens[start:start + FCM_MULTICAST_LIMIT]
        try:
            multicast_message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=payload_data,
                tokens=chunk,
                android=messaging.AndroidConfig(
                    priority='high',
                    notification=messaging.AndroidNotification(
                        sound='default',
                        channel_id='toe_pwar_notifications',
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

            response = messaging.send_each_for_multicast(multicast_message)
            total_success += response.success_count
            total_failure += response.failure_count

            if response.failure_count > 0:
                for idx, resp in enumerate(response.responses):
                    if not resp.success:
                        print(f'❌ Failed to send to token {start + idx}: {resp.exception}')

        except Exception as e:
            print(f'❌ FCM multicast error (chunk starting at {start}): {e}')
            import traceback
            traceback.print_exc()
            total_failure += len(chunk)

    print(f'✅ FCM multicast sent: {total_success} success, {total_failure} failure')
    return {"success": total_success, "failure": total_failure}