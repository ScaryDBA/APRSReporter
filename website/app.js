// Configuration - UPDATE THIS with your API Gateway URL after deployment
const API_BASE_URL = 'https://zcftrap1y3.execute-api.us-east-1.amazonaws.com/aprs_reporter';

// Initialize map
const map = L.map('map').setView([42.3601, -71.0589], 10); // Default to Boston area

// Add OpenStreetMap tiles
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors',
    maxZoom: 19
}).addTo(map);

// Layer groups
let pointsLayer = L.layerGroup().addTo(map);
let routeLayer = L.layerGroup();
let coverageLayer = L.layerGroup();
let extremesLayer = L.layerGroup();
let clustersLayer = L.layerGroup();

// Current view mode
let currentMode = 'points';

// Fetch and display data
async function fetchData(endpoint) {
    try {
        const response = await fetch(`${API_BASE_URL}${endpoint}`);
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        return await response.json();
    } catch (error) {
        console.error('Error fetching data:', error);
        alert('Error loading data. Make sure to update API_BASE_URL in app.js');
        return null;
    }
}

// Show points view
async function showPoints() {
    clearLayers();
    currentMode = 'points';
    
    // Get date filter value
    const dateFilter = document.getElementById('dateFilter').value;
    const endpoint = dateFilter ? `/points?date=${dateFilter}` : '/points';
    
    const data = await fetchData(endpoint);
    if (!data || !data.features) return;
    
    const geojsonLayer = L.geoJSON(data, {
        pointToLayer: (feature, latlng) => {
            const speed = feature.properties.speed || 0;
            let fillColor;
            if (speed <= 5) {
                fillColor = '#3498db'; // Blue - stationary/very slow
            } else if (speed <= 20) {
                fillColor = '#f39c12'; // Orange - slow moving
            } else {
                fillColor = '#e74c3c'; // Red - fast moving
            }
            
            return L.circleMarker(latlng, {
                radius: 6,
                fillColor: fillColor,
                color: '#fff',
                weight: 1,
                opacity: 1,
                fillOpacity: 0.8
            });
        },
        onEachFeature: (feature, layer) => {
            const props = feature.properties;
            const time = new Date(props.time).toLocaleString();
            layer.bindPopup(`
                <b>Time:</b> ${time}<br>
                <b>Speed:</b> ${props.speed || 0} km/h<br>
                <b>Altitude:</b> ${props.altitude || 0} m<br>
                <b>Distance from prev:</b> ${props.distance || 0} km
            `);
        }
    });
    
    pointsLayer.addLayer(geojsonLayer);
    pointsLayer.addTo(map);
    
    if (data.features.length > 0) {
        map.fitBounds(geojsonLayer.getBounds(), { padding: [50, 50] });
    }
}

// Show route view
// Show route view - displays detected journeys
async function showRoute() {
    clearLayers();
    currentMode = 'route';
    
    // Get date filter value
    const dateFilter = document.getElementById('dateFilter').value;
    const endpoint = dateFilter ? `/routes?date=${dateFilter}` : '/routes';
    
    const data = await fetchData(endpoint);
    if (!data || !data.features) return;
    
    const colors = ['#e74c3c', '#3498db', '#2ecc71', '#f39c12', '#9b59b6'];
    
    const geojsonLayer = L.geoJSON(data, {
        style: (feature) => {
            const colorIndex = feature.properties.journey_id % colors.length;
            return {
                color: colors[colorIndex],
                weight: 3,
                opacity: 0.8
            };
        },
        onEachFeature: (feature, layer) => {
            const props = feature.properties;
            const startTime = new Date(props.start_time).toLocaleString();
            const endTime = new Date(props.end_time).toLocaleString();
            
            layer.bindPopup(`
                <b>Journey #${props.journey_id}</b><br>
                <b>Start:</b> ${startTime}<br>
                <b>End:</b> ${endTime}<br>
                <b>Duration:</b> ${props.duration_minutes} minutes<br>
                <b>Points:</b> ${props.points}<br>
                <b>Distance:</b> ${props.distance_km} km<br>
                <b>Max Speed:</b> ${props.max_speed_kmh} km/h
            `);
        }
    });
    
    routeLayer.addLayer(geojsonLayer);
    routeLayer.addTo(map);
    
    if (data.features.length > 0) {
        map.fitBounds(geojsonLayer.getBounds(), { padding: [50, 50] });
        
        // Show journey count in console
        console.log(`Displaying ${data.features.length} recent journeys`);
    }
}


