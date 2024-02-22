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

    Description: Move an entity on the AURORA entity tree.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="MoveEntity";
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
    export let id = [];
    // accept single IDs as well and convert to an array if needed
    if (!Array.isArray(id)) { id = [Number(id)]; }
    export let closeHandle;
    export let parent=0;

    // some promises
    let data;
    let moveent;
    
    // some variables    
    let show = false;    
    let moved = false;
    let mvcount = 0;
    let movedcount = 0;

    let md = {};
    let mdcount=0;

    // entity types
    let enttypes={};
    
    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        data = getData();
    });      
    

    // call REST-server to move entity
    async function moveEntity() {
        let params={};
        // go through each entity
        for (let i=0; i < id.length; i++) {
            params["id"]=id[i];
            // get type from metadata and convert to textual type
            let type = String(enttypes[md[id[i]][MD["entity_type"]]]).toUpperCase();
            let nicetype = type.substring(0,1).toUpperCase() + type.substring(1).toLowerCase();
            params["parent"]=parent;
            mvcount++;
            let mv=await call_aurora("move"+nicetype,params);
            if (mv.err == 0) { movedcount++; }
        }   
    };

    // get all data needed 
    async function getData () {            
        show = false;
        
        // get entity types
        let params={};        
        let gettypes = await call_aurora("enumEntityTypes",params);

        if (gettypes.err == 0) {
            // save the entity types for later
            enttypes = gettypes.types;
        }

        // get metadata of entity(-ies)  
        for (let i=0; i < id.length; i++) {    
            params={};
            // set dataset id
            params["id"] = id[i];
            mdcount++;
            let getmd = await call_aurora("getMetadata",params);

            // set some info if metadata was retrieved successfully
            if (getmd.err == 0) {
                // put metadata in hash
                md[id[i]]=getmd.metadata;                        
            }
        };

        show = true;

        // return success            
        return 1;
    };

    const setMoved = () => {
        moved = true;
        return "";
    }
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving entity data of {mdcount}/{id.length} entities..." type="processing" />
        {/await}
    {/if}
    {#if moveent != undefined}
        {#await moveent}
            <Status message="Moving {mvcount}/{id.length} entities..." type="processing" />
        {:then result}
            {setMoved()}
        {/await}
    {/if}
    {#if show && id.length > 0}    
        <!-- show title and table with entity metadata -->
        <div class="ui_title ui_center">Move Entities</div>        
        {#if !moved}
            <!-- show delete mesage -->
            <div class="ui_center ui_text_large ui_margin_top">Move the following {(id.length > 1 ? "entities" : "entity")}:</div>
            <div class="ui_center ui_text_large ui_margin_top tree_row">
                {#each id as idn}            
                    &nbsp;{idn}&nbsp;-&nbsp;{md[idn][MD["name"]]}&nbsp;(<div class="treecolor_{String(enttypes[md[idn][MD["entity_type"]]||0]).toUpperCase()}">{enttypes[md[idn][MD["entity_type"]]||0]}</div>),
                {/each}
            </div>
            <!-- show button to accept deletion -->
            <div class="ui_center">                  
                <div class="ui_label">Are you sure?</div>
                <button class="ui_button" on:click={() => { moveent=moveEntity() }}>Move</button>
            </div>  
        {:else}
            <!-- show success message -->            
            <div class="ui_text_large ui_center ui_margin_top">
                {#if movedcount > 0}
                    Successfully moved {movedcount} of {id.length} entitites...
                {:else}
                    Unable to move any of the entities. Please check error messages...
                {/if}    
            </div>
            <div class="ui_center"><button class="ui_button" on:click={() => { closeHandle(); }}>Close</button></div>
        {/if}
    {/if}    
{/if}
