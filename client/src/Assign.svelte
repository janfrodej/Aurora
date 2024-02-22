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

    Description: Handles Template-assignments on an entity.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="Assign";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { onMount } from 'svelte';
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";    
    import Status from "./Status.svelte";
    import { MD } from "./_sysschema";
    import { hash2SortedSelect, sendStatusMessage } from './_tools';
    import InputSearchList from './InputSearchList.svelte';
    
    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);

    // some promises
    let data;
    let assign;
    
    // some variables   
    let enttypes = {};
    let md = {};
    let orgtemplates = {};
    let templates = {};
    let assigns = {};
    let typeval = 0;
    let templval = 0;
    let assignval = 0;
    let changed = [];
    let show = false;    
    let rerender = 0;
    
    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        data=getData();
    });  

    async function getData () {            
        show = false;

        // get entity types
        let params={};        
        let gettypes = await call_aurora("enumEntityTypes",params);

        if (gettypes.err == 0) {
            // save the entity types for later            
            enttypes = gettypes.types;
            // go through enttypes and locate DATASET
            for (let type in enttypes) {
                // set default type to dataset, if possible
                if (String(enttypes[type]).toUpperCase() == "DATASET") { typeval = type; break; }
            }
        }            

        // get metadata of entity
        params={};
        // set dataset id
        params["id"] = id;
        let getmd = await call_aurora("getMetadata",params);

        // set some info if metadata was retrieved successfully
        if (getmd.err == 0) {
            // put metadata in hash
            md=getmd.metadata;                     
        }    

        // get templates
        params={};
        let gettempl =  await call_aurora("enumTemplates",params);

        if (gettempl.err == 0) {
            orgtemplates=gettempl.templates;
            templates=hash2SortedSelect(gettempl.templates);
        }

        // get template assignments
        params={};
        params["id"]=id;
        let getass = await call_aurora("getEntityTemplateAssignments",params);

        if (getass.err == 0) {
            assigns=getass.assignments;
        }        

        // show data
        show = true;

        if ((gettypes.err != 0) || (getmd.err != 0) || (gettempl.err != 0) || (getass.err != 0)) {
            return 0;
        } else {
            // return success            
            show = true;
            return 1;        
        }     
    };

    async function assignTemplates() {
        let params={};        
        params["id"]=id;

        // go through each changed entity type and assign templates
        let success=true;
        for (let i=0; i < changed.length; i++) {
            // set templates to assign
            params.templates=assigns[enttypes[changed[i]]];
            // set type
            params.type=enttypes[changed[i]];
            // attempt to assign them to the given type
            let ass = await call_aurora("assignGroupTemplate",params);
            if (ass.err != 0) {
                // something failed - abort further update attempts
                success=false;
                break;
            }
        }
        if (success) {
            // successfully updated all template assignments - clear changed tags
            changed=[];
        }
    }

    const update = () => {
        // attempt to assign templates
        assign = assignTemplates();
    };

    const addTemplate = () => {
        // add a template to the list - append to end        
        if (assigns[enttypes[typeval]] == undefined) {
            // make an empty array
            assigns[enttypes[typeval]]=[];
        }
        // add given template to array at the end
        if (!assigns[enttypes[typeval]].includes(Number(templval))) {
            // only add template if it is not there already
            assigns[enttypes[typeval]].push(Number(templval));
            // reset value in templval
            templval=0;
        }
        // tag given entity type as changed
        if (!changed.includes(typeval)) { changed.push(typeval); }
        // rerender interface
        rerender++;
    };

    const removeTemplate = () => {
        // remove template in question from array
        if (assigns[enttypes[typeval]] != undefined) {
            // first locate position of template, if at all
            let pos=assigns[enttypes[typeval]].indexOf(Number(assignval));
            if (pos > -1) {
                // element found - remove it
                assigns[enttypes[typeval]].splice(pos,1);
                // tag given entity type as changed
                if (!changed.includes(typeval)) { changed.push(typeval); }
            }
        }
        // rerender interface
        rerender++;
    };

    const moveUp = () => {
        // get current type
        let type=enttypes[typeval];
        if ((assignval != undefined) && (assignval > 0) && (assigns[type] != undefined)) {            
            // only do this if assigned value exists
            let pos=assigns[type].indexOf(assignval);
            // position must not be negative and above 0 in order to be able to 
            // move up
            if (pos > 0) {
                // value exists in array, lets move it up
                assigns[type].splice(pos-1,2,assigns[type][pos],assigns[type][pos-1]);
                // tag given entity type as changed
                if (!changed.includes(typeval)) { changed.push(typeval); }
                // rerender
                rerender++;
            }         
        }
    };

    const moveDown = () => {
        // get current type
        let type=enttypes[typeval];
        if ((assignval != undefined) && (assignval > 0) && (assigns[type] != undefined)) {            
            // only do this if assigned value exists
            let pos=assigns[type].indexOf(assignval);
            // position must not be negative and above 0 in order to be able to 
            // move down. It can also not be the last element in the array
            if ((pos >= 0) && (pos < assigns[type].length-1)) {
                // value exists in array, lets move it down
                assigns[type].splice(pos,2,assigns[type][pos+1],assigns[type][pos]);
                // tag given entity type as changed
                if (!changed.includes(typeval)) { changed.push(typeval); }
                // rerender
                rerender++;
            }    
        }
    };
