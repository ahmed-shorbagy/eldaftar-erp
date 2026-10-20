import { createClient } from "@supabase/supabase-js";
import {
  loadCallerKeys,
  resolveServerCredentials,
} from "../owner-register/http.ts";
import { handleStaffCreation, type StaffCreationPorts } from "./handler.ts";
import { staffPasswordProof } from "./password_proof.ts";

const options = {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
  global: {
    fetch: (input: RequestInfo | URL, init?: RequestInit) =>
      fetch(input, {
        ...init,
        signal: init?.signal ?? AbortSignal.timeout(15000),
      }),
  },
};

Deno.serve(async (request) => {
  const env = Deno.env.toObject(),
    credentials = resolveServerCredentials(env),
    keys = loadCallerKeys(env);
  if (!credentials || !keys || keys.publishable.length === 0) {
    return new Response(JSON.stringify({ code: "unavailable" }), {
      status: 503,
      headers: {
        "cache-control": "no-store",
        "content-type": "application/json",
      },
    });
  }
  const admin = createClient(credentials.url, credentials.serviceKey, options);
  const client = createClient(credentials.url, keys.publishable[0], options);
  const rpc = async (
    database: typeof admin,
    name: string,
    args: Record<string, unknown>,
  ) => {
    const { data, error } = await database.rpc(name, args);
    if (error) throw new Error(error.message);
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error("unavailable");
    }
    return data as Record<string, unknown>;
  };
  const ports: StaffCreationPorts = {
    async user(token) {
      const { data, error } = await client.auth.getUser(token);
      return !error && data.user && !data.user.is_anonymous
        ? data.user.id
        : null;
    },
    proof: staffPasswordProof,
    prepare(token, args) {
      const caller = createClient(credentials.url, keys.publishable[0], {
        ...options,
        global: {
          ...options.global,
          headers: { Authorization: `Bearer ${token}` },
        },
      });
      return rpc(caller, "begin_closing_staff_creation_v1", args);
    },
    async identity(id) {
      const { data, error } = await admin.auth.admin.getUserById(id);
      if (error?.status === 404) return null;
      if (error) throw new Error("unavailable");
      return data.user
        ? { id: data.user.id, phone: data.user.phone ?? null }
        : null;
    },
    async create(id, phone, password) {
      const { data, error } = await admin.auth.admin.createUser({
        id,
        phone,
        password,
        phone_confirm: true,
      });
      if (error) {
        throw new Error(
          ["phone_exists", "user_already_exists"].includes(error.code ?? "")
            ? "identifier_taken"
            : "unavailable",
        );
      }
      if (data.user?.id !== id) throw new Error("unavailable");
    },
    complete(owner, key) {
      return rpc(admin, "complete_closing_staff_creation_v1", {
        p_owner: owner,
        p_key: key,
      });
    },
  };
  return handleStaffCreation(request, ports);
});
