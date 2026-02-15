-- Journey Detection Functions
-- Automatically detect separate trips by finding gaps where device was stationary

-- Function to detect journeys (separate trips) based on time gaps
CREATE OR REPLACE FUNCTION reports.detect_journeys(
    p_callsign text DEFAULT 'KC1KCE-8',
    p_gap_hours numeric DEFAULT 1.0
)
RETURNS TABLE (
    journey_id int,
    start_time timestamptz,
    end_time timestamptz,
    points int,
    distance_km numeric,
    max_speed_kmh numeric,
    route_line geometry
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH ordered_points AS (
        SELECT 
            location_info_id,
            lasttime,
            gis_point,
            speed,
            LAG(lasttime) OVER (ORDER BY lasttime) as prev_time
        FROM reports.location_info
        WHERE loc_name = p_callsign
        ORDER BY lasttime
    ),
    journey_breaks AS (
        SELECT 
            location_info_id,
            lasttime,
            gis_point,
            speed,
            -- Start new journey if gap > threshold or it's the first point
            SUM(CASE 
                WHEN prev_time IS NULL THEN 1
                WHEN EXTRACT(EPOCH FROM (lasttime - prev_time)) > (p_gap_hours * 3600) THEN 1
                ELSE 0
            END) OVER (ORDER BY lasttime) as journey_num
        FROM ordered_points
    ),
    journey_distances AS (
        SELECT 
            journey_num,
            lasttime,
            gis_point,
            speed,
            ST_Distance(
                gis_point::geography,
                LAG(gis_point::geography) OVER (PARTITION BY journey_num ORDER BY lasttime)
            ) as segment_distance
        FROM journey_breaks
    )
    SELECT 
        journey_num::int as journey_id,
        MIN(lasttime) as start_time,
        MAX(lasttime) as end_time,
        COUNT(*)::int as points,
        ROUND(COALESCE(SUM(segment_distance), 0)::numeric / 1000.0, 2) as distance_km,
        ROUND(MAX(speed)::numeric, 2) as max_speed_kmh,
        ST_MakeLine(gis_point::geometry ORDER BY lasttime) as route_line
    FROM journey_distances
    GROUP BY journey_num
    HAVING COUNT(*) > 1  -- Only journeys with more than 1 point
    ORDER BY start_time DESC;
END;
$$;

-- Function to get recent journeys as GeoJSON
CREATE OR REPLACE FUNCTION reports.get_recent_journeys_geojson(
    p_callsign text DEFAULT 'KC1KCE-8',
    p_limit int DEFAULT 10,
    p_gap_hours numeric DEFAULT 1.0,
    p_date date DEFAULT NULL
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
                'geometry', ST_AsGeoJSON(route_line)::jsonb,
                'properties', jsonb_build_object(
                    'journey_id', journey_id,
                    'start_time', start_time,
                    'end_time', end_time,
                    'points', points,
                    'distance_km', distance_km,
                    'max_speed_kmh', max_speed_kmh,
                    'duration_minutes', ROUND(EXTRACT(EPOCH FROM (end_time - start_time)) / 60, 1)
                )
            )
        )
    )
    INTO v_result
    FROM (
        SELECT * FROM reports.detect_journeys(p_callsign, p_gap_hours)
        WHERE p_date IS NULL OR DATE(start_time) = p_date
        ORDER BY start_time DESC
        LIMIT p_limit
    ) journeys;
    
    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;

-- Function to get a specific journey's details with all points
CREATE OR REPLACE FUNCTION reports.get_journey_details_geojson(
    p_journey_id int,
    p_callsign text DEFAULT 'KC1KCE-8',
    p_gap_hours numeric DEFAULT 1.0
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_result jsonb;
BEGIN
    WITH ordered_points AS (
        SELECT 
            location_info_id,
            lasttime,
            gis_point,
            speed,
            altitude,
            LAG(lasttime) OVER (ORDER BY lasttime) as prev_time
        FROM reports.location_info
        WHERE loc_name = p_callsign
        ORDER BY lasttime
    ),
    journey_breaks AS (
        SELECT 
            location_info_id,
            lasttime,
            gis_point,
            speed,
            altitude,
            SUM(CASE 
                WHEN prev_time IS NULL THEN 1
                WHEN EXTRACT(EPOCH FROM (lasttime - prev_time)) > (p_gap_hours * 3600) THEN 1
                ELSE 0
            END) OVER (ORDER BY lasttime) as journey_num
        FROM ordered_points
    )
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', jsonb_agg(
            jsonb_build_object(
                'type', 'Feature',
                'geometry', ST_AsGeoJSON(gis_point::geometry)::jsonb,
                'properties', jsonb_build_object(
                    'time', lasttime,
                    'speed', speed,
                    'altitude', altitude
                )
            )
            ORDER BY lasttime
        )
    )
    INTO v_result
    FROM journey_breaks
    WHERE journey_num = p_journey_id;
    
    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;

-- View for journey summary
CREATE OR REPLACE VIEW reports.journey_summary AS
SELECT 
    journey_id,
    start_time,
    end_time,
    points,
    distance_km,
    max_speed_kmh,
    ROUND(EXTRACT(EPOCH FROM (end_time - start_time)) / 60, 1) as duration_minutes,
    DATE(start_time) as journey_date
FROM reports.detect_journeys('KC1KCE-8', 1.0)
ORDER BY start_time DESC;

COMMENT ON FUNCTION reports.detect_journeys IS 'Detects separate journeys by finding time gaps where device was stationary (default 1 hour gap)';
COMMENT ON FUNCTION reports.get_recent_journeys_geojson IS 'Returns recent journeys as GeoJSON FeatureCollection with route lines';
COMMENT ON FUNCTION reports.get_journey_details_geojson IS 'Returns all points for a specific journey as GeoJSON';
COMMENT ON VIEW reports.journey_summary IS 'Summary of all detected journeys with key metrics';
