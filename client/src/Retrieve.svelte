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

    Description: View a AURORA dataset folder structure and render and download the selected data output.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="Retrieve";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";
    import { unixtime2ISO } from "./_iso8601";
    import Table from "./Table.svelte";
    import FolderTree from "./FolderTree.svelte";
    import Status from "./Status.svelte";
    import { onMount } from 'svelte';

    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0; // id of dataset to render interface of
    id=Number(id);
    export let ifid = 0; // interface id of interface to use for rendering
    ifid=Number(ifid);

    // some promises
    let getif;
    let getfolders;
    let renderif;
    let getmd;    
    let getdata;
    // some variables
    let md = {};
    let mdtable = {};
    let mdtabledata = {};
    let ifdata = {};
    let folderdata = {};
    let renderdata = {};
    let selected = {}; 
    // show variables
    let show = false;
    let showif = false;
    let showfolders = false;
    let showrender = false;    

    // on finished rendering
    onMount(async () => {        
      // fetch configuration and wait
      CFG =  await getConfig();
      // update disabled
      disabled = CFG["www.maintenance"]||false;
      // attempt an authentication automatically
      // and thereby check our credentials
      // we will be redirected to login-page if it fails
	  call_aurora("doAuth",undefined);
      // get the data for the first screen
      getdata=getData();
	});
    
    // set the retrieved metadata in md variable of component
    const setMetadata = (metadata) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (metadata["metadata"] == undefined) { return ""; }    
        md = metadata["metadata"];
        // put data into mdtabledata
        let i = 1;
        mdtabledata[i] = {};
        mdtabledata[i]["attr"] = "Created";
        mdtabledata[i]["value"] = unixtime2ISO(md["system.dataset.time.created"]||0); 
        i++;
        mdtabledata[i] = {};
        mdtabledata[i]["attr"] = "Expire Date";
        mdtabledata[i]["value"] = unixtime2ISO(md["system.dataset.time.expire"]||0);
        i++;
        mdtabledata[i] = {};
        mdtabledata[i]["attr"] = "Creator";
        mdtabledata[i]["value"] = md[".Creator"]||"N/A";
        i++;
        mdtabledata[i] = {};
        mdtabledata[i]["attr"] = "Computer";
        mdtabledata[i]["value"] = md["system.dataset.computername"]||"N/A";
        i++;
        mdtabledata[i] = {};
        mdtabledata[i]["attr"] = "Dataset Type";
        mdtabledata[i]["value"] = md["system.dataset.type"]||"N/A";
        i++;
        mdtabledata[i] = {};
        mdtabledata[i]["attr"] = "Group";
        mdtabledata[i]["value"] = md["system.entity.parentname"]||"N/A";

        show = true;
        return "";
    };

    // get complete folder and file listing for dataset in question
    const getFolders = () => {
        showfolders = false;
        let params={};
        params["id"] = id;
        getfolders = call_aurora("listDatasetFolder",params);
    };

    // update data with retrieved folder listing
    const setFolders = (result) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (result["folder"] == undefined) { return ""; }    
        folderdata=result.folder;
        showfolders = true;
        return "";
    };   

    // save data of interface to use for rendering
    const setInterface = (result) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (result["interface"] == undefined) { return ""; }    
        ifdata =  result.interface;
        // does the rendering generate the same MIME result
        // independant of the dataset ID provided? 
        if (ifdata.distinguishable) {
            // get folders of dataset, it does not
            // generate the same MIME result
            getFolders();
        } else {
            // just start rendering, MIME-result will be the same
            renderInterface();
        }
        showif = true;
        return "";
    };

    // attempt to render interface of dataset
    const renderInterface = () => {
        // do not show dataset folder structure
        showfolders=false;
        // generate paths
        let paths=[];
        if ((selected["/"]) || (Object.keys(selected).length == 0)) {
            // if none is chosen or root is chosen, we archive all of dataset
            // no need to add anything
        } else {
            for (let key in selected) {
                // only push paths that have been checked/are true
                if (selected[key]) { paths.push(key); }
            }
        }       
        // call render REST-call
        let params={};
        params["id"] = ifid;
        params["dataset"] = id;
        params["paths"] = paths;
        renderif = call_aurora("renderInterface",params);
    };

    // save result of render operation
    const setRender = (result) => {
        // rendered, type and result
        renderdata = result;   
        if (renderdata.err == 0) {
            // show result        
            showrender = true;
        } else {
            showfolders = true;
            showrender = false;            
        }
        return "";
    };

    // define close table
    const defineTable = () => {
        // define the component table       
        mdtable.oddeven=true;    
        mdtable.orderby="attr";
        mdtable.fields=[
            { name: "Attribute", dataname: "attr", visible: true },
            { name: "Value", dataname: "value", visible: true },            
        ];
    };

    // get all relevant data for component
    async function getData() {
        // define the table view
        defineTable();
        // get metadata of given dataset        
        let params={};
        // set dataset id
        params["id"] = id;
        getmd = await call_aurora("getDatasetSystemAndMetadata",params);

        await getmd;

        if (getmd.err === 0) {
            setMetadata(getmd);
        }   

        // get interface details
        params={};
        params["id"] = ifid;
        getif = await call_aurora("getInterface",params);

        await getif;

        // if successfully retrieved data, set interface details
        if (getif.err === 0) {
            setInterface(getif)
        }

        if ((getmd.err === 0) && (getif.err === 0)) { show = true; return 1; } else { return 0; }        
    }   
