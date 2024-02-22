<!--
    Copyright (C) 2021-2024 Jan Frode Jæger (jan.frode.jaeger@ntnu.no), NTNU, Trondheim, Norway

    This file is part of AURORA, a system to store and manage science data.

    AURORA is free software: you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free
    Software Foundation, either version 3 of the License, or (at your option)
    any later version.

    AURORA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with
    AURORA. If not, see <https://www.gnu.org/licenses/>.

    Description: Browse a computer by calling the AURORA REST-server, selecting a file or folder.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script> 
 
 <script>  
    import { onMount } from "svelte";
    import { getConfig } from "./_config";
    import { int2SI, sortArrayOfArray } from "./_tools.js";   
    import { call_aurora } from './_aurora';
    import { unixtime2ISO } from "./_iso8601";
    import Icon from "./Icon.svelte";
    import Status from "./Status.svelte";
   
    let CFG={};

    // component name
    let compname="ComputerBrowser";
    // create a random id number of this instance of component
    let myrand = counter++;
    // id of computer to browse, defaults to 0/invalid id
    export let id=0;
    // the selected folder or file at any given time
    export let selection="";
    // the selected folder only of the selection
    export let folder=selection;
    // delete data after copying? Defaults to false
    export let remove=false;
    // signal if folder is being shown or not?
    export let showing=false;
    // some internal variables
    let disabled=false;

    let cmetaget=false;       // flag that are true while fetching and processing computer metadata
    let cmetaprom;            // promise from REST-server on response on computer metadata
    let name="";              // name of computer from metadata
    let datafolder="";        // the starting location of the data on the computer in question
    let platform=0;           // computer platform - default: linux/unix.
    let cfolderget=false;     // flag that are true while getting and processing computer folder
    let cfolderprom;          // promise for info from the REST-server on folder info
    let folderdata;               // folder data from REST-server     
    let showresult=false;
    let toggleinput=false;    // to show or not to show is the....
    let folderup=false;       // show folder up choice or not.... 
    let username="";   
    let dir=1;                // sorting direction, 1=asc, -1=desc
    let row = 0;              // which row/field is being sorted, 0=name, 1=size, 2=datetime
    
  onMount(async () => {
    // fetch configuration and wait
    CFG =  await getConfig();
    // update disabled value
    disabled=(CFG["www.maintenance"] != undefined ? CFG["www.maintenance"] : false);
  });

  const getComputerMetadata = (id) => {
    if (id != 0) {
      let params={};
      params["id"]=id;
      cmetaprom=call_aurora("getComputerMetadata",params)
      // set that promise has been created
      cmetaget=true;
    }
  }

  const processComputerMetadata = (result) => {
    cmetaget=false;        
    if (result != undefined) {
      // save computer datafolder path for later use
      if (result.metadata[".computer.path"] != undefined) { datafolder=result.metadata[".computer.path"]; }
      platform=1;
      if ((datafolder != undefined) && (datafolder == /^\/cygdrive\/.*/)) {
        // this computer is windows based
        platform=2;
      }
      name=result.metadata[".system.entity.name"];
      listComputerFolder(selection);
    }
  }

  const listComputerFolder = (path) => {
    cfolderget=true;
    showresult=false;
    showing=false;
    let params={};
    params["id"]=id;
    params["path"]=path;
    cfolderprom=call_aurora("listComputerFolder",params);
    // set both folder and selection to the folder being
    // traversed into
    folder=path;
    selection=path;
  }

  const selectFile = (item) => {
    // update whats selected, but not folder
    selection=folder+"/"+item;
  }

  // go one folder up in the folder structure, if possible
  const folderUp = () => {
    let path=folder;
    path=path.replace(/^(.*)\/[^\/]+$/,'$1');
    listComputerFolder(path);
    // folder has now changed, as well as selection
    folder=path;
    selection=path;
  }

  const processComputerFolder = (result) => {
    cfolderget=false;

    if (result != undefined) {
      // get folder structure response
      folderdata=result.folder;
      if (platform == 2) {
        // clean selection

      }
    }
    // only show folder up-symbol if we 
    // actually have somewhere to go
    if ((selection != "") && 
        (selection != ".") && 
        (selection != "/") && 
        (selection != "./")) { 
        folderup=true; 
    } else { folderup=false; }

    // check if username is being appended to datafolder
    if (result.useusername) {
      // username is being appended
      username="/"+result.username;
    }
    // we are now allowed to show the folder-data
    showresult=true;
    showing=true;
  }

  const getFolders = () => {
    let fs=[];
    for (let key in folderdata.D) {
      fs.push([key,folderdata.D[key].size,unixtime2ISO(folderdata.D[key].datetime)]);
    }
    return fs;
  }

  const getFiles = () => {
    let fs=[];
    for (let key in folderdata.F) {
      fs.push([key,folderdata.F[key].size,unixtime2ISO(folderdata.F[key].datetime)]);
    }
    return fs;
  }

  const getAbsoluteFolder = () => {
    let path="("+datafolder+username+")/"+folder;
    path=path.replace(/\/\//g,"/");
    return path;
  }

  const toggle = () => {
    toggleinput=!toggleinput;
  }

  getComputerMetadata(id);
</script>    

<!-- here comes the rendering -->
{#if !disabled} 
  {#if cmetaget}
    {#await cmetaprom}      
      <Status message="Retrieving computer metadata..." type="processing" />     
    {:then result}
      {#if result.err == 0}
        {processComputerMetadata(result)}
      {/if}
    {/await}
  {/if}
  {#if cfolderget}
    {#await cfolderprom}
      <Status message="Retrieving computer folder list..." type="processing" />           
    {:then result}
      {#if result.err == 0}
        {processComputerFolder(result)}
      {/if}
    {/await}
  {/if}
  {#if showresult}
    <!-- Headers -->
    <div class="ui_center ui_title">Select Path</div>
    <div class="ui_label ui_center">Computer to create dataset from</div>
    <div class="ui_output ui_center">{name}</div>
    <div class="ui_label ui_center">Delete Data (after copying)</div>
    <div class="ui_center ui_input"><input type="checkbox" bind:checked={remove}></div>
    <div class="ui_browser ui_margin_top ui_margin_bottom">            
      <div class="ui_center ui_label">Folder Contents </div>      
      {#if toggleinput}
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <div class="ui_right" on:click={() => { toggle(); }}><Icon name="unfoldless" size="40" /></div>        
        <div class="ui_center ui_input">{getAbsoluteFolder()}&nbsp;<input type="text" bind:value={selection} size="100" maxlength="256"></div>
      {:else}  
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <div class="ui_right" on:click={() => { toggle(); }}><Icon name="unfoldmore" size="40" /></div>
      {/if}            
      {#if folderup}
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <div class="ui_center" on:click={() => { folderUp(); }}><Icon class="ui_center" name="arrowup" size="40" /></div>
      {/if}
      <div class="ui_folder_location">{getAbsoluteFolder()}</div>
      <div class="ui_table">
        <div class="ui_table_header_cell">&nbsp</div>
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <div class="ui_table_header_cell ui_cursor_default" on:click={() => { dir=(dir == 1 && row == 0 ? -1 : 1); row=0; }}>Name {#if row == 0 && dir == 1}<Icon name="arrowup" size={30} />{:else if row == 0 && dir == -1}<Icon name="arrowdown" size={30} />{/if}</div>
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <div class="ui_table_header_cell ui_cursor_default" on:click={() => { dir=(dir == 1 && row == 1 ? -1 : 1); row=1; }}>Size {#if row == 1 && dir == 1}<Icon name="arrowup" size={30} />{:else if row == 1 && dir == -1}<Icon name="arrowdown" size={30} />{/if}</div>
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <div class="ui_table_header_cell ui_cursor_default" on:click={() => { dir=(dir == 1 && row == 2 ? -1 : 1); row=2; }}>Date {#if row == 2 && dir == 1}<Icon name="arrowup" size={30} />{:else if row == 2 && dir == -1}<Icon name="arrowdown" size={30} />{/if}</div>
        <!-- First show all folders -->        
        {#each sortArrayOfArray(getFolders(),dir,row) as item,index}
          <!-- svelte-ignore a11y-click-events-have-key-events -->
          <div class="ui_table_row ui_cursor_pointer ui_hover_light" on:click={() => { listComputerFolder(folder+"/"+item[0]); }}>
            <div class="ui_table_cell"><Icon name="folder" size="40" /></div>
            <div class="ui_table_cell">{item[0]}</div>
            <div class="ui_table_cell"></div>
            <div class="ui_table_cell">{item[2]}</div>          
          </div>
        {/each}
        <!-- Next show all files -->
        {#each sortArrayOfArray(getFiles(),dir,row) as item,index}
          <!-- svelte-ignore a11y-click-events-have-key-events -->
          <div class="ui_table_row ui_cursor_pointer ui_hover_light" on:click={() => { selectFile(item[0]); }}>
            <div class="ui_table_cell"><Icon name="file" size="40" /></div>
            <div class="ui_table_cell">{item[0]}</div>
            <div class="ui_table_cell">{int2SI(item[1])}</div>
            <div class="ui_table_cell">{item[2]}</div>
          </div>
        {/each}    
      </div>       
      {#if folderup}
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <div class="ui_center" on:click={() => { folderUp(); }}><Icon class="ui_center" name="arrowup" size="40" /></div>
      {/if}     
    </div>
  {/if}  
{/if}