// Show coverage area (convex hull)
async function showCoverage() {
    clearLayers();
    currentMode = 'coverage';
    
    const data = await fetchData('/query/convex-hull');
    if (!data || !data.geometry) return;
    
    const geojsonLayer = L.geoJSON(data, {
        style: {
            color: '#9b59b6',
            weight: 2,
            fillOpacity: 0.2
        },
        onEachFeature: (feature, layer) => {
            const props = feature.properties;
            layer.bindPopup(`
                <b>${props.description}</b><br>
                <b>Area:</b> ${props.area_km2} km²
            `);
        }
    });
    
    coverageLayer.addLayer(geojsonLayer);
    coverageLayer.addTo(map);
    map.fitBounds(geojsonLayer.getBounds(), { padding: [50, 50] });
    
    // Also show points
    const pointsData = await fetchData('/points');
    if (pointsData) {
        const pointsGeoJson = L.geoJSON(pointsData, {
            pointToLayer: (feature, latlng) => {
                return L.circleMarker(latlng, {
                    radius: 3,
                    fillColor: '#3498db',
                    color: '#fff',
                    weight: 1,
                    opacity: 1,
                    fillOpacity: 0.5
                });
            }
        });
        coverageLayer.addLayer(pointsGeoJson);
    }
}

// Show extreme points
async function showExtremes() {
    clearLayers();
    currentMode = 'extremes';
    
    const data = await fetchData('/query/extremes');
    if (!data) return;
    
    const extremePoints = [
        { name: 'Northernmost', data: data.northernmost, color: '#e74c3c' },
        { name: 'Southernmost', data: data.southernmost, color: '#3498db' },
        { name: 'Easternmost', data: data.easternmost, color: '#2ecc71' },
        { name: 'Westernmost', data: data.westernmost, color: '#f39c12' }
    ];
    
    extremePoints.forEach(point => {
        if (point.data) {
            const marker = L.circleMarker([point.data.lat, point.data.lon], {
                radius: 10,
                fillColor: point.color,
                color: '#fff',
                weight: 2,
                opacity: 1,
                fillOpacity: 0.8
            });
            
            marker.bindPopup(`
                <b>${point.name}</b><br>
                <b>Time:</b> ${new Date(point.data.lasttime).toLocaleString()}<br>
                <b>Location:</b> ${point.data.lat}, ${point.data.lon}
            `);
            
            extremesLayer.addLayer(marker);
        }
    });
    
    extremesLayer.addTo(map);
    
    // Also show all points
    const pointsData = await fetchData('/points');
    if (pointsData) {
        const pointsGeoJson = L.geoJSON(pointsData, {
            pointToLayer: (feature, latlng) => {
                return L.circleMarker(latlng, {
                    radius: 3,
                    fillColor: '#95a5a6',
                    color: '#fff',
                    weight: 1,
                    opacity: 1,
                    fillOpacity: 0.3
                });
            }
        });
        extremesLayer.addLayer(pointsGeoJson);
        map.fitBounds(pointsGeoJson.getBounds(), { padding: [50, 50] });
    }
}

// Show clusters as convex-hull polygons (PostGIS ST_ClusterDBSCAN + ST_ConvexHull)
async function showClusters() {
    clearLayers();
    currentMode = 'clusters';

    const data = await fetchData('/query/clusters');
    if (!data || !data.features) return;

    // Distinct color per cluster id
    const palette = ['#e74c3c', '#3498db', '#2ecc71', '#f39c12', '#9b59b6', '#1abc9c', '#e67e22', '#34495e'];
    const colorFor = (cluster) => palette[cluster % palette.length];

    data.features.forEach(feature => {
        const props = feature.properties;
        const color = colorFor(props.cluster);

        // Semi-transparent shaded convex hull around the group
        const hull = L.geoJSON(feature, {
            style: {
                color: color,
                weight: 2,
                opacity: 0.9,
                fillColor: color,
                fillOpacity: 0.25
            }
        });
        hull.bindPopup(`
            <b>Cluster #${props.cluster}</b><br>
            <b>Points:</b> ${props.point_count}
        `);
        clustersLayer.addLayer(hull);

        // Identifying center point with a permanent label on the hull
        if (props.center_lat != null && props.center_lon != null) {
            const center = [props.center_lat, props.center_lon];
            const centerMarker = L.circleMarker(center, {
                radius: 5,
                fillColor: color,
                color: '#fff',
                weight: 2,
                opacity: 1,
                fillOpacity: 1
            });
            centerMarker.bindTooltip(`${props.cluster}`, {
                permanent: true,
                direction: 'center',
                className: 'cluster-label'
            });
            clustersLayer.addLayer(centerMarker);
        }
    });

    clustersLayer.addTo(map);

    if (data.features.length > 0) {
        const allBounds = L.geoJSON(data).getBounds();
        if (allBounds.isValid()) map.fitBounds(allBounds, { padding: [50, 50] });
    }
}

