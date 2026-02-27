import * as esbuild from 'esbuild';
import { sassPlugin } from 'esbuild-sass-plugin';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const isWatch = process.argv.includes('--watch');

const buildOptions = {
  entryPoints: [
    path.resolve(__dirname, 'src/index.js'),
    path.resolve(__dirname, 'src/shidashi.scss'),
  ],
  bundle: true,
  outdir: path.resolve(__dirname, 'www/shidashi'),
  // JS goes to js/, CSS goes to css/
  entryNames: '[ext]/[name]',
  format: 'iife',
  globalName: 'Shidashi',
  sourcemap: true,
  minify: !isWatch,
  target: ['es2020'],
  plugins: [
    // jQuery is provided by Shiny at runtime — resolve to window.jQuery
    {
      name: 'jquery-external',
      setup(build) {
        build.onResolve({ filter: /^jquery$/ }, () => ({
          path: 'jquery',
          namespace: 'jquery-external',
        }));
        build.onLoad({ filter: /.*/, namespace: 'jquery-external' }, () => ({
          contents: 'module.exports = window.jQuery',
          loader: 'js',
        }));
      },
    },
    sassPlugin(),
  ],
  loader: {
    '.woff': 'file',
    '.woff2': 'file',
    '.ttf': 'file',
    '.eot': 'file',
    '.svg': 'file',
  },
};

if (isWatch) {
  const ctx = await esbuild.context(buildOptions);
  await ctx.watch();
  console.log('Watching for changes...');
} else {
  await esbuild.build(buildOptions);
  console.log('Build complete.');
}
