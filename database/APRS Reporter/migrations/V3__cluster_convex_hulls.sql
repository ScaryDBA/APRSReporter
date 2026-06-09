-- Rework get_clusters_geojson to return one convex-hull polygon per DBSCAN cluster
-- instead of individual points. Noise points (cluster id null) and single-point
-- "clusters" are excluded. Each hull Feature carries the cluster id, the member
-- point count, and the cluster centroid (center_lat/center_lon) so the front end
-- can place an identifying center marker and label.
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
    WITH clustered AS (
        SELECT
            gis_point::geometry AS geom,
            ST_ClusterDBSCAN(gis_point::geometry, eps := p_eps, minpoints := p_minpoints) OVER () AS cluster_id
        FROM reports.location_info
        WHERE loc_name = p_callsign
    ),
    grouped AS (
        SELECT
            cluster_id,
            COUNT(*) AS point_count,
            ST_ConvexHull(ST_Collect(geom)) AS hull,
            ST_Centroid(ST_Collect(geom)) AS center
        FROM clustered
        WHERE cluster_id IS NOT NULL
        GROUP BY cluster_id
        HAVING COUNT(*) > 1
    )
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(
            jsonb_build_object(
                'type', 'Feature',
                'geometry', ST_AsGeoJSON(hull)::jsonb,
                'properties', jsonb_build_object(
                    'cluster', cluster_id,
                    'point_count', point_count,
                    'center_lat', ST_Y(center),
                    'center_lon', ST_X(center)
                )
            )
            ORDER BY cluster_id
        ), '[]'::jsonb)
    )
    INTO v_result
    FROM grouped;

    RETURN COALESCE(v_result, '{"type": "FeatureCollection", "features": []}'::jsonb);
END;
$$;

COMMENT ON FUNCTION reports.get_clusters_geojson(text, double precision, integer) IS 'Returns one convex-hull polygon per DBSCAN cluster (noise and singletons excluded) with cluster id, point count, and centroid';