// Load statistics from the /stats endpoint (per-journey aggregates)
async function loadStats() {
    const data = await fetchData('/stats');
    if (!Array.isArray(data) || data.length === 0) return;

    let totalDistance = 0;
    let maxSpeed = 0;
    let totalLocations = 0;
    let lastUpdate = null;

    data.forEach(row => {
        if (row.total_distance_km) totalDistance += parseFloat(row.total_distance_km);
        if (row.max_speed_kmh && parseFloat(row.max_speed_kmh) > maxSpeed) {
            maxSpeed = parseFloat(row.max_speed_kmh);
        }
        if (row.unique_locations) totalLocations += parseInt(row.unique_locations, 10);
        if (row.last_transmission) {
            const time = new Date(row.last_transmission);
            if (!lastUpdate || time > lastUpdate) lastUpdate = time;
        }
    });

    document.getElementById('statJourneys').textContent = data.length;
    document.getElementById('statDistance').textContent = totalDistance.toFixed(2) + ' km';
    document.getElementById('statMaxSpeed').textContent = maxSpeed.toFixed(1) + ' km/h';
    document.getElementById('statLocations').textContent = totalLocations;
    document.getElementById('statLastUpdate').textContent = lastUpdate ?
        lastUpdate.toLocaleString() : '-';
}

// Clear all layers
function clearLayers() {
    pointsLayer.clearLayers();
    routeLayer.remove();
    coverageLayer.remove();
    extremesLayer.remove();
    clustersLayer.remove();
    routeLayer = L.layerGroup();
    coverageLayer = L.layerGroup();
    extremesLayer = L.layerGroup();
    clustersLayer = L.layerGroup();
}

// Set active button
function setActiveButton(buttonId) {
    document.querySelectorAll('.controls button').forEach(btn => {
        btn.classList.remove('active');
    });
    document.getElementById(buttonId).classList.add('active');
}

// Event listeners
document.getElementById('btnPoints').addEventListener('click', () => {
    setActiveButton('btnPoints');
    showPoints();
});

document.getElementById('btnRoute').addEventListener('click', () => {
    setActiveButton('btnRoute');
    showRoute();
});

document.getElementById('btnCoverage').addEventListener('click', () => {
    setActiveButton('btnCoverage');
    showCoverage();
});

document.getElementById('btnExtremes').addEventListener('click', () => {
    setActiveButton('btnExtremes');
    showExtremes();
});

document.getElementById('btnClusters').addEventListener('click', () => {
    setActiveButton('btnClusters');
    showClusters();
});

document.getElementById('btnRefresh').addEventListener('click', () => {
    switch(currentMode) {
        case 'points': showPoints(); break;
        case 'route': showRoute(); break;
        case 'coverage': showCoverage(); break;
        case 'extremes': showExtremes(); break;
        case 'clusters': showClusters(); break;
    }
    loadStats();
});
// Date filter change handler
document.getElementById('dateFilter').addEventListener('change', () => {
    if (currentMode === 'points') {
        showPoints();
    } else if (currentMode === 'route') {
        showRoute();
    }
});

// Clear date filter
document.getElementById('btnClearFilter').addEventListener('click', () => {
    document.getElementById('dateFilter').value = '';
    if (currentMode === 'points') {
        showPoints();
    } else if (currentMode === 'route') {
        showRoute();
    }
});

// Locations expandable section
document.getElementById('locationsHeader').addEventListener('click', () => {
    const content = document.getElementById('locationsContent');
    const toggle = document.getElementById('locationsToggle');
    
    content.classList.toggle('expanded');
    toggle.classList.toggle('expanded');
    
    // Load locations if not already loaded
    if (content.classList.contains('expanded') && !content.dataset.loaded) {
        loadLocations();
    }
});

// Load locations data
async function loadLocations() {
    const content = document.getElementById('locationsContent');
    const grid = document.getElementById('locationsGrid');
    
    const data = await fetchData('/locations');
    if (!data || !data.length) {
        grid.innerHTML = '<div style="text-align: center; padding: 2rem; color: #7f8c8d;">No location data available</div>';
        return;
    }
    
    grid.innerHTML = '';
    data.forEach(loc => {
        const item = document.createElement('div');
        item.className = 'location-item';
        
        const cityDiv = document.createElement('div');
        cityDiv.className = 'city';
        cityDiv.textContent = loc.city || 'Unknown City';
        
        const regionDiv = document.createElement('div');
        regionDiv.className = 'region';
        regionDiv.textContent = [loc.state, loc.country].filter(Boolean).join(', ') || 'Unknown Region';
        
        // Add visit count if available
        if (loc.visit_count) {
            const countDiv = document.createElement('div');
            countDiv.className = 'visit-count';
            countDiv.textContent = `${loc.visit_count} point${loc.visit_count !== 1 ? 's' : ''}`;
            item.appendChild(countDiv);
        }
        
        item.appendChild(cityDiv);
        item.appendChild(regionDiv);
        grid.appendChild(item);
    });
    
    content.dataset.loaded = 'true';
}

// Initial load
showPoints();
loadStats();
