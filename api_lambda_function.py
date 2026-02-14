import json
import psycopg2
import os
import boto3
from datetime import datetime, date

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
    API Gateway endpoints:
    GET /points - Get all position points as GeoJSON
    GET /route - Get route track as GeoJSON LineString
    GET /stats - Get journey statistics
    GET /query/{type} - Run predefined spatial queries
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
    
    # Get path from either 'path' or 'resource' field
    # API Gateway Test uses 'resource', deployed stage uses 'path'
    raw_path = event.get('path') or event.get('resource', '')
    path = raw_path
    
    # Remove stage name if present (for deployed URLs)
    if path.startswith('/aprs_reporter'):
        path = path[len('/aprs_reporter'):]
    
    query_params = event.get('queryStringParameters') or {}
    
    # Debug: return the raw event to see what we're receiving
    print(f"Event keys: {event.keys()}, Raw path: {raw_path}, Processed path: {path}")
    
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Route: Get all points as GeoJSON
        if path == '/points':
            date_filter = query_params.get('date')
            
            if date_filter:
                # Filter by specific date
                cur.execute("""
                    SELECT jsonb_build_object(
                        'type', 'FeatureCollection',
                        'features', jsonb_agg(
                            jsonb_build_object(
                                'type', 'Feature',
                                'geometry', ST_AsGeoJSON(gis_point::geometry)::jsonb,
                                'properties', jsonb_build_object(
                                    'time', lasttime,
                                    'speed', actual_speed_kmh,
                                    'altitude', altitude,
                                    'distance', distance_from_previous
                                )
                            )
                            ORDER BY lasttime
                        )
                    )
                    FROM reports.location_info
                    WHERE loc_name = 'KC1KCE-8'
                      AND DATE(lasttime) = %s
                """, (date_filter,))
                result = cur.fetchone()
                body = result[0] if result else {'type': 'FeatureCollection', 'features': []}
            else:
                # Get all points
                cur.execute("""
                    SELECT geojson FROM reports.points_geojson
                """)
                result = cur.fetchone()
                body = result[0] if result else {'type': 'FeatureCollection', 'features': []}
        
        # Route: Get track as LineString
        elif path == '/route':
            date_filter = query_params.get('date', date.today().isoformat())
            cur.execute("""
                SELECT jsonb_build_object(
                    'type', 'FeatureCollection',
                    'features', jsonb_agg(
                        jsonb_build_object(
                            'type', 'Feature',
                            'geometry', ST_AsGeoJSON(route_line::geometry)::jsonb,
                            'properties', jsonb_build_object(
                                'date', track_date,
                                'points', point_count,
                                'distance_km', total_km
                            )
                        )
                    )
                )
                FROM reports.route_track
                WHERE track_date = %s
            """, (date_filter,))
            result = cur.fetchone()
            body = result[0] if result else {'type': 'FeatureCollection', 'features': []}
        
        # Route: Get all routes (all dates)
        elif path == '/routes':
            cur.execute("""
                SELECT jsonb_build_object(
                    'type', 'FeatureCollection',
                    'features', jsonb_agg(
                        jsonb_build_object(
                            'type', 'Feature',
                            'geometry', ST_AsGeoJSON(route_line::geometry)::jsonb,
                            'properties', jsonb_build_object(
                                'date', track_date,
                                'points', point_count,
                                'distance_km', total_km
                            )
                        )
                    )
                )
                FROM reports.route_track
            """)
            result = cur.fetchone()
            body = result[0] if result else {'type': 'FeatureCollection', 'features': []}
        
        # Route: Get journey stats
        elif path == '/stats':
            cur.execute("""
                SELECT json_agg(row_to_json(t))
                FROM (
                    SELECT 
                        journey_date,
                        total_distance_km,
                        max_speed_kmh,
                        total_moving_time,
                        unique_locations,
                        first_transmission,
                        last_transmission
                    FROM reports.journey_stats
                    ORDER BY journey_date DESC
                ) t
            """)
            result = cur.fetchone()
            body = result[0] if result else []
        
        # Route: Spatial queries
        elif path.startswith('/query/'):
            query_type = path.split('/')[-1]
            
            if query_type == 'bounding-box':
                # Get the bounding box of all positions
                cur.execute("""
                    SELECT jsonb_build_object(
                        'type', 'Feature',
                        'geometry', ST_AsGeoJSON(ST_Envelope(ST_Collect(gis_point::geometry)))::jsonb,
                        'properties', jsonb_build_object(
                            'description', 'Coverage area bounding box'
                        )
                    )
                    FROM reports.location_info
                    WHERE loc_name = 'KC1KCE-8'
                """)
                result = cur.fetchone()
                body = result[0] if result else {}
            
            elif query_type == 'convex-hull':
                # Get convex hull (coverage area)
                cur.execute("""
                    SELECT jsonb_build_object(
                        'type', 'Feature',
                        'geometry', ST_AsGeoJSON(ST_ConvexHull(ST_Collect(gis_point::geometry)))::jsonb,
                        'properties', jsonb_build_object(
                            'description', 'Coverage area (convex hull)',
                            'area_km2', ROUND((ST_Area(ST_ConvexHull(ST_Collect(gis_point::geometry))::geography) / 1000000.0)::numeric, 2)
                        )
                    )
                    FROM reports.location_info
                    WHERE loc_name = 'KC1KCE-8'
                """)
                result = cur.fetchone()
                body = result[0] if result else {}
            
            elif query_type == 'extremes':
                # Get northernmost, southernmost, easternmost, westernmost points
                cur.execute("""
                    SELECT json_build_object(
                        'northernmost', (SELECT row_to_json(t) FROM (
                            SELECT lasttime, lat, lon, ST_Y(gis_point::geometry) as latitude
                            FROM reports.location_info
                            WHERE loc_name = 'KC1KCE-8'
                            ORDER BY ST_Y(gis_point::geometry) DESC LIMIT 1
                        ) t),
                        'southernmost', (SELECT row_to_json(t) FROM (
                            SELECT lasttime, lat, lon, ST_Y(gis_point::geometry) as latitude
                            FROM reports.location_info
                            WHERE loc_name = 'KC1KCE-8'
                            ORDER BY ST_Y(gis_point::geometry) ASC LIMIT 1
                        ) t),
                        'easternmost', (SELECT row_to_json(t) FROM (
                            SELECT lasttime, lat, lon, ST_X(gis_point::geometry) as longitude
                            FROM reports.location_info
                            WHERE loc_name = 'KC1KCE-8'
                            ORDER BY ST_X(gis_point::geometry) DESC LIMIT 1
                        ) t),
                        'westernmost', (SELECT row_to_json(t) FROM (
                            SELECT lasttime, lat, lon, ST_X(gis_point::geometry) as longitude
                            FROM reports.location_info
                            WHERE loc_name = 'KC1KCE-8'
                            ORDER BY ST_X(gis_point::geometry) ASC LIMIT 1
                        ) t)
                    )
                """)
                result = cur.fetchone()
                body = result[0] if result else {}
            
            else:
                body = {'error': 'Unknown query type'}
        
        else:
            body = {'error': 'Unknown endpoint', 'available': ['/points', '/route', '/routes', '/stats', '/query/{type}']}
        
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(body, default=str)
        }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': str(e)})
        }
