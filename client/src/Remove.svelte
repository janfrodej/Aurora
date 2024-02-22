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

    Description: Handle and initiate an AURORA dataset removal process.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
 </script>

<script>
    // component name
    let compname="Remove";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { onMount } from "svelte";
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";
    import { unixtime2ISO } from "./_iso8601";
    import Table from "./Table.svelte";
    import Status from "./Status.svelte";    

    let CFG={};
    let disabled=false; 

    // some input/output variables
    export let id = 0;
    id=Number(id);

    // some promises
    let getmd;
    let removeds;
    // some variables
    let md = {};
    let mdtable = {};
    let mdtabledata = {};
    let show = false;
    let removed = false;
    let failed = false;
    let failedstr = "";

    onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // set disabled
      disabled = CFG["www.maintenance"]||false;

    });  

    // get metadata of dataset in question
    const getDatasetMetadata = () => {
        show = false;
        let params={};
        // set dataset id
        params["id"] = id;
        getmd = call_aurora("getDatasetSystemAndMetadata",params);
    };

    // set the retrieved metadata in md variable of component
    const setMetadata = (metadata) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (metadata["metadata"] == undefined) { return ""; }        
        md = metadata["metadata"];
        // put data into mdtabledata
        let i = 1;
        mdtabledata[i]={};
        mdtabledata[i]["attr"] = "Created";
        mdtabledata[i]["value"] = unixtime2ISO(md["system.dataset.time.created"]||0); 
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Expire Date";
        mdtabledata[i]["value"]=unixtime2ISO(md["system.dataset.time.expire"]||0);
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Creator";
        mdtabledata[i]["value"]=md[".Creator"]||"N/A";
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Computer";
        mdtabledata[i]["value"]=md["system.dataset.computername"]||"N/A";
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Dataset Type";
        mdtabledata[i]["value"]=md["system.dataset.type"]||"N/A";
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Group";
        mdtabledata[i]["value"]=md["system.entity.parentname"]||"N/A";

        show = true;
        return "";
    };

    // call REST-server to remove dataset
    const removeDataset = () => {
        let params={};
        params["id"]=id;
        removeds=call_aurora("removeDataset",params,false);
    };

    const setRemoved = () => {
        removed = true;        
        return "";
    }

    const setFailed = (result) => {       
        failedstr = result.errstr; 
        failed = true;
        return "";
    }

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

    // get all metadata for dataset
    const getData = () => {
        defineTable();
        getDatasetMetadata();
    };

    // start retrieval of all necessary data
    getData();
</script>

<!-- Rendering -->
{#if !disabled}
    {#if getmd != undefined}
        {#await getmd}        
            <Status message="Retrieving dataset metadata..." type="processing" />     
        {:then result}
            {#if result.err == 0}
                {setMetadata(result)}
            {/if}    
        {:catch}    
            &nbsp;
        {/await}
    {/if}
    {#if removeds != undefined}
        {#await removeds}
            <Status message="Removing dataset..." type="processing" />                 
        {:then result}
            {#if result.err == 0}
                {setRemoved()}
            {:else}
                {setFailed(result)}
            {/if}
        {/await}
    {/if}
    {#if show && !removed && !failed &&
     (md["system.dataset.status"] == "CLOSED" || md["system.dataset.status"] == "OPEN")}
        <div class="ui_center">      
            <div class="ui_title">Remove Dataset</div>
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
            <div class="ui_label">Are you sure?</div>
            <button class="ui_button ui_margin_top" on:click={() => { removeDataset() }}>Remove</button>
        </div>
    {/if}
    {#if show && removed }
        <div class="ui_label ui_text_large ui_center">Dataset {id} removal process initiated...</div>
    {/if}    
    {#if show && !removed && !failed && (md["system.dataset.status"] == "DELETED" || md["system.dataset.time.removed"] > 0) } 
        <div class="ui_label ui_text_large ui_center">Dataset {id} already removed. Unable to remove it again.</div>
    {/if}
    {#if show && failed}    
        <div class="ui_label ui_text_large ui_center">Failed to remove dataset {id}: {failedstr}</div>
    {/if}
{/if}
