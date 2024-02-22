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

    Description: Rename the textual name of an AURORA entity.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="RenameEntity";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";   
    import Status from "./Status.svelte";
    import { onMount } from 'svelte';
    import { MD } from "./_sysschema.js";
    import Table from "./Table.svelte";

    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);
    export let closeHandle;

    // some promises
    let data;
    let renameent;
    
    // some variables    
    let show = false;
    let name = "";
    let newname = "";
    let type="";
    let nicetype="";
    let renamed = false;

    let md = {};
    let mdtable = {};
    let mdtabledata = {};

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        data = getData();
    });      

    // set the retrieved metadata in md variable of component
    const setMetadata = (metadata) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (metadata["metadata"] == undefined) { return ""; }        
        md = metadata["metadata"];
        // put data into mdtabledata
        let i = 1;
        mdtabledata[i]={};
        mdtabledata[i]["attr"] = "Type";
        mdtabledata[i]["value"] = nicetype;
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Parent";
        mdtabledata[i]["value"]=md[MD["entity_parentname"]];
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="ID";
        mdtabledata[i]["value"]=md[MD["entity_id"]];
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Name";
        mdtabledata[i]["value"]=md[MD["name"]];
        
        return "";
    };

    // call REST-server to delete entity
    const renameEntity = () => {
        let params={};
        params["id"]=id;
        params["name"]=newname;
        renameent=call_aurora("set"+nicetype+"Name",params);
    };

    // define metadata table
    const defineTable = () => {
        // define the component table       
        mdtable.oddeven=true;    
        mdtable.orderby="attr";
        mdtable.fields=[
            { name: "Attribute", dataname: "attr", visible: true },
            { name: "Value", dataname: "value", visible: true },            
        ];
    };

    // get all data needed 
    async function getData () {    
        // define table for data
        defineTable();    

        show = false;

        // first get entity type
        let params={};
        params["id"]=id;
        let gettype = await call_aurora("getType",params);

        if (gettype.err == 0) {
            // save its type
            type = String(gettype.type).toUpperCase();
            nicetype = type.substring(0,1).toUpperCase() + type.substring(1).toLowerCase();
        }

        // get metadata of entity        
        params={};
        // set dataset id
        params["id"] = id;
        let getmd = await call_aurora("getMetadata",params);

        // set some info if metadata was retrieved successfully
        if (getmd.err == 0) {
            // save its name
            name = getmd.metadata[MD["name"]];
            // also update newname
            newname = name;
        
            // update global metadata structure for the table
            setMetadata(getmd);

            // show data
            show = true;

            // return success            
            return 1;
        } else { return 0; }
    };

    const setRenamed = () => {
        renamed = true;
        return "";
    }
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving entity data..." type="processing" />
        {/await}
    {/if}
    {#if renameent != undefined}
        {#await renameent}
            <Status message="Renaming {type} with id {id} to {newname}..." type="processing" />
        {:then result}
            {#if result.err == 0}
                {setRenamed()}
            {/if}
        {/await}
    {/if}
    {#if show}    
        <!-- show title and table with entity metadata -->
        <div class="ui_title ui_center">Rename {type}</div>              
        <Table data={mdtabledata} headers={mdtable} orderdirection={0} />
        {#if !renamed}
            <!-- show inputs for renaming -->
            <div class="ui_center ui_margin_top">
                <div class="ui_output">New name</div>
                <div class="ui_margin_top ui_input">
                    <input type="text" bind:value={newname} default={name}>
                </div>
                <button class="ui_button ui_margin_top" on:click={() => { renameEntity() }}>Rename</button>
            </div>  
        {:else}
            <!-- show success message -->
            <div class="ui_text_large ui_center ui_margin_top">Successfully renamed {type} with id {id}...</div>
            <div class="ui_center"><button class="ui_button" on:click={() => { closeHandle(); }}>Close</button></div>
        {/if}
    {/if}    
{/if}
