import type { SupabaseClient } from '@supabase/supabase-js'
import type { AdminAccess, AdminAuthGateway } from './AdminAuthGateway.ts'

function accessTokenExpired(session: { expires_at?: number | null }): boolean {
  return typeof session.expires_at !== 'number' || session.expires_at * 1000 <= Date.now()
}

function userIdOf(session: { user?: { id?: string | null } | null } | null): string | null {
  const userId = session?.user?.id
  return typeof userId === 'string' && userId.length > 0 ? userId : null
}

export class SupabaseAdminAuthGateway implements AdminAuthGateway {
  private access: AdminAccess = 'checking'
  private readonly listeners = new Set<(status: AdminAccess) => void>()
  private revision = 0
  private sessionUserId: string | null = null
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
    client.auth.onAuthStateChange((event, session) => {
      const nextUserId = userIdOf(session)
      const signedOut = event === 'SIGNED_OUT' || session === null
      const identityChanged = nextUserId !== null
        && this.sessionUserId !== null
        && nextUserId !== this.sessionUserId
      if (signedOut || identityChanged) {
        this.revision += 1
        this.sessionUserId = signedOut ? null : nextUserId
        this.setStatus(signedOut ? 'signedOut' : 'checking')
        if (identityChanged && !signedOut) {
          setTimeout(() => {
            void this.refresh()
          }, 0)
        }
        return
      }
      setTimeout(() => {
        void this.refresh()
      }, 0)
    })
  }

  get status(): AdminAccess {
    return this.access
  }

  subscribe(listener: (status: AdminAccess) => void): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  private setStatus(next: AdminAccess): void {
    this.access = next
    for (const listener of this.listeners) listener(next)
  }

  async refresh(): Promise<void> {
    const current = ++this.revision
    try {
      const { data, error } = await this.client.auth.getSession()
      if (current !== this.revision) return
      if (error) {
        this.setStatus('unavailable')
        return
      }
      const session = data.session
      if (session === null || accessTokenExpired(session)) {
        this.sessionUserId = null
        this.setStatus('signedOut')
        return
      }
      const userId = userIdOf(session)
      if (userId !== null) this.sessionUserId = userId
      const result = await this.client.rpc('is_platform_admin')
      if (current !== this.revision) return
      this.setStatus(result.error ? 'unavailable' : result.data === true ? 'admin' : 'denied')
    } catch {
      if (current === this.revision) this.setStatus('unavailable')
    }
  }

  async signIn(email: string, password: string): Promise<void> {
    this.setStatus('checking')
    try {
      const result = await this.client.auth.signInWithPassword({
        email: email.trim(),
        password,
      })
      if (result.error) throw result.error
    } catch (error) {
      this.setStatus('signedOut')
      throw error
    }
    await this.refresh()
  }

  async signOut(): Promise<void> {
    this.revision += 1
    this.sessionUserId = null
    this.setStatus('signedOut')
    try {
      const result = await this.client.auth.signOut()
      if (result.error) throw result.error
    } catch (error) {
      await this.refresh()
      throw error
    }
    this.revision += 1
    this.sessionUserId = null
    this.setStatus('signedOut')
  }
}
