import { spawn } from 'node:child_process';
import { watch } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const appDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const options = process.argv.slice(2);
if (options.length && (options.length !== 2 || options[0] !== '--port' || !/^\d{4,5}$/.test(options[1]) || Number(options[1]) > 65535)) {
  throw new Error('Verwendung: npm run dev -- [--port 4318]');
}
const port = options[1] ?? '4318';
const child = spawn(process.platform === 'win32' ? 'flutter.bat' : 'flutter', ['--suppress-analytics', 'run', '-d', 'web-server',
  '--web-hostname', '127.0.0.1', '--web-port', port, '--no-pub'],
  { cwd: appDirectory, shell: process.platform === 'win32', stdio: ['pipe', 'pipe', 'pipe'] });
child.stdout.pipe(process.stdout);
child.stderr.pipe(process.stderr);
let timer;
let ready = false;
let restart = false;
child.stdout.on('data', chunk => { if (chunk.toString().includes('is being served at')) ready = true; });
const watchers = ['lib', 'web'].map(directory => watch(resolve(appDirectory, directory), { recursive: true }, (_, name) => {
  if (!ready || !name || !/\.(dart|html|css|js|svg)$/.test(name)) return;
  restart ||= name.endsWith('main.dart');
  clearTimeout(timer);
  timer = setTimeout(() => {
    if (!child.killed) { console.log('\nVideo Shrink: Änderung erkannt, Vorschau wird aktualisiert.'); child.stdin.write(restart ? 'R' : 'r'); restart = false; }
  }, 400);
}));
if (process.stdin.isTTY) {
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.on('data', data => {
    if (data.includes(3)) { child.kill('SIGINT'); }
    else { child.stdin.write(data); }
  });
}
const stop = signal => child.kill(signal);
process.on('SIGINT', () => stop('SIGINT'));
process.on('SIGTERM', () => stop('SIGTERM'));
child.on('error', error => { console.error(`Flutter konnte nicht gestartet werden: ${error.message}`); process.exitCode = 1; });
child.on('close', code => {
  clearTimeout(timer);
  watchers.forEach(watcher => watcher.close());
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
  process.stdin.pause();
  process.exitCode = code ?? 1;
});
