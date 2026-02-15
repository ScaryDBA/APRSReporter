"""
Lambda function for reverse geocoding APRS coordinates
Uses OpenStreetMap Nominatim API (free, rate-limited to 1 req/sec)
Runs hourly via EventBridge to geocode new locations
"""

import json
import psycopg2
import boto3
import urllib.request
import urllib.parse
import time
from datetime import datetime

SECRET_NAME = "aprs-db-secret"
secrets_client = boto3.client('secretsmanager')
ssm_client = boto3.client('ssm')

# Configuration loaded from Parameter Store
def get_config():
    """Get configuration from AWS Parameter Store and Secrets Manager"""
    params = ssm_client.get_parameters(
        Names=['/aprs/db-host', '/aprs/db-name']
    )
    config = {p['Name'].split('/')[-1]: p['Value'] for p in params['Parameters']}
    
    secret = secrets_client.get_secret_value(SecretId=SECRET_NAME)
    secret_dict = json.loads(secret['SecretString'])
    
    return {
        'db_host': config['db-host'],
        'db_name': config['db-name'],
        'db_username': secret_dict['username'],
        'db_password': secret_dict['password']
    }

# Cache config at module level
CONFIG = get_config()

# Nominatim API configuration
NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"
USER_AGENT = "APRSReporter/1.0 (APRS tracking demo)"

def get_db_connection():
    """Get database connection with credentials from config"""
    return psycopg2.connect(
        host=CONFIG['db_host'],
        database=CONFIG['db_name'],
        user=CONFIG['db_username'],
        password=CONFIG['db_password'],
        sslmode='require',
        connect_timeout=10
    )

def reverse_geocode(lat, lon):
    """
    Reverse geocode a coordinate using Nominatim
    Returns: (city, state, country) tuple or (None, None, None) on error
    """
    params = {
        'lat': str(lat),
        'lon': str(lon),
        'format': 'json',
        'addressdetails': 1,
        'zoom': 10  # City/town level
    }
    
    url = f"{NOMINATIM_URL}?{urllib.parse.urlencode(params)}"
    
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', USER_AGENT)
        
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read())
            
            if 'address' not in data:
                print(f"No address found for {lat}, {lon}")
                return (None, None, None)
            
            address = data['address']
            
            # Extract city (try multiple fields)
            city = (
                address.get('city') or 
                address.get('town') or 
                address.get('village') or
                address.get('hamlet') or
                address.get('municipality') or
                address.get('county')
            )
            
            # Extract state/province
            state = address.get('state') or address.get('province') or ''
            
            # Extract country
            country = address.get('country') or 'Unknown'
            
            print(f"Geocoded {lat}, {lon} -> {city}, {state}, {country}")
            return (city, state, country)
            
    except urllib.error.HTTPError as e:
        if e.code == 429:
            print(f"Rate limit hit, backing off")
            return (None, None, None)
        print(f"HTTP error geocoding {lat}, {lon}: {e}")
        return (None, None, None)
    except Exception as e:
        print(f"Error geocoding {lat}, {lon}: {e}")
        return (None, None, None)

def lambda_handler(event, context):
    """
    Main handler - finds ungeocoded coordinates and reverse geocodes them
    Respects Nominatim rate limit of 1 request per second
    """
    
    print(f"Starting geocoding run at {datetime.now().isoformat()}")
    
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get coordinates that need geocoding (limit to 50 per hour)
        cur.execute("SELECT * FROM reports.get_ungeocoded_locations(50)")
        ungeocoded = cur.fetchall()
        
        print(f"Found {len(ungeocoded)} coordinates to geocode")
        
        geocoded_count = 0
        failed_count = 0
        
        for row in ungeocoded:
            lat, lon, point_count = row
            
            # Reverse geocode
            city, state, country = reverse_geocode(float(lat), float(lon))
            
            if city:
                # Insert into lookup table
                cur.execute("""
                    CALL reports.upsert_location(%s, %s, %s, %s, %s, 5.0, 'nominatim')
                """, (lat, lon, city, state, country))
                conn.commit()
                geocoded_count += 1
                print(f"Saved: {city}, {state}, {country}")
            else:
                failed_count += 1
            
            # Respect Nominatim rate limit: 1 request per second
            # Add a bit of buffer to be safe
            time.sleep(1.2)
        
        cur.close()
        conn.close()
        
        result = {
            'success': True,
            'coordinates_found': len(ungeocoded),
            'geocoded': geocoded_count,
            'failed': failed_count,
            'timestamp': datetime.now().isoformat()
        }
        
        print(f"Geocoding complete: {json.dumps(result)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
        
    except Exception as e:
        error_msg = f"Error in geocoding lambda: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }
