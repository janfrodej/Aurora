# Overview of the AURORA web-client

## Main, Technical Buildup

The AURORA web-client has been written in Svelte using rollup for bundling the code for 
usability across older and newer browser versions.

The code base is located in the source code repo under the src-folder. The code starts in the 
main.js file which loads the index.svelte component.

The source code also contains several files that starts with underscore ("_"). These are 
mostly libraries and code that are reused across the client.

These are:


- **\_aurora.js**: - Handles calling the AURORA REST-server, waiting for result, handling returns, errors and more. Used by the whole of the web-client application when calling AURORA
- **\_auroradataloader.js**: - Class to load data through a REST-call from an AURORA REST-server
- **\_auroradatasetcache.js**: - Class to cache dataset entries in memory and read from AURORA REST-server when needed this gives results as if it was the REST-server (same return structure)
- **\_auroratreecache.js**: - Class to cache entity tree in memory and read from AURORA REST-server when needed
- **\_config.js**: - Fetches the AURORA configuration file. Used by the whole AURORA application.
- **\_cookies.js**: - Handles cookies in AURORA, reading them, writing them.
- **\_iso8601.js**: - Handles timedate data by converting between unixtime, javascript Date and ISO-8601.
- **\_stores.js**: - Global state data that are used across components. In this case only the selected route/which parts of the app to open and its parameteres are eventually stored here.
- **\_sysschema.js**: - AURORA database schema data which tells where to find and store metadata.
- **\_tools.js**: - Utility functions of AURORA such as sorting arrays and into arrays, conversion and sending application messages and more.
- **\_version.js**: - Sets the version of the web-client. Used by components where relevant.


The index.svelte component handles the logon process and either redirects to a feide.cgi-script for
FEIDE-authentication (OAuth) or logs on using the built-in AuroraID account.

After login, the code redirects to the Main.svelte-component which is the central "hub" for most of
what is done in the application.

FEIDE-authentication is performed by the public/feide.cgi-script written in Perl. It runs on the web-server and converts the
credentials it receives into a set of AURORA crumbs credentials that are forwarded to the AURORA web-client. In this way the
credentials exposed to the user browser are only valid for AURORA and temporary in nature.

All the cookies are base64 encoded before they are stored or served to the application. The reason for this is that the feide.cgi
perl-script did not handle having certain characters in the cookie values through the CGI-library and its cookie-routines. It then
resulted in issues with the transport between it and the web-client application. The easiest solution was therefore to encode
all cookies into and out of the browser seemlessly for the application. This makes reading cookie contents manually in the
browser through the developer window a bit like reading ancient egyptian hieroglyphs before Champollion came along.

## Component overview

- **Ack.svelte**: Acknowledge notifications that have a voting-process running.
- **Announcement.svelte**: Show any announcements that are written in the public/announcement.log-file.
- **Assign.svelte**: Handles Template-assignments on an entity.
- **AuroraBranch.svelte**: Show a branch/node of the entity tree with dropdowns, information etc.
- **AuroraHeader.svelte**: Show the AURORA header visible throughout the entire application.
- **AuroraTree.svelte**: Show the entire AURORA entity tree by recursing the tree data.
- **Auth.svelte**: Handle changing an Authenticator-type's authentication credentials - ie. set a new password.
- **CircularDateTimeSlider.svelte**: Show a circular slider arrangement for setting/adjusting year, month and date.
- **CircularSlider.svelte**: Component to show one circular slider, set its boundaries and what to display etc.
- **Close.svelte**: Handles starting a close-dataset process.
- **CodeEditor.svelte**: A simple code-editor with numbered lines based on the textarea html tag.
- **ComputerBrowser.svelte**: Browse a computer by calling the AURORA REST-server, selecting a file or folder.
- **Control.svelte**: Setup a tunnell to remote control a computer in the AURORA entity tree.
- **Create.svelte**: Create a AURORA dataset, selecting file/folder if applicable and setting metadata.
- **DeleteEntity.svelte**: Delete an AURORA-entity.
- **Expire.svelte**: Update/set a new dataset expiration date.
- **FloatContent.svelte**: Handle showing some content floating over the web-page.
- **FolderTree.svelte**: Show a tree arrangement based upon a set of folder data.
- **Icon.svelte**: Display a named icon with a set of attributes. Mostly uses Google Material fonts.
- **InputSearchList.svelte**: Show a selection dropdown box with the option to function as both a search box and a regular selection box.
- **Log.svelte**: Show the log of a dataset.
- **Main.svelte**: Handle showing the main hub of the AURORA web-client and selecting what to do.
- **Manage.svelte**: Show the manage dataset view. 
- **Members.svelte**: View, Add or Remove members of a GROUP-entity.
- **MetadataEditor.svelte**: Edit metadata of any given AURORA entity, template handling, checking etc.
- **Modal.svelte**: Show a modal container with any given content inside.
- **MoveEntity.svelte**: Move an entity on the AURORA entity tree.
- **Permissions.svelte**: Handle viewing, changing and adding permissions of AURORA entities.
- **Privacy.svelte**: Show the privacy message of AURORA.
- **Remove.svelte**: Handle and initiate an AURORA dataset removal process.
- **RenameEntity.svelte**: Rename the textual name of an AURORA entity.
- **Retrieve.svelte**: View a AURORA dataset folder structure and render and download the selected data output.
- **SQLStructEditor.svelte**: View and edit the SQLStruct structure used by the search engine in AURORA. See the REST documentation of the AURORA REST-server for more information on SQLStruct.
- **SQLStructRenderer.svelte**: Render a SQLStruct search-structure. See the REST documentation of the AURORA REST-server for more information on SQLStruct.
- **ScriptEditor.svelte**: View for editing Lua script code, loading and saving it.
- **ScriptExecuter.svelte**: Loading, running and viewing a Lua script inside the AURORA environment.
- **SetFileInterfaceStore.svelte**: Set the fileinterface store on a group in the AURORA entity tree.
- **Status.svelte**: Show a status message overlay with a suitable icon to follow.
- **StatusMessage.svelte**: Display a status message on screen when a statusmessage-event triggers.
- **Subscription.svelte**: View and set notification-subscriptions and votes on the AURORA entity tree.
- **Table.svelte**: Show and handle a table arrangement based upon table input.
- **Tabs.svelte**: Handle and show a tab bar.
- **TaskAssign.svelte**: View and assign tasks on the AURORA entity tree.
- **TaskEditor.svelte**: View and edit a Task in the AURORA entity tree.
- **Template.svelte**: View and edit a template in AURORA.
- **index.svelte**: Handle login to the AURORA web-client.

## Component use/imports

This is an overview of which components are used by a component and only consists of those that are main ones
of the project itself. All _-libraries and svelte internal libraries have med removed from this overview.

- **Ack.svelte**:
  - Status.svelte
- **Announcement.svelte**: NO USE OF APPLICATION COMPONENTS.
- **Assign.svelte**:
  - InputSearchList.svelte
  - Status.svelte
- **AuroraBranch.svelte**:
  - Icon.svelte
- **AuroraHeader.svelte**:
  - Privacy.svelte
- **AuroraTree.svelte**:
  - Assign.svelte
  - AuroraBranch.svelte
  - Auth.svelte
  - DeleteEntity.svelte
  - Icon.svelte
  - Members.svelte
  - MetadataEditor.svelte
  - Modal.svelte
  - MoveEntity.svelte
  - Permissions.svelte
  - RenameEntity.svelte
  - ScriptEditor.svelte
  - ScriptExecuter.svelte
  - SetFileInterfaceStore.svelte
  - Status.svelte
  - Subscription.svelte
  - TaskAssign.svelte
  - TaskEditor.svelte
  - Template.svelte
- **Auth.svelte**:
  - InputSearchList.svelte
  - Status.svelte
- **CircularDateTimeSlider.svelte**:
  - CircularSlider.svelte
- **CircularSlider.svelte**: NO USE OF APPLICATION COMPONENTS.
- **Close.svelte**:
  - Status.svelte
  - Table.svelte
- **CodeEditor.svelte**: NO USE OF APPLICATION COMPONENTS.
- **ComputerBrowser.svelte**:
  - Icon.svelte
  - Status.svelte
- **Control.svelte**:
  - InputSearchList.svelte
  - Status.svelte
- **Create.svelte**:
  - ComputerBrowser.svelte
  - InputSearchList.svelte
  - MetadataEditor.svelte
  - Status.svelte
- **DeleteEntity.svelte**:
  - Status.svelte
- **Expire.svelte**:
  - CircularDateTimeSlider.svelte
  - Status.svelte
  - Table.svelte
- **FloatContent.svelte**: NO USE OF APPLICATION COMPONENTS.
- **FolderTree.svelte**: NO USE OF APPLICATION COMPONENTS.
- **Icon.svelte**: NO USE OF APPLICATION COMPONENTS.
- **InputSearchList.svelte**:
  - Icon.svelte
- **Log.svelte**:
  - Status.svelte
  - Table.svelte
- **Main.svelte**:
  - Announcement.svelte
  - AuroraTree.svelte
  - Auth.svelte
  - Control.svelte
  - Create.svelte
  - Manage.svelte
  - Modal.svelte
  - Status.svelte
  - Tabs.svelte
- **Manage.svelte**:
  - Ack.svelte
  - Close.svelte
  - Expire.svelte
  - Icon.svelte
  - Log.svelte
  - MetadataEditor.svelte
  - Modal.svelte
  - Permissions.svelte
  - Remove.svelte
  - Retrieve.svelte
  - SQLStructEditor.svelte
  - Status.svelte
  - Table.svelte
- **Members.svelte**:
  - InputSearchList.svelte
  - Status.svelte
- **MetadataEditor.svelte**:
  - Icon.svelte
  - Status.svelte
- **Modal.svelte**: NO USE OF APPLICATION COMPONENTS.
- **MoveEntity.svelte**:
  - Status.svelte
  - Table.svelte
- **Permissions.svelte**:
  - InputSearchList.svelte
  - Status.svelte
- **Privacy.svelte**:
  - Modal.svelte
- **Remove.svelte**:
  - Status.svelte
  - Table.svelte
- **RenameEntity.svelte**:
  - Status.svelte
  - Table.svelte
- **Retrieve.svelte**:
  - FolderTree.svelte
  - Status.svelte
  - Table.svelte
- **SQLStructEditor.svelte**:
  - Icon.svelte
  - SQLStructRenderer.svelte
- **SQLStructRenderer.svelte**: NO USE OF APPLICATION COMPONENTS.
- **ScriptEditor.svelte**:
  - CodeEditor.svelte
  - Icon.svelte
  - Status.svelte
- **ScriptExecuter.svelte**:
  - Icon.svelte
  - Status.svelte
- **SetFileInterfaceStore.svelte**:
  - Status.svelte
  - Table.svelte
- **Status.svelte**: NO USE OF APPLICATION COMPONENTS.
- **StatusMessage.svelte**: NO USE OF APPLICATION COMPONENTS.
- **Subscription.svelte**:
  - InputSearchList.svelte
  - Modal.svelte
  - Status.svelte
- **Table.svelte**:
  - Icon.svelte
- **Tabs.svelte**: NO USE OF APPLICATION COMPONENTS.
- **TaskAssign.svelte**:
  - InputSearchList.svelte
  - Modal.svelte
  - Status.svelte
- **TaskEditor.svelte**:
  - Modal.svelte
  - Status.svelte
  - Tabs.svelte
- **Template.svelte**:
  - Status.svelte
- **index.svelte**:
  - Announcement.svelte
  - AuroraHeader.svelte
  - FloatContent.svelte
  - Main.svelte
  - Privacy.svelte
  - Status.svelte
  - StatusMessage.svelte


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
