import { expect, test } from 'vitest'
import { SubscriptionCodeError } from './SubscriberDirectoryGateway.ts'
import {
  parseIntegerDays,
  parseIssuedSubscriptionCode,
  parseSubscriptionCodePage,
} from './subscriptionCodes.ts'

const issueRow = {
  code: 'ABCDEFABCDEFABCDEFABCDEFABCDEFAB',
  shop_id: 'c2100000-0000-4000-8000-000000000001',
  owner_user_id: 'c2000000-0000-4000-8000-0000000000b1',
  duration_days: 30,
  code_expires_at: '2026-11-21T00:00:00.000Z',
  status: 'issued',
  request_key: 'c2300000-0000-4000-8000-000000000011',
  issued_via: 'platform_admin',
}

const expectedIssue = {
  shopId: issueRow.shop_id,
  requestKey: issueRow.request_key,
  durationDays: 30,
}

const historyRow = {
  id: 'c2400000-0000-4000-8000-000000000001',
  issued_at: '2026-10-22T00:30:00.000Z',
  duration_days: 30,
  code_ttl_days: 14,
  code_expires_at: '2026-11-05T00:30:00.000Z',
  issued_via: 'platform_admin',
  code_status: 'unused',
  redeemed_at: null,
}

const expectedHistory = {
  shopId: 'c2100000-0000-4000-8000-000000000001',
  pageSize: 20,
  cursor: null,
}

test('integer day parser accepts inclusive bounds and rejects other text', () => {
  expect(parseIntegerDays('1', 1, 3660)).toBe(1)
  expect(parseIntegerDays('3660', 1, 3660)).toBe(3660)
  expect(parseIntegerDays('30', 1, 365)).toBe(30)
  for (const value of ['0', '3661', '30.5', '01', '٣٠', '', '1e2', '1 day', 'month']) {
    expect(() => parseIntegerDays(value, 1, 3660)).toThrow(SubscriptionCodeError)
  }
})

test('issued parser keeps the secret and drops owner identity from the domain object', () => {
  const parsed = parseIssuedSubscriptionCode([issueRow], expectedIssue)
  expect(parsed.code).toBe(issueRow.code)
  expect(parsed.status).toBe('issued')
  expect(parsed).not.toHaveProperty('owner_user_id')
  expect(parsed).not.toHaveProperty('ownerUserId')
  expect(JSON.stringify(parsed)).not.toContain(issueRow.owner_user_id)
})

test('issued parser requires exactly one row matching the original envelope', () => {
  expect(() => parseIssuedSubscriptionCode([], expectedIssue)).toThrow(SubscriptionCodeError)
  expect(() => parseIssuedSubscriptionCode([issueRow, issueRow], expectedIssue)).toThrow(SubscriptionCodeError)
  expect(() => parseIssuedSubscriptionCode([issueRow], {
    ...expectedIssue,
    shopId: 'c2100000-0000-4000-8000-000000000099',
  })).toThrow(SubscriptionCodeError)
  expect(() => parseIssuedSubscriptionCode([issueRow], {
    ...expectedIssue,
    requestKey: 'c2300000-0000-4000-8000-000000000099',
  })).toThrow(SubscriptionCodeError)
  expect(() => parseIssuedSubscriptionCode([issueRow], {
    ...expectedIssue,
    durationDays: 14,
  })).toThrow(SubscriptionCodeError)
  expect(() => parseIssuedSubscriptionCode([{ ...issueRow, issued_via: 'owner' }], expectedIssue))
    .toThrow(SubscriptionCodeError)
  expect(() => parseIssuedSubscriptionCode([{ ...issueRow, owner_user_id: 'not-a-uuid' }], expectedIssue))
    .toThrow(SubscriptionCodeError)
})

test('replayed parser requires a null code', () => {
  const parsed = parseIssuedSubscriptionCode({
    ...issueRow,
    status: 'replayed',
    code: null,
  }, expectedIssue)
  expect(parsed.status).toBe('replayed')
  expect(parsed.code).toBeNull()
  expect(() => parseIssuedSubscriptionCode({
    ...issueRow,
    status: 'replayed',
    code: issueRow.code,
  }, expectedIssue)).toThrow(SubscriptionCodeError)
})

test('strict parsers reject extra keys, lowercase secrets and numeric counts', () => {
  expect(() => parseIssuedSubscriptionCode({ ...issueRow, extra: true }, expectedIssue)).toThrow(SubscriptionCodeError)
  expect(() => parseIssuedSubscriptionCode({
    ...issueRow,
    code: issueRow.code.toLowerCase(),
  }, expectedIssue)).toThrow(SubscriptionCodeError)
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: historyRow.id,
    shop_name: 'متجر',
    row_count: 1,
    page_size: 20,
    rows: [historyRow],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: 'c2100000-0000-4000-8000-000000000001',
    shop_name: 'متجر',
    row_count: '1',
    page_size: 20,
    rows: [{ ...historyRow, owner_user_id: issueRow.owner_user_id }],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
})

