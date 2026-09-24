export type AdminAccess = 'checking' | 'signedOut' | 'unverified' | 'denied' | 'admin' | 'unavailable'

export interface AdminAuthGateway {
  readonly status: AdminAccess
  subscribe(listener: (status: AdminAccess) => void): () => void
  refresh(): Promise<void>
  signIn(email: string, password: string): Promise<void>
  signOut(): Promise<void>
}
