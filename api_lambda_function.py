import json
import psycopg2
import boto3
from datetime import date

SECRET_NAME = "aprs-db-secret"
secrets_client = boto3.client('secretsmanager')

DB_HOST = "aprs-instance-1.c2ek9ilzyxhz.us-east-1.rds.amazonaws.com"
DB_NAME = "aprs_reporter"

def get_db_connection():
    """Get database connection with credentials from Secrets Manager"""
    secret_response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
    secret_dict = json.loads(secret_response['SecretString'])
    
    return psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=secret_dict['username'],
        password=secret_dict['password'],
        sslmode='require',
        connect_timeout=10
    )

def lambda_handler(event, context):
    """
    API Gateway endpoints - all logic is in PostgreSQL functions
    """
    
    # CORS headers
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'GET, OPTIONS'
    }
    
    # Handle OPTIONS for CORS preflight
    if event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}
    
    # Get path and strip stage name if present
    raw_path = event.get('path') or event.get('resource', '')
    path = raw_path[len('/aprs_reporter'):] if raw_path.startswith('/aprs_reporter') else raw_path
    
    query_params = event.get('queryStringParameters') or {}
    
    print(f"Request: {path}, params: {query_params}")
    
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Route to appropriate database function
        if path == '/points':
            # Get points with optional date filter
            date_filter = query_params.get('date')
            if date_filter:
                cur.execute("SELECT reports.get_points_geojson('KC1KCE-8', %s)", (date_filter,))
            else:
                cur.execute("SELECT reports.get_points_geojson('KC1KCE-8', NULL)")
            body = cur.fetchone()[0]
        
        elif path == '/route':
            # Get route for specific date (default today)
            route_date = query_params.get('date', date.today().isoformat())
            cur.execute("SELECT reports.get_route_geojson(%s)", (route_date,))
            body = cur.fetchone()[0]
        
        elif path == '/routes':
            # Get all routes
            cur.execute("SELECT reports.get_all_routes_geojson()")
            body = cur.fetchone()[0]
        
        elif path == '/stats':
            # Get journey statistics
            cur.execute("SELECT reports.get_journey_stats_json()")
            body = cur.fetchone()[0]
        
        elif path == '/locations':
            # Get visited locations
            cur.execute("SELECT reports.get_locations_json()")
            body = cur.fetchone()[0]
        
        elif path.startswith('/query/'):
            # Spatial queries
            query_type = path.split('/')[-1]
            
            if query_type == 'bounding-box':
                cur.execute("SELECT reports.get_bounding_box_geojson('KC1KCE-8')")
                body = cur.fetchone()[0]
            
            elif query_type == 'convex-hull':
                cur.execute("SELECT reports.get_convex_hull_geojson('KC1KCE-8')")
                body = cur.fetchone()[0]
            
            elif query_type == 'extremes':
                cur.execute("SELECT reports.get_extreme_points_json('KC1KCE-8')")
                body = cur.fetchone()[0]
            
            else:
                body = {'error': 'Unknown query type'}
        
        else:
            body = {
                'error': 'Unknown endpoint',
                'available': [
                    '/points',
                    '/route',
                    '/routes',
                    '/stats',
                    '/locations',
                    '/query/bounding-box',
                    '/query/convex-hull',
                    '/query/extremes'
                ]
            }
        
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(body, default=str)
        }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': str(e)})
        }
