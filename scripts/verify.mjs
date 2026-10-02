import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('../', import.meta.url));
for (const args of [['analyze', '--no-pub'], ['test', '--no-pub']]) {
  const result = spawnSync(process.platform === 'win32' ? 'flutter.bat' : 'flutter',
    ['--suppress-analytics', ...args],
    { cwd: directory, stdio: 'inherit', shell: process.platform === 'win32' });
  if (result.error) console.error(result.error.message);
  if (result.status !== 0) process.exit(result.status ?? 1);
}
