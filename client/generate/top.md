# Overview of the AURORA web-client

## Main, Technical Buildup

The AURORA web-client has been written in Svelte using rollup for bundling the code for 
usability across older and newer browser versions.

The code base is located in the source code repo under the src-folder. The code starts in the 
main.js file which loads the index.svelte component.

The source code also contains several files that starts with underscore ("_"). These are 
mostly libraries and code that are reused across the client.

These are:
