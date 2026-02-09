import json
import urllib.request
import psycopg2
import os
import logging
from datetime import datetime
import boto3
SECRET_NAME = "aprs-db-secret"  # Your Secrets Manager secret name
secrets_client = boto3.client('secretsmanager')

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Replace these
CALLSIGNS = "KC1KCE-8"  # Comma-separated, e.g., "N0CALL-7,KC5AAA-9"
API_KEY = "REDACTED_API_KEY"
DB_HOST = "aprs-instance-1.c2ek9ilzyxhz.us-east-1.rds.amazonaws.com"
DB_NAME = "aprs_reporter"

def lambda_handler(event, context):
    # Fetch from aprs.fi
    url = f"https://api.aprs.fi/api/get?what=loc&call={CALLSIGNS}&apikey={API_KEY}&format=json"
    
    try:
        with urllib.request.urlopen(url) as response:
            data = json.loads(response.read().decode())
        
        if data.get('entries') != 1:
            logger.warning(f"Unexpected entries: {data.get('entries')}")
            return {'statusCode': 200, 'body': json.dumps('No new data')}
        
        entries = data['entries']
        for entry in entries:
            # Call your stored procedure
            # Get DB credentials from Secrets Manager
            secret_response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
            secret_dict = json.loads(secret_response['SecretString'])

            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=secret_dict['username'],
                password=secret_dict['password'],
                sslmode='require'
            )

            cur = conn.cursor()
            cur.execute("CALL reports.add_aprs_info(%s)", (json.dumps(entry),))
            conn.commit()
            cur.close()
            conn.close()
            
        logger.info(f"Processed {len(entries)} entries at {datetime.now()}")
        return {'statusCode': 200, 'body': json.dumps(f'Added {len(entries)} records')}
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise
