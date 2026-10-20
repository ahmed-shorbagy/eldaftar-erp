/** Private retry verifier; no plaintext is persisted, and key rotation is safe. */
export async function staffPasswordProof(
  owner: string,
  key: string,
  password: string,
): Promise<string> {
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const digest = new Uint8Array(
    await crypto.subtle.deriveBits(
      {
        name: "PBKDF2",
        hash: "SHA-256",
        iterations: 600000,
        salt: new TextEncoder().encode(`closing-staff:v1:${owner}:${key}`),
      },
      material,
      256,
    ),
  );
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
