import json
import os
import requests

bot_token = os.getenv("BOT_TOKEN")  
chat_id   = os.getenv("CHAT_ID")    
pixel_img = os.getenv("PIXEL_IMG") 

def send_telegram_message(bot_token, chat_id, _message):
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    print(_message)

    try:
        params = {"chat_id": chat_id,"text":_message}
        response = requests.post(url, params=params,)

        if response.status_code == 200:
            print("Message sent successfully!")
        else:
            print(f"Failed to send message. Status code: {response.status_code}\nError:{response.content}")

    except Exception as e :
        print(e)
        pass
    
def handler(event, context):
    query_params = event.get('queryStringParameters', {})
    # Access specific query parameters
    email = query_params.get('em') 

    info = query_params.get('info') 
    
    if email and info == None:
        send_telegram_message(bot_token,chat_id,f"Email viewed by : {email} ")
    if email and info != None:
        send_telegram_message(bot_token,chat_id,f"Email viewed by : {email} \n Additional info: {info}")

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'image/png',
            'Content-Disposition': 'inline; filename="image.png"'
        },
        'body': pixel_img,
        'isBase64Encoded': True
    }