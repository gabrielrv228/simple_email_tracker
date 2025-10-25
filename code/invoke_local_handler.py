import os
import sys

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

try:
    import email_tracker as email_tracker_mod
    send_telegram_message = email_tracker_mod.send_telegram_message
except Exception as e:
    print(f"ERROR importing email_tracker module: {e}")
    sys.exit(2)


def main(message):
    bot_token = os.getenv("TF_VAR_bot_token")
    chat_id = os.getenv("TF_VAR_chat_id")

    if not bot_token or not chat_id:
        print("ERROR: BOT_TOKEN and CHAT_ID must be set in the environment to send a Telegram message.")
        sys.exit(2)

    try:
        send_telegram_message(bot_token, chat_id, message)
        print("send_telegram_message invoked (check Telegram for delivery).")
        # Note: the underlying function logs status; it doesn't currently return a boolean.
        sys.exit(0)
    except Exception as e:
        print(f"ERROR invoking send_telegram_message: {e}")
        sys.exit(1)


if __name__ == "__main__":
    # Expect the message to be provided as a command-line argument.
    if len(sys.argv) < 2:
        print("Usage: invoke_local_handler.py <message>")
        sys.exit(2)

    # Allow messages with spaces by joining all args
    msg = " ".join(sys.argv[1:])
    main(msg)
