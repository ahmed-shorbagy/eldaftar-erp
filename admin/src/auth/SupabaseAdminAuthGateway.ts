import type { SupabaseClient } from '@supabase/supabase-js'
import type { AdminAccess, AdminAuthGateway } from './AdminAuthGateway.ts'

export class SupabaseAdminAuthGateway implements AdminAuthGateway {
  private access: AdminAccess = 'checking'
  private readonly listeners = new Set<(status: AdminAccess) => void>()
  private revision = 0
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
    client.auth.onAuthStateChange(() => {
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
      if (session === null) {
        this.setStatus('signedOut')
        return
      }
      if (session.user.email_confirmed_at == null) {
        this.setStatus('unverified')
        return
      }
      const result = await this.client.rpc('is_platform_admin')
      if (current !== this.revision) return
      this.setStatus(result.error ? 'unavailable' : result.data === true ? 'admin' : 'denied')
    } catch {
      if (current === this.revision) this.setStatus('unavailable')
    }
  }

  async signIn(email: string, password: string): Promise<void> {
    this.setStatus('checking')
    const result = await this.client.auth.signInWithPassword({
      email: email.trim(),
      password,
    })
    if (result.error) {
      this.setStatus('signedOut')
      throw result.error
    }
    await this.refresh()
  }

  async signOut(): Promise<void> {
    const result = await this.client.auth.signOut()
    if (result.error) throw result.error
    ++this.revision
    this.setStatus('signedOut')
  }
}