test('history parser reads server status and paging', () => {
  const page = parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: 'c2100000-0000-4000-8000-000000000001',
    shop_name: 'متجر تاريخ',
    row_count: '1',
    page_size: 20,
    rows: [historyRow],
    next_cursor: null,
  }, expectedHistory)
  expect(page.rows[0]?.codeStatus).toBe('unused')
  expect(page.shopName).toBe('متجر تاريخ')
})

test('history parser matches the requested shop and does not derive status from the client clock', () => {
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: 'c2100000-0000-4000-8000-000000000099',
    shop_name: 'متجر آخر',
    row_count: '1',
    page_size: 20,
    rows: [historyRow],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  const expiredFuture = parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر تاريخ',
    row_count: '1',
    page_size: 20,
    rows: [{
      ...historyRow,
      code_status: 'expired',
      code_expires_at: '2099-01-01T00:00:00.000Z',
    }],
    next_cursor: null,
  }, expectedHistory)
  expect(expiredFuture.rows[0]?.codeStatus).toBe('expired')
})

test('history parser rejects inconsistent rows, counts, order and cursors', () => {
  const newer = {
    ...historyRow,
    id: 'c2400000-0000-4000-8000-000000000002',
    issued_at: '2026-10-23T00:30:00.000Z',
  }
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 20,
    rows: [historyRow, newer],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '1',
    page_size: 20,
    rows: [historyRow, historyRow],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '1',
    page_size: 20,
    rows: [{ ...historyRow, code_status: 'redeemed', redeemed_at: null }],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '1',
    page_size: 20,
    rows: [{ ...historyRow, code_status: 'unused', redeemed_at: '2026-10-22T08:00:00.000Z' }],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '0',
    page_size: 20,
    rows: [historyRow],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  const cursor = `v1|2026-10-22 00:30:00.000000|${historyRow.id}`
  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '1',
    page_size: 20,
    rows: [historyRow],
    next_cursor: cursor,
  }, expectedHistory)).toThrow(SubscriptionCodeError)
  const page = parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 1,
    rows: [historyRow],
    next_cursor: cursor,
  }, { ...expectedHistory, pageSize: 1 })
  expect(page.nextCursor).toBe(cursor)
})

test('history parser keeps microsecond order and offset-equivalent instants', () => {
  const newer = {
    ...historyRow,
    id: 'c2400000-0000-4000-8000-000000000001',
    issued_at: '2026-10-22T00:30:00.000002Z',
  }
  const older = {
    ...historyRow,
    id: 'c2400000-0000-4000-8000-000000000002',
    issued_at: '2026-10-22T00:30:00.000001Z',
  }
  const page = parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 20,
    rows: [newer, older],
    next_cursor: null,
  }, expectedHistory)
  expect(page.rows.map((row) => row.id)).toEqual([newer.id, older.id])

  const offsetEquivalent = {
    ...newer,
    issued_at: '2026-10-22T03:30:00.000002+03:00',
  }
  const offsetPage = parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 20,
    rows: [offsetEquivalent, older],
    next_cursor: null,
  }, expectedHistory)
  expect(offsetPage.rows[0]?.issuedAt).toBe(offsetEquivalent.issued_at)

  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 20,
    rows: [older, newer],
    next_cursor: null,
  }, expectedHistory)).toThrow(SubscriptionCodeError)

  const lastCursor = 'v1|2026-10-22 00:30:00.000001|c2400000-0000-4000-8000-000000000002'
  const paged = parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 1,
    rows: [older],
    next_cursor: lastCursor,
  }, { ...expectedHistory, pageSize: 1 })
  expect(paged.nextCursor).toBe(lastCursor)

  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 1,
    rows: [older],
    next_cursor: 'v1|2026-10-22 00:30:00.000002|c2400000-0000-4000-8000-000000000002',
  }, { ...expectedHistory, pageSize: 1 })).toThrow(SubscriptionCodeError)

  const inputCursor = 'v1|2026-10-22 00:30:00.000002|c2400000-0000-4000-8000-000000000001'
  const continued = parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 20,
    rows: [older],
    next_cursor: null,
  }, { ...expectedHistory, cursor: inputCursor })
  expect(continued.rows[0]?.id).toBe(older.id)

  expect(() => parseSubscriptionCodePage({
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: expectedHistory.shopId,
    shop_name: 'متجر',
    row_count: '2',
    page_size: 20,
    rows: [newer],
    next_cursor: null,
  }, { ...expectedHistory, cursor: inputCursor })).toThrow(SubscriptionCodeError)
})