</script>

<!-- Rendering -->
{#if !disabled}
    {#if getdata != undefined}
        {#await getdata}            
            <Status message="Retrieving dataset and interface information..." type="processing" />             
        {/await}
    {/if}   
    {#if renderif != undefined}
        {#await renderif}
            <Status message="Rendering interface..." type="processing" />                 
        {:then result}
            {setRender(result)}            
        {/await}
    {/if}
    {#if getfolders != undefined}
        {#await getfolders}            
            <Status message="Reading dataset folder structure..." type="processing" />     
        {:then result}
            {setFolders(result)}
        {/await}
    {/if}
    {#if show}
        <div class="ui_center">      
            <div class="ui_title">Render Dataset Interface</div>
            <div class="ui_output">{id}</div>
            <div class="ui_label">Description</div>
            <div class="ui_output">{md[".Description"]}</div>    
            <div class="ui_label">Status</div>
            {#if md["system.dataset.status"] === "OPEN"}
                <div class="status_open">{md["system.dataset.status"]}</div>
            {:else if md["system.dataset.status"] === "CLOSED"}
                <div class="status_closed">{md["system.dataset.status"]}</div>
            {:else if md["system.dataset.status"] === "DELETED" }
                <div class="status_deleted">{md["system.dataset.status"]}</div>
            {:else}
                <div class="ui_output">{md["system.dataset.status"]}></div>
            {/if}
            <Table data={mdtabledata} headers={mdtable} orderdirection={0} />    
            {#if showfolders}  
                <div class="ui_left">
                    <FolderTree data={folderdata} bind:selected={selected} />
                </div>
            {/if}
            {#if showrender}
                {#if renderdata.rendered == 1}                
                    {#each renderdata.result as item,index}                    
                        {#if String(renderdata.type).match(/^text\/uri-list$/)}                        
                            {#if String(item).match(/^http[s]?:\/\/.*/)}
                                <div class="ui_margin_top ui_text_large"><a href={item}>{item}</a></div>
                            {:else}
                                <div class="ui_margin_top ui_text_large">{item}</div>
                            {/if}
                        {/if}
                    {/each}
                {:else if renderdata.err == 0}
                    <div class="ui_margin_top ui_text_large">Interface is still being rendered for dataset. Please press refresh in a little while...</div>
                    <button class="ui_button" on:click={() => { renderInterface() }}>Refresh</button>
                {/if}                   
            {/if}
            {#if !showrender && showfolders}
                <button class="ui_button" on:click={() => { renderInterface() }}>Render</button>
            {/if}
        </div>
    {/if}    
{/if}
