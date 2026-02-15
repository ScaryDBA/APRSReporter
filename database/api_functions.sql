-- API Functions for APRS Reporter
-- These functions encapsulate all the SQL logic used by the API Lambda

-- Function: Get all points as GeoJSON (with optional date filter)
CREATE OR REPLACE FUNCTION reports.get_points_geojson(
    p_callsign text DEFAULT 'KC1KCE-8',
    p_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_result jsonb;
BEGIN
    IF p_date IS NOT NULL THEN
        -- Filter by specific date
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', jsonb_agg(
                jsonb_build_object(
                    'type', 'Feature',
                    'geometry', ST_AsGeoJSON(gis_point::geometry)::jsonb,
                    'properties', jsonb_build_object(
                        'time', lasttime,
                        'speed', speed,
                        'altitude', altitude,
                        'course', course
                    )
                )
                ORDER BY lasttime
            )
        )
        INTO v_result
        FROM reports.location_info
        WHERE loc_name = p_callsign
          AND DATE(lasttime) = p_date;
    ELSE
        -- Get all points
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', jsonb_agg(
                jsonb_build_object(
                    'type', 'Feature',
                    'geometry', ST_AsGeoJSON(gis_point::geometry)::jsonb,
                    'properties', jsonb_build_object(
                        'time', lasttime,
                        'speed', speed,
                        'altitude', altitude,
                        'course', course
                    )
                )
                ORDER BY lasttime
            )
        )
        INTO v_result
        FROM reports.location_info
        WHERE loc_name = p_callsign;
    END IF;
    
    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;

-- Function: Get route track as LineString for a specific date
CREATE OR REPLACE FUNCTION reports.get_route_geojson(
    p_date date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_result jsonb;
BEGIN
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
    INTO v_result
    FROM reports.route_track
    WHERE track_date = p_date;
    
    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;

-- Function: Get all routes (all dates)
CREATE OR REPLACE FUNCTION reports.get_all_routes_geojson()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_result jsonb;
BEGIN
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
    INTO v_result
    FROM reports.route_track;
    
    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;

-- Function: Get journey statistics
CREATE OR REPLACE FUNCTION reports.get_journey_stats_json()
RETURNS json
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        json_agg(row_to_json(t) ORDER BY journey_date DESC),
        '[]'::json
    )
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
    ) t;
$$;

-- Function: Get locations visited with visit counts
CREATE OR REPLACE FUNCTION reports.get_locations_json()
RETURNS json
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        json_agg(row_to_json(t) ORDER BY visit_count DESC, city),
        '[]'::json
    )
    FROM (
        SELECT 
            city,
            state,
            country,
            visit_count,
            first_visit,
            last_visit
        FROM reports.locations_visited
        ORDER BY visit_count DESC, city
    ) t;
$$;

-- Function: Get bounding box of all positions
CREATE OR REPLACE FUNCTION reports.get_bounding_box_geojson(
    p_callsign text DEFAULT 'KC1KCE-8'
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'type', 'Feature',
        'geometry', ST_AsGeoJSON(ST_Envelope(ST_Collect(gis_point::geometry)))::jsonb,
        'properties', jsonb_build_object(
            'description', 'Coverage area bounding box'
        )
    )
    INTO v_result
    FROM reports.location_info
    WHERE loc_name = p_callsign;
    
    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

-- Function: Get convex hull (coverage area)
CREATE OR REPLACE FUNCTION reports.get_convex_hull_geojson(
    p_callsign text DEFAULT 'KC1KCE-8'
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'type', 'Feature',
        'geometry', ST_AsGeoJSON(ST_ConvexHull(ST_Collect(gis_point::geometry)))::jsonb,
        'properties', jsonb_build_object(
            'description', 'Coverage area (convex hull)',
            'area_km2', ROUND((ST_Area(ST_ConvexHull(ST_Collect(gis_point::geometry))::geography) / 1000000.0)::numeric, 2)
        )
    )
    INTO v_result
    FROM reports.location_info
    WHERE loc_name = p_callsign;
    
    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

-- Function: Get extreme points (north, south, east, west)
CREATE OR REPLACE FUNCTION reports.get_extreme_points_json(
    p_callsign text DEFAULT 'KC1KCE-8'
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    v_result json;
BEGIN
    SELECT json_build_object(
        'northernmost', (SELECT row_to_json(t) FROM (
            SELECT lasttime, lat, lon, ST_Y(gis_point::geometry) as latitude
            FROM reports.location_info
            WHERE loc_name = p_callsign
            ORDER BY ST_Y(gis_point::geometry) DESC LIMIT 1
        ) t),
        'southernmost', (SELECT row_to_json(t) FROM (
            SELECT lasttime, lat, lon, ST_Y(gis_point::geometry) as latitude
            FROM reports.location_info
            WHERE loc_name = p_callsign
            ORDER BY ST_Y(gis_point::geometry) ASC LIMIT 1
        ) t),
        'easternmost', (SELECT row_to_json(t) FROM (
            SELECT lasttime, lat, lon, ST_X(gis_point::geometry) as longitude
            FROM reports.location_info
            WHERE loc_name = p_callsign
            ORDER BY ST_X(gis_point::geometry) DESC LIMIT 1
        ) t),
        'westernmost', (SELECT row_to_json(t) FROM (
            SELECT lasttime, lat, lon, ST_X(gis_point::geometry) as longitude
            FROM reports.location_info
            WHERE loc_name = p_callsign
            ORDER BY ST_X(gis_point::geometry) ASC LIMIT 1
        ) t)
    )
    INTO v_result;
    
    RETURN COALESCE(v_result, '{}'::json);
END;
$$;

-- Add comments for documentation
COMMENT ON FUNCTION reports.get_points_geojson IS 'Returns all position points as GeoJSON FeatureCollection, optionally filtered by date';
COMMENT ON FUNCTION reports.get_route_geojson IS 'Returns route track as GeoJSON LineString for a specific date';
COMMENT ON FUNCTION reports.get_all_routes_geojson IS 'Returns all route tracks as GeoJSON FeatureCollection';
COMMENT ON FUNCTION reports.get_journey_stats_json IS 'Returns journey statistics as JSON array';
COMMENT ON FUNCTION reports.get_locations_json IS 'Returns visited locations with visit counts as JSON array';
COMMENT ON FUNCTION reports.get_bounding_box_geojson IS 'Returns bounding box of all positions as GeoJSON';
COMMENT ON FUNCTION reports.get_convex_hull_geojson IS 'Returns convex hull (coverage area) as GeoJSON';
COMMENT ON FUNCTION reports.get_extreme_points_json IS 'Returns extreme points (northernmost, southernmost, easternmost, westernmost) as JSON';
