-- Location lookup table for reverse geocoding cache
-- Groups nearby coordinates into regions with city/state/country

CREATE TABLE IF NOT EXISTS reports.location_lookup (
    location_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    center_point geography(Point, 4326) NOT NULL,
    lat numeric(9,5) NOT NULL,
    lon numeric(10,5) NOT NULL,
    city text,
    state text,
    country text NOT NULL DEFAULT 'USA',
    radius_km numeric(6,2) DEFAULT 5.0,
    point_count int DEFAULT 0,
    first_seen timestamptz DEFAULT NOW(),
    last_geocoded timestamptz,
    geocode_source text DEFAULT 'manual',
    CONSTRAINT unique_location UNIQUE (lat, lon)
);

CREATE INDEX idx_location_lookup_point ON reports.location_lookup USING GIST(center_point);

-- Function to find the nearest location cluster for a given point
CREATE OR REPLACE FUNCTION reports.find_nearest_location(
    p_lat numeric,
    p_lon numeric,
    p_radius_km numeric DEFAULT 5.0
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_location_id bigint;
    v_point geography;
BEGIN
    v_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326);
    
    -- Find the nearest location within radius
    SELECT location_id INTO v_location_id
    FROM reports.location_lookup
    WHERE ST_DWithin(center_point, v_point, p_radius_km * 1000)
    ORDER BY ST_Distance(center_point, v_point)
    LIMIT 1;
    
    RETURN v_location_id;
END;
$$;

-- Procedure to get coordinates that need geocoding
CREATE OR REPLACE FUNCTION reports.get_ungeocoded_locations(p_limit int DEFAULT 50)
RETURNS TABLE (
    lat numeric,
    lon numeric,
    point_count bigint
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH distinct_coords AS (
        SELECT 
            li.lat,
            li.lon,
            COUNT(*) as point_count
        FROM reports.location_info li
        WHERE li.loc_name = 'KC1KCE-8'
        GROUP BY li.lat, li.lon
    )
    SELECT 
        dc.lat,
        dc.lon,
        dc.point_count
    FROM distinct_coords dc
    WHERE NOT EXISTS (
        SELECT 1 
        FROM reports.location_lookup ll
        WHERE ST_DWithin(
            ll.center_point,
            ST_SetSRID(ST_MakePoint(dc.lon, dc.lat), 4326),
            ll.radius_km * 1000
        )
    )
    ORDER BY dc.point_count DESC
    LIMIT p_limit;
END;
$$;

-- Procedure to add or update a geocoded location
CREATE OR REPLACE PROCEDURE reports.upsert_location(
    p_lat numeric,
    p_lon numeric,
    p_city text,
    p_state text,
    p_country text DEFAULT 'USA',
    p_radius_km numeric DEFAULT 5.0,
    p_source text DEFAULT 'nominatim'
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO reports.location_lookup (
        center_point,
        lat,
        lon,
        city,
        state,
        country,
        radius_km,
        last_geocoded,
        geocode_source
    )
    VALUES (
        ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326),
        p_lat,
        p_lon,
        p_city,
        p_state,
        p_country,
        p_radius_km,
        NOW(),
        p_source
    )
    ON CONFLICT (lat, lon) DO UPDATE
    SET 
        city = EXCLUDED.city,
        state = EXCLUDED.state,
        country = EXCLUDED.country,
        last_geocoded = NOW(),
        geocode_source = EXCLUDED.geocode_source;
END;
$$;

-- View for locations with geocoding
CREATE OR REPLACE VIEW reports.locations_visited AS
SELECT DISTINCT
    ll.city,
    ll.state,
    ll.country,
    COUNT(DISTINCT li.location_info_id) as visit_count,
    MIN(li.lasttime) as first_visit,
    MAX(li.lasttime) as last_visit
FROM reports.location_info li
LEFT JOIN reports.location_lookup ll ON 
    ST_DWithin(
        ll.center_point,
        li.gis_point,
        ll.radius_km * 1000
    )
WHERE li.loc_name = 'KC1KCE-8'
  AND ll.city IS NOT NULL
GROUP BY ll.city, ll.state, ll.country
ORDER BY visit_count DESC, ll.city;

COMMENT ON TABLE reports.location_lookup IS 'Cache of reverse geocoded locations for coordinate clustering';
COMMENT ON COLUMN reports.location_lookup.radius_km IS 'Radius in km to cluster nearby points into this location';
COMMENT ON FUNCTION reports.get_ungeocoded_locations IS 'Returns coordinates that need reverse geocoding';
COMMENT ON PROCEDURE reports.upsert_location IS 'Insert or update a geocoded location';
