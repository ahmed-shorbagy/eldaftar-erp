import { HeadBucketCommand, S3Client } from '@aws-sdk/client-s3'
import dotenv from 'dotenv'

dotenv.config({ path: new URL('./.env.local', import.meta.url), quiet: true })

const onlySupabase = process.argv.includes('--supabase-only')
const onlyR2 = process.argv.includes('--r2-only')
if (onlySupabase && onlyR2) {
  throw new Error('Choose one check or run both without flags.')
}

function required(name) {
  const value = process.env[name]?.trim()
  if (!value) throw new Error(name + ' is missing from supabase/.env.local')
  return value
}

async function verifySupabase() {
  const rawUrl = required('SUPABASE_URL')
  const url = rawUrl.endsWith('/') ? rawUrl.slice(0, -1) : rawUrl
  const key = required('SUPABASE_PUBLISHABLE_KEY')
  const response = await fetch(url + '/auth/v1/health', {
    headers: { apikey: key },
    signal: AbortSignal.timeout(15000),
  })
  if (!response.ok) throw new Error('Supabase Auth health returned HTTP ' + response.status)
  console.log('Supabase Auth: connected')
}

async function verifyR2() {
  const client = new S3Client({
    endpoint: required('R2_ENDPOINT'),
    region: 'auto',
    credentials: {
      accessKeyId: required('R2_ACCESS_KEY_ID'),
      secretAccessKey: required('R2_SECRET_ACCESS_KEY'),
    },
  })
  try {
    await client.send(new HeadBucketCommand({ Bucket: required('R2_BUCKET') }))
    console.log('Cloudflare R2 bucket: connected')
  } finally {
    client.destroy()
  }
}

try {
  if (!onlyR2) await verifySupabase()
  if (!onlySupabase) await verifyR2()
} catch (error) {
  console.error('Connection check failed: ' + (error instanceof Error ? error.message : String(error)))
  process.exitCode = 1
}
