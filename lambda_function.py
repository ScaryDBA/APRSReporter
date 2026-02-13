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
    url = f"https://api.aprs.fi/api/get?name={CALLSIGNS}&what=loc&apikey={API_KEY}&format=json"
    
    try:
        # Add 15 second timeout to prevent hanging
        with urllib.request.urlopen(url, timeout=15) as response:
            data = json.loads(response.read().decode())
        
        # Log the full API response for debugging
        logger.info(f"API Response: {json.dumps(data)}")
        
        # Check if API call was successful
        if data.get('result') != 'ok':
            logger.warning(f"API returned non-ok result: {data.get('result')}")
            return {'statusCode': 200, 'body': json.dumps('API call failed')}
        
        # Check if there are any entries
        entry_count = data.get('found', 0)
        if entry_count == 0:
            logger.warning(f"No entries found in API response")
            return {'statusCode': 200, 'body': json.dumps('No new data')}
        
        logger.info(f"Found {entry_count} entries")
        
        # Get the actual data from the 'entries' array
        entries = data.get('entries', [])
        
        # Get DB credentials from Secrets Manager (once, not per entry)
        secret_response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        secret_dict = json.loads(secret_response['SecretString'])
        
        # Connect to database (once, not per entry)
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=secret_dict['username'],
            password=secret_dict['password'],
            sslmode='require',
            connect_timeout=10
        )
        
        try:
            for entry in entries:
                logger.info(f"Processing entry: {json.dumps(entry)}")
                
                cur = conn.cursor()
                cur.execute("CALL reports.add_aprs_info(%s)", (json.dumps(entry),))
                conn.commit()
                cur.close()
                logger.info(f"Successfully inserted entry for {entry.get('name', 'unknown')}")
        finally:
            conn.close()
            
        logger.info(f"Processed {len(entries)} entries at {datetime.now()}")
        return {'statusCode': 200, 'body': json.dumps(f'Added {len(entries)} records')}
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise
