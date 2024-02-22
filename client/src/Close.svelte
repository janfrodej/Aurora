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
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
 </script>

<script>
    // component name
    let compname="Close";
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
    let closeds;
    // some variables
    let md = {};
    let mdtable = {};
    let mdtabledata = {};
    let show = false;
    let closed = false;

    onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // update disabled
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

    // call REST-server to close dataset
    const closeDataset = () => {
        let params={};
        params["id"]=id;
        closeds=call_aurora("closeDataset",params);
    };

    const setClosed = () => {
        show = false;
        closed = true;        
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
            <Status message="Retrieving metadata of dataset {id}..." type="processing" />             
        {:then result}
            {#if result.err == 0}
                {setMetadata(result)}
            {/if}    
        {/await}
    {/if}
    {#if closeds != undefined}
        {#await closeds}            
            <Status message="Closing dataset {id}..." type="processing" />     
        {:then result}
            {#if result.err == 0}
                {setClosed()}
            {/if}    
        {/await}
    {/if}
    {#if show && md["system.dataset.status"] != "CLOSED" && md["system.dataset.type"] == "MANUAL"}
        <div class="ui_center">      
            <div class="ui_title">Close Dataset</div>
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
            {#if !closed}
                <div class="ui_label ui_text_large">Are you sure?</div>
                <button class="ui_button" on:click={() => { closeDataset() }}>Close</button>
            {/if}    
        </div>
    {/if}
    {#if !show && closed}
        <div class="ui_center ui_text_large">Dataset closed successfully...</div>
    {/if}
    {#if show && !closed && md["system.dataset.status"] == "CLOSED"} 
        <div class="ui_center ui_text_large">Dataset already closed. Unable to close it again.</div>
    {/if}
    {#if show && !closed && md["system.dataset.type"] == "AUTOMATED"}
        <div class="ui_center ui_text_large">Dataset is of type AUTOMATED and cannot be closed here.</div>
    {/if}
{/if}
