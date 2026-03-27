import { build } from 'esbuild';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const outFile = path.resolve(
  __dirname,
  '../htmlwidgets/lib/stream-viz/stream_main.js'
);

await build({
  entryPoints: [path.resolve(__dirname, 'src/stream_main.js')],
  bundle: true,
  format: 'iife',
  outfile: outFile,
  minify: true,
  sourcemap: false,
  target: 'es2019',
  logLevel: 'info',
});
