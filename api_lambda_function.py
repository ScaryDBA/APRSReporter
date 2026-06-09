import json
import psycopg2
import boto3
from datetime import date

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
            # Get all routes with optional date filter (max 10 journeys)
            date_filter = query_params.get('date')
            if date_filter:
                cur.execute("SELECT reports.get_all_routes_geojson(%s)", (date_filter,))
            else:
                cur.execute("SELECT reports.get_all_routes_geojson(NULL)")
            body = cur.fetchone()[0]
        
        elif path == '/journeys':
            # Get recent journeys (default 10, 1 hour gap threshold)
            limit = int(query_params.get('limit', 10))
            gap_hours = float(query_params.get('gap_hours', 1.0))
            cur.execute("SELECT reports.get_recent_journeys_geojson('KC1KCE-8', %s, %s)", (limit, gap_hours))
            body = cur.fetchone()[0]
        
        elif path.startswith('/journey/'):
            # Get specific journey details
            journey_id = int(path.split('/')[-1])
            gap_hours = float(query_params.get('gap_hours', 1.0))
            cur.execute("SELECT reports.get_journey_details_geojson(%s, 'KC1KCE-8', %s)", (journey_id, gap_hours))
            body = cur.fetchone()[0]
        
        elif path == '/stats':
            # Get journey statistics
            cur.execute("SELECT reports.get_journey_stats_json()")
            body = cur.fetchone()[0]
        
        elif path == '/locations':
            # Get visited locations
            cur.execute("SELECT reports.get_locations_json()")
            body = cur.fetchone()[0]

        elif path == '/aurora':
            # Get Aurora-specific status (versions, instance id, replica status, stat activity)
            cur.execute("SELECT reports.get_aurora_status_json()")
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

            elif query_type == 'clusters':
                cur.execute("SELECT reports.get_clusters_geojson('KC1KCE-8')")
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
                    '/journeys',
                    '/journey/{id}',
                    '/stats',
                    '/locations',
                    '/aurora',
                    '/query/bounding-box',
                    '/query/convex-hull',
                    '/query/extremes',
                    '/query/clusters'
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
            'body': json.dumps({'error': 'Internal server error'})
        }
