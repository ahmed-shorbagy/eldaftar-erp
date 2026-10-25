export type SubscriberContactRow = {
  shopId: string
  phone: string
  countryCode: string
  locationDisplayAr: string | null
}

export type SubscriberContactGateway = {
  reveal(shopId: string): Promise<SubscriberContactRow>
}

export class SubscriberContactError extends Error {
  readonly code: 'unauthorized' | 'forbidden' | 'not_found' | 'invalid' | 'unavailable'

  constructor(code: 'unauthorized' | 'forbidden' | 'not_found' | 'invalid' | 'unavailable') {
    super(code)
    this.code = code
  }
}

export function parseSubscriberContact(value: unknown): SubscriberContactRow {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new SubscriberContactError('invalid')
  }
  const row = value as Record<string, unknown>
  if (typeof row.shop_id !== 'string' || typeof row.phone !== 'string') {
    throw new SubscriberContactError('invalid')
  }
  if (typeof row.country_code !== 'string') throw new SubscriberContactError('invalid')
  const location = row.location_display_ar
  if (location !== null && typeof location !== 'string') {
    throw new SubscriberContactError('invalid')
  }
  return {
    shopId: row.shop_id,
    phone: row.phone,
    countryCode: row.country_code,
    locationDisplayAr: location,
  }
}
