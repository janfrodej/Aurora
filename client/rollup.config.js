// Copyright (C) 2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
//
// This file is part of AURORA, a system to store and manage science data.
//
// AURORA is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// AURORA is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// AURORA. If not, see <https://www.gnu.org/licenses/>.
//
import svelte from 'rollup-plugin-svelte';
import resolve from '@rollup/plugin-node-resolve';
import livereload from 'rollup-plugin-livereload';
import css from 'rollup-plugin-css-only';
import commonjs from 'rollup-plugin-commonjs';
//import ignore from 'rollup-plugin-ignore';

function serve() {
  // Keep a reference to a spawned server process
  let server;

  function toExit() {
    // kill the server if it exists
    if (server) server.kill(0);
  }

  return {
    writeBundle() {
      if (server) return;
      // Spawn a child server process
      server = require('child_process').spawn(
        'npm',
        ['run', 'start', '--', '--dev'],
        {
          stdio: ['ignore', 'inherit', 'inherit'],
          shell: true,
        }
      );

      // Kill server on process termination or exit
      process.on('SIGTERM', toExit);
      process.on('exit', toExit);
    },
  };
}

export default {
  // This `main.js` file we wrote
  input: 'src/main.js',
  output: {
    // The destination for our bundled JavaScript
    file: 'public/build/bundle.js',
    // Our bundle will be an Immediately-Invoked Function Expression
    format: 'iife',
    // The IIFE return value will be assigned into a variable called `app`
    name: 'app',
  },
  plugins: [
    svelte({
      // Tell the svelte plugin where our svelte files are located
      include: 'src/**/*.svelte',
    }),
    // component CSS are extracted into global bundle
    css({ output: 'bundle.css' }),
  //  ignore(['path', 'fs', 'child_process', 'crypto', 'url', 'module']),
    // Tell any third-party plugins that we're building for the browser
    resolve({ 
       browser: true,
    }),
    serve(),
    livereload('public'),
    commonjs({
      requireReturnsDefault: 'auto',
      strictRequires: 'auto',
      namedExports: {
         // left-hand side can be an absolute path, a path
         // relative to the current directory, or the name
         // of a module in node_modules
         'node_modules/wasmoon/dist/index.js': [ 'LuaFactory' ],
      },
    }),
  ],
};
