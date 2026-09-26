import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  type AdminAuthClient,
  type BoundaryError,
  createAuthAdminPort,
  createPasswordProofPort,
  createSqlPort,
  type PasswordAuthClient,
  type RpcClient,
} from "./boundary.ts";
import {
  handleOwnerRegister,
  loadCallerKeys,
  resolveServerCredentials,
} from "./http.ts";

const requestTimeoutMs = 15_000;

function fetchWithTimeout(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const signal = init?.signal ?? AbortSignal.timeout(requestTimeoutMs);
  return fetch(input, { ...init, signal });
}

function clientOptions() {
  return {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: fetchWithTimeout },
  };
}

// verify_jwt must be false for this function. Registration happens before any
// user session, so the platform JWT gate would reject the publishable key.
// The handler allows only that key. Password proof uses a second publishable
// client. The service key stays inside the admin client and is never returned.
function liveHandler(request: Request): Promise<Response> {
  const env = Deno.env.toObject();
  const credentials = resolveServerCredentials(env);
  const keys = loadCallerKeys(env);
  if (credentials === null || keys === null) {
    return handleOwnerRegister(request, {
      keys: { publishable: [], secret: [] },
      ports: unusedPorts(),
    });
  }
  const admin = createClient(
    credentials.url,
    credentials.serviceKey,
    clientOptions(),
  );
  return handleOwnerRegister(request, {
    keys,
    ports: {
      sql: createSqlPort(rpcBoundary(admin)),
      auth: createAuthAdminPort(adminBoundary(admin)),
      passwords: createPasswordProofPort(() =>
        passwordBoundary(
          createClient(
            credentials.url,
            credentials.publishableKey,
            clientOptions(),
          ),
        )
      ),
    },
  });
}

function boundaryError(
  error: {
    message: string;
    code?: string;
    status?: number;
    details?: string;
    hint?: string;
  } | null,
): BoundaryError | null {
  if (error === null) return null;
  return {
    message: error.message,
    code: error.code,
    status: error.status,
    details: error.details,
    hint: error.hint,
  };
}

function rpcBoundary(admin: SupabaseClient): RpcClient {
  return {
    async rpc(fn, args) {
      const { data, error } = await admin.rpc(fn, args);
      return { data, error: boundaryError(error) };
    },
  };
}

function adminBoundary(admin: SupabaseClient): AdminAuthClient {
  return {
    auth: {
      admin: {
        async getUserById(uid) {
          const { data, error } = await admin.auth.admin.getUserById(uid);
          return {
            data: { user: data.user },
            error: boundaryError(error),
          };
        },
        async createUser(attributes) {
          const { data, error } = await admin.auth.admin.createUser({
            id: String(attributes.id),
            email: String(attributes.email),
            phone: String(attributes.phone),
            password: String(attributes.password),
            email_confirm: true,
            phone_confirm: true,
          });
          return {
            data: { user: data.user },
            error: boundaryError(error),
          };
        },
      },
    },
  };
}

function passwordBoundary(client: SupabaseClient): PasswordAuthClient {
  return {
    auth: {
      async signInWithPassword(credentials) {
        const { data, error } = await client.auth.signInWithPassword(
          credentials,
        );
        return {
          data: { user: data.user ? { id: data.user.id } : null },
          error: boundaryError(error),
        };
      },
    },
  };
}

function unusedPorts() {
  const unavailable = () => Promise.reject(new Error("misconfigured"));
  return {
    sql: { begin: unavailable, complete: unavailable },
    auth: { getUserById: unavailable, createUser: unavailable },
    passwords: { verifyBoth: unavailable },
  };
}

Deno.serve(liveHandler);
