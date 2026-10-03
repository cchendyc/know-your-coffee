import { useEffect, useRef, useState } from 'react'
import { PHOTO_KIND_LABELS } from '../labels'
import { SectionHeader } from './bits'
import { plural } from './util'
import { useShopPhotos } from './shopData'

// Photos are base64 blobs, so they load only once this section is within
// 600px of the viewport.
export function PhotosSection({ shopId, photoCount, version }: { shopId: string; photoCount: number; version: number }) {
  const ref = useRef<HTMLDivElement>(null)
  const [near, setNear] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          setNear(true)
          observer.disconnect()
        }
      },
      { rootMargin: '600px 0px' },
    )
    observer.observe(el)
    return () => observer.disconnect()
  }, [])
  const photos = useShopPhotos(shopId, near, version)

  return (
    <div ref={ref} className="flex flex-col gap-4">
      <SectionHeader title="Photos" subtitle={`${plural(photoCount, 'photo')} from the community`} />
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {photos
          ? photos.map((p) => (
              <figure key={p.id}>
                <img src={p.data} alt={PHOTO_KIND_LABELS[p.kind]} className="h-[160px] w-full rounded-xl object-cover" />
                <figcaption className="mt-1 text-[11px] text-espresso-500">
                  {PHOTO_KIND_LABELS[p.kind]} · {p.uploader ? p.uploader.name : 'Anonymous'}
                </figcaption>
              </figure>
            ))
          : Array.from({ length: Math.min(photoCount, 4) }, (_, i) => <div key={i} className="sp-skeleton h-[160px]" />)}
      </div>
    </div>
  )
}
