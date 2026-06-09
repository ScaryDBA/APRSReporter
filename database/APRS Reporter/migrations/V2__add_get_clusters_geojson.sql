-- Groups position points into spatial clusters using ST_ClusterDBSCAN.
-- Each returned point Feature carries a 'cluster' property (integer cluster id,
-- or null for noise points that do not belong to any cluster).
-- p_eps is the neighbourhood radius in degrees (~0.01 deg ≈ 1.1 km at mid latitudes);
-- p_minpoints is the minimum number of points required to form a cluster.
CREATE OR REPLACE FUNCTION reports.get_clusters_geojson(
    p_callsign text DEFAULT 'KC1KCE-8',
    p_eps double precision DEFAULT 0.01,
    p_minpoints integer DEFAULT 5
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(
            jsonb_build_object(
                'type', 'Feature',
                'geometry', ST_AsGeoJSON(gis_point::geometry)::jsonb,
                'properties', jsonb_build_object(
                    'cluster', cluster_id,
                    'time', lasttime,
                    'speed', speed
                )
            )
            ORDER BY lasttime
        ), '[]'::jsonb)
    )
    INTO v_result
    FROM (
        SELECT
            lasttime,
            gis_point,
            speed,
            ST_ClusterDBSCAN(gis_point::geometry, eps := p_eps, minpoints := p_minpoints) OVER () AS cluster_id
        FROM reports.location_info
        WHERE loc_name = p_callsign
    ) clustered;

    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;

COMMENT ON FUNCTION reports.get_clusters_geojson(text, double precision, integer) IS 'Returns position points as a GeoJSON FeatureCollection with a DBSCAN cluster id on each point';
