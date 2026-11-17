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


def _stringify_data(data: dict | None) -> dict:
    """FCM data payload values must all be strings."""
    return {str(k): ("" if v is None else str(v)) for k, v in (data or {}).items()}


FCM_MULTICAST_LIMIT = 500


def _push_message(token: str, title: str | None, body: str | None, data: dict | None) -> messaging.Message:
    """A visible notification (title set), or a data-only ("silent") message when title is None: no Notification
    block, no badge, no sound; the app receives it in its message handler and can refresh state."""
    if title is None:
        return messaging.Message(
            data=_stringify_data(data),
            token=token,
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
    return messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data=_stringify_data(data),
        token=token,
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


def send_push(tokens: list[str], title: str | None, body: str | None, data: dict | None) -> dict:
    """
    Send one push to each of these device tokens (a person's devices). title None = a data-only ("silent") message.

    Returns {"success": n, "failure": n, "unregistered": [tokens Firebase reports as unregistered]}: the caller
    deletes those device rows (other failures keep them).
    Blocking — call via asyncio.to_thread / run_in_threadpool from async code.
    """
    tokens = list(dict.fromkeys(t for t in tokens if t))
    result = {"success": 0, "failure": 0, "unregistered": []}
    if not tokens:
        return result

    if _firebase_app is None:
        print("⚠️  Firebase not initialized, skipping FCM push")
        result["failure"] = len(tokens)
        return result

    for start in range(0, len(tokens), FCM_MULTICAST_LIMIT):
        chunk = tokens[start:start + FCM_MULTICAST_LIMIT]
        try:
            response = messaging.send_each([_push_message(t, title, body, data) for t in chunk])
            result["success"] += response.success_count
            result["failure"] += response.failure_count
            for token, resp in zip(chunk, response.responses):
                if resp.success:
                    continue
                if isinstance(resp.exception, messaging.UnregisteredError):
                    result["unregistered"].append(token)
                    print('❌ FCM token is unregistered; its device will be removed')
                else:
                    print(f'❌ FCM error: {resp.exception}')
        except Exception as e:
            print(f'❌ FCM push error (chunk starting at {start}): {e}')
            result["failure"] += len(chunk)

    print(f'✅ FCM push sent: {result["success"]} success, {result["failure"]} failure')
    return result


def send_fcm_to_multiple(
    fcm_tokens: list[str],
    title: str,
    body: str,
    data: dict = None
) -> dict:
    """
    Send FCM notification to multiple devices using send_each_for_multicast,
    in chunks of at most 500 tokens (the FCM multicast limit).

    Returns {"success": n, "failure": n, "unregistered": [tokens Firebase reports as unregistered]}: the caller
    deletes those device rows (other failures keep them).
    Blocking — call via run_in_threadpool from async code.
    """
    if not fcm_tokens:
        return {"success": 0, "failure": 0, "unregistered": []}

    if _firebase_app is None:
        print("⚠️  Firebase not initialized, skipping FCM notifications")
        return {"success": 0, "failure": len(fcm_tokens), "unregistered": []}

    payload_data = _stringify_data(data)
    total_success = 0
    total_failure = 0
    unregistered = []

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
                        if isinstance(resp.exception, messaging.UnregisteredError):
                            unregistered.append(chunk[idx])
                        print(f'❌ Failed to send to token {start + idx}: {resp.exception}')

        except Exception as e:
            print(f'❌ FCM multicast error (chunk starting at {start}): {e}')
            import traceback
            traceback.print_exc()
            total_failure += len(chunk)

    print(f'✅ FCM multicast sent: {total_success} success, {total_failure} failure')
    return {"success": total_success, "failure": total_failure, "unregistered": unregistered}
