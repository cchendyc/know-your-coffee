import { useEffect } from 'react'
import { MapContainer, Marker, TileLayer, Tooltip, useMap } from 'react-leaflet'
import { divIcon, latLngBounds } from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { CoffeeShop } from '../api'
import { MACHINE_LABELS } from '../labels'

const BAY_AREA_CENTER: [number, number] = [37.72, -122.25]

// Saved and been-to shops get their own marker colors (see index.css).
function markerIcon(shop: CoffeeShop) {
  const classes = ['shop-marker', shop.savedByMe && 'is-saved', shop.beenByMe && 'is-been']
    .filter(Boolean)
    .join(' ')
  return divIcon({
    className: '',
    html: `<span class="${classes}"></span>`,
    iconSize: [18, 18],
    iconAnchor: [9, 9],
  })
}

function FitToShops({ shops }: { shops: CoffeeShop[] }) {
  const map = useMap()
  useEffect(() => {
    if (shops.length === 0) return
    const bounds = latLngBounds(shops.map((s) => [s.lat, s.lng]))
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 })
  }, [map, shops])
  return null
}

export function MapView({
  shops,
  onSelect,
  showLegend,
}: {
  shops: CoffeeShop[]
  onSelect: (id: string) => void
  showLegend?: boolean
}) {
  return (
    <div className="isolate relative h-[70vh] overflow-hidden rounded-2xl border border-cream-200 shadow-sm">
      {showLegend && (
        <div className="absolute right-3 bottom-3 z-[500] flex flex-col gap-1 rounded-xl bg-white/90 px-3 py-2 text-xs shadow backdrop-blur">
          <span className="flex items-center gap-2">
            <span className="shop-marker !static" /> Shop
          </span>
          <span className="flex items-center gap-2">
            <span className="shop-marker is-saved !static" /> Saved
          </span>
          <span className="flex items-center gap-2">
            <span className="shop-marker is-been !static" /> Been
          </span>
        </div>
      )}
      <MapContainer center={BAY_AREA_CENTER} zoom={10} className="h-full w-full">
        <TileLayer
          attribution="Tiles &copy; Esri &mdash; Esri, HERE, Garmin, OpenStreetMap contributors"
          url="https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}"
          maxNativeZoom={16}
          maxZoom={18}
        />
        <FitToShops shops={shops} />
        {shops.map((shop) => (
          <Marker
            key={`${shop.id}-${shop.savedByMe}-${shop.beenByMe}`}
            position={[shop.lat, shop.lng]}
            icon={markerIcon(shop)}
            eventHandlers={{ click: () => onSelect(shop.id) }}
          >
            <Tooltip direction="top" offset={[0, -8]}>
              <span className="font-semibold">{shop.name}</span>
              {shop.machine !== 'UNKNOWN' && <span> · {MACHINE_LABELS[shop.machine]}</span>}
              {shop.savedByMe && <span> · saved</span>}
              {shop.beenByMe && <span> · been</span>}
            </Tooltip>
          </Marker>
        ))}
      </MapContainer>
    </div>
  )
}
