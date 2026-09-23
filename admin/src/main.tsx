import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App.tsx'
import { startSupabase } from './config/supabaseClient.ts'
import { readSupabasePublicConfig } from './config/supabasePublicConfig.ts'
import { prepareSupabase } from './config/supabaseStartup.ts'
import { ThemeController } from './theme/themeController.ts'
import { LocalStorageThemeStore } from './theme/themePreference.ts'

async function start(): Promise<void> {
  const supabaseStatus = await prepareSupabase(
    readSupabasePublicConfig(),
    startSupabase,
  )
  const themeController = new ThemeController(new LocalStorageThemeStore())
  const root = document.getElementById('root')
  if (root === null) {
    throw new Error('Root element was not found')
  }

  createRoot(root).render(
    <StrictMode>
      <App supabaseStatus={supabaseStatus} themeController={themeController} />
    </StrictMode>,
  )
}

void start()
