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
    
    const data = await fetchData('/points');
    if (!data || !data.features) return;
    
    const geojsonLayer = L.geoJSON(data, {
        pointToLayer: (feature, latlng) => {
            return L.circleMarker(latlng, {
                radius: 6,
                fillColor: feature.properties.speed > 10 ? '#e74c3c' : '#3498db',
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
        updateStats(data);
    }
}

// Show route view
async function showRoute() {
    clearLayers();
    currentMode = 'route';
    
    const data = await fetchData('/routes');
    if (!data || !data.features) return;
    
    const geojsonLayer = L.geoJSON(data, {
        style: {
            color: '#e74c3c',
            weight: 3,
            opacity: 0.8
        },
        onEachFeature: (feature, layer) => {
            const props = feature.properties;
            layer.bindPopup(`
                <b>Date:</b> ${props.date}<br>
                <b>Points:</b> ${props.points}<br>
                <b>Distance:</b> ${props.distance_km} km
            `);
        }
    });
    
    routeLayer.addLayer(geojsonLayer);
    routeLayer.addTo(map);
    
    if (data.features.length > 0) {
        map.fitBounds(geojsonLayer.getBounds(), { padding: [50, 50] });
    }
    
    // Also show points
    const pointsData = await fetchData('/points');
    if (pointsData) {
        const pointsGeoJson = L.geoJSON(pointsData, {
            pointToLayer: (feature, latlng) => {
                return L.circleMarker(latlng, {
                    radius: 4,
                    fillColor: '#3498db',
                    color: '#fff',
                    weight: 1,
                    opacity: 1,
                    fillOpacity: 0.6
                });
            }
        });
        routeLayer.addLayer(pointsGeoJson);
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

// Update statistics
function updateStats(data) {
    if (!data || !data.features) return;
    
    const features = data.features;
    document.getElementById('statPositions').textContent = features.length;
    
    let totalDistance = 0;
    let maxSpeed = 0;
    let lastUpdate = null;
    
    features.forEach(f => {
        const props = f.properties;
        if (props.distance) totalDistance += parseFloat(props.distance);
        if (props.speed && props.speed > maxSpeed) maxSpeed = props.speed;
        if (props.time) {
            const time = new Date(props.time);
            if (!lastUpdate || time > lastUpdate) lastUpdate = time;
        }
    });
    
    document.getElementById('statDistance').textContent = totalDistance.toFixed(2) + ' km';
    document.getElementById('statMaxSpeed').textContent = maxSpeed.toFixed(1) + ' km/h';
    document.getElementById('statLastUpdate').textContent = lastUpdate ? 
        lastUpdate.toLocaleString() : '-';
}

// Clear all layers
function clearLayers() {
    pointsLayer.clearLayers();
    routeLayer.remove();
    coverageLayer.remove();
    extremesLayer.remove();
    routeLayer = L.layerGroup();
    coverageLayer = L.layerGroup();
    extremesLayer = L.layerGroup();
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

document.getElementById('btnHeatmap').addEventListener('click', () => {
    setActiveButton('btnHeatmap');
    showCoverage();
});

document.getElementById('btnExtremes').addEventListener('click', () => {
    setActiveButton('btnExtremes');
    showExtremes();
});

document.getElementById('btnRefresh').addEventListener('click', () => {
    switch(currentMode) {
        case 'points': showPoints(); break;
        case 'route': showRoute(); break;
        case 'coverage': showCoverage(); break;
        case 'extremes': showExtremes(); break;
    }
});

// Initial load
showPoints();