</script>

{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving entity data of group "+id type="processing" />
        {/await}
    {/if}
    {#if assign != undefined}
        {#await assign}
            <Status message="Updating template assignments on group "+id type="processing" />
        {:then result}
            {#if result}
                {sendStatusMessage("Successfully updated assigned template(s)...","INFO")}
            {/if}    
        {/await}
    {/if}
    {#key rerender}
        {#if show}
            <div class="ui_center ui_title">Template Assignments</div>
            <div class="ui_center ui_label">Group Name</div>
            <div class="ui_center ui_text_large ui_output">{md[MD["name"]]} ({id})</div>
            <div class="ui_center">
                <!-- select assignment entity type -->
                <div class="ui_label">Assignment Type</div>
                <div class="ui_select">
                    <select bind:value={typeval} default={typeval}>
                        {#each Object.keys(enttypes) as entkey}
                            <option value={entkey} selected={(entkey == typeval ? true : false)}}>
                                {enttypes[entkey]}
                            </option>
                        {/each}
                    </select>                
                </div>
                <!-- show the template selection pool that one can add from -->
                <!-- if template has been added already, it will not be possible to add it to the list again -->
                <div class="ui_label">Add</div>
                <div class="ui_input">
                    <InputSearchList bind:value={templval} datalist={templates} defaultValue={templval} />
                </div>
                <button class="ui_margin_top ui_button" on:click={() => { addTemplate() }} 
                    disabled={(typeval != undefined && typeval != 0 && templval != undefined && templval != 0 ? false : true)}
                >
                    Add
                </button>
                <!-- show the template assignment on the chosen entity type -->
                <div class="ui_label">Edit</div>
                <div class="ui_row">
                    <div class="ui_select">
                        <select class="ui_margin_top" bind:value={assignval} size=8>
                            {#if assigns[enttypes[typeval]] != undefined}
                                {#each assigns[enttypes[typeval]] as assign}
                                    <option value={assign}>{orgtemplates[assign]}</option>
                                {/each}
                            {/if}                        
                        </select>
                    </div>
                    <div class="ui_column ui_margin_top">
                        <button class="ui_button" on:click={() => { moveUp() }} disabled={(assignval != undefined && assignval != 0 ? false : true)}>Up &#8593</button>
                        <button class="ui_button" on:click={() => { moveDown() }} disabled={(assignval != undefined && assignval != 0 ? false : true)}>Down &#8595</button>
                    </div>
                </div>
                <button class="ui_margin_top ui_button" on:click={() => { removeTemplate() }}
                    disabled={(assignval != undefined && assignval != 0 ? false : true)}                
                >
                    Remove
                </button>
                <!-- Only allow update if the assigns structure has changed -->
                <button class="ui_margin_top ui_button" on:click={() => { update() }} disabled={(changed.length > 0 ? false : true)}>Update</button>
            </div>
        {/if}
    {/key}
{/if}
