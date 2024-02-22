## How to develop

In order to start development of the code of this web-client, do the following:

1. Create a folder where your AURORA web-client code/git repo resides.
1. Populate the folder with the source code of the AURORA web-client git repo.
1. Install all necessary dependencies as configured in the package.json-file by writing "npm install" and hitting enter.
1. Move the public/settings.example-file to public/settings.yaml.
1. Configure and setup the AURORA web-client by updating the public/settings.yaml file. See the installation-documentation 
in the AURORA-server code.
1. Start the build and subsequent serving of the web-client by writing "npm run dev" and then hit enter.

After a while the screen should show that the bundle is available locally on "localhost:8080". Point your browser 
to localhost:8080 to start using the compiled/bundled solution.

There also exists a development docker-set that can be used to run a complete AURORA environment and then allow the 
checking of code being developed in real-time. See the documentation of the AURORA REST-server for more information. This is 
the recommended way of developing the AURORA code, both for REST-server and the web-client. It is easy to setup and get to 
start using and easy to try out the complete AURORA codebase. We recommend however using a Linux OS when using this setup, although 
it should also work with some adjustments with a windows setup. This has however not been tested. 

## Build-up of the generated documentation

In the "generate"-folder of the svelte web-client you will also find a script called "generate.pl" which are able to generate 
the technical documentation of the AURORA REST-server located in public/docs/webclient/index.md (which you right now have the pleasure of 
reading). The script uses the files top.md, middle.md and bottom.md in addition to some quick analysis of the code to generate the 
documentation.

The generation does the following in this order:

1. Writes the top.md file to the public/docs/webclient/index.md-file.
1. Writes list of library modules and what they do to the index.md-file.
1. Writes the middle.md file to the index.md-file.
1. Writes the component overview and what they do to the index.md-file.
1. Writes the import/use of application svelte components of each component to the index.md-file.
1. Writes the bottom.md-file to the index.md-file.
