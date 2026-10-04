// Line-based driver: first input supplies transient keys; later lines name phases.
// No credentials are written to disk or stdout. Use a pipe, never a terminal echo.
import { createInterface } from 'node:readline';
import { createStorageValidation } from './daily_notes_storage_hosted.mjs';
// Interactive orchestration disables input echo before accepting credentials.
if (process.stdin.isTTY) process.stdin.setRawMode(true);
console.log(JSON.stringify({ inputReady: true, inputEchoDisabled: !!process.stdin.isTTY }));
const lines = createInterface({ input: process.stdin, terminal: false });
let validation;
for await (const line of lines) {
  try {
    const input = JSON.parse(line);
    if (!validation) {
      validation = createStorageValidation(input);
      console.log(JSON.stringify({ ready: true }));
    } else {
      if (!['createUsers', 'run', 'cleanupObjects', 'cleanupUsers', 'manifest', 'results'].includes(input.phase)) {
        throw new Error('unknown validation phase');
      }
      const result = await validation[input.phase]();
      console.log(JSON.stringify({ phase: input.phase, result }));
    }
  } catch (error) {
    // Request bodies and credentials are never included in errors by the harness.
    console.log(JSON.stringify({ failed: true, error: error.message,
      manifest: validation?.manifest() }));
  }
}
