import json
import urllib.request
import psycopg2
import os
import logging
from datetime import datetime
import boto3

SECRET_NAME = "aprs-db-secret"
secrets_client = boto3.client('secretsmanager')
ssm_client = boto3.client('ssm')

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configuration loaded from Parameter Store and Secrets Manager
def get_config():
    """Get configuration from AWS Parameter Store and Secrets Manager"""
    # Get parameters from Parameter Store (free)
    params = ssm_client.get_parameters(
        Names=['/aprs/callsign', '/aprs/db-host', '/aprs/db-name']
    )
    config = {p['Name'].split('/')[-1]: p['Value'] for p in params['Parameters']}
    
    # Get secrets (API key and DB credentials)
    secret = secrets_client.get_secret_value(SecretId=SECRET_NAME)
    secret_dict = json.loads(secret['SecretString'])
    
    return {
        'callsign': config['callsign'],
        'db_host': config['db-host'],
        'db_name': config['db-name'],
        'api_key': secret_dict['aprs_api_key'],
        'db_username': secret_dict['username'],
        'db_password': secret_dict['password']
    }

# Cache config at module level (Lambda reuses containers)
CONFIG = get_config()

def lambda_handler(event, context):
    # Fetch from aprs.fi
    url = f"https://api.aprs.fi/api/get?name={CONFIG['callsign']}&what=loc&apikey={CONFIG['api_key']}&format=json"
    
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
        
        # Get DB credentials from config (already cached)
        # Connect to database (once, not per entry)
        conn = psycopg2.connect(
            host=CONFIG['db_host'],
            database=CONFIG['db_name'],
            user=CONFIG['db_username'],
            password=CONFIG['db_password'],
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
