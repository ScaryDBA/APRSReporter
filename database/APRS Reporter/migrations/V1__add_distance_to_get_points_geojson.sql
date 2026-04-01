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
                        'course', course,
                        'distance', distance
                    )
                )
                ORDER BY lasttime
            )
        )
        INTO v_result
        FROM (
            SELECT
                lasttime,
                gis_point,
                speed,
                altitude,
                course,
                ROUND(COALESCE(
                    ST_Distance(
                        gis_point::geography,
                        LAG(gis_point::geography) OVER (ORDER BY lasttime)
                    ) / 1000.0,
                0)::numeric, 2) AS distance
            FROM reports.location_info
            WHERE loc_name = p_callsign
              AND DATE(lasttime) = p_date
        ) pts;
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
                        'course', course,
                        'distance', distance
                    )
                )
                ORDER BY lasttime
            )
        )
        INTO v_result
        FROM (
            SELECT
                lasttime,
                gis_point,
                speed,
                altitude,
                course,
                ROUND(COALESCE(
                    ST_Distance(
                        gis_point::geography,
                        LAG(gis_point::geography) OVER (ORDER BY lasttime)
                    ) / 1000.0,
                0)::numeric, 2) AS distance
            FROM reports.location_info
            WHERE loc_name = p_callsign
        ) pts;
    END IF;

    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;
