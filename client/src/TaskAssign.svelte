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

    Description: View and assign tasks on the AURORA entity tree.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="TaskAssign";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";   
    import Status from "./Status.svelte";    
    import { onMount } from 'svelte';
    import { sendStatusMessage, hash2SortedSelect } from "./_tools";    
    import InputSearchList from "./InputSearchList.svelte";
    import Modal from "./Modal.svelte";    
    
    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);

    // some promises
    let data;    
    let updateass;
    
    // some variables    
    let show = false;
    let show_editcomp = false;
    let enttype = "";
    let cameltype = "";
    let name = "";
    let assigns = {};
    let tasks = {};
    let computers = {};
    let compval = 0;
    let curcomp = 0;
    let taskval = 0;    

    // rerender trigger
    let rerender = 0;

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        data = getData();
    });      

    // call REST-server to set assignments    
    async function setTaskAssignments() {
        let params={};
        // set task assignments        
        params["id"]=id;
        params["assignments"]=assigns;
        let updateass=await call_aurora("set"+cameltype+"TaskAssignments",params);

        await updateass;

        if (updateass.err == 0) { assigns = updateass.assignments; }

        if (updateass.err == 0) { return 1; } else { return 0; }
    };

    // get all data needed 
    async function getData () {    
        show = false;
       
        // get entity type
        let params={};
        params.id = id;        
        let gettype = await call_aurora("getType",params);

        if (gettype.err == 0) {
            // get data
            enttype = gettype.type;
        }

        // get task assignments on above type
        cameltype=String(enttype).substring(0,1).toUpperCase() + String(enttype).substring(1).toLowerCase();
        params={};
        params.id = id;  
        let getass = await call_aurora("get"+cameltype+"TaskAssignments",params);

        // was data retrieved successfully?
        if (getass.err == 0) {
            // get subscriptions
            assigns = getass.assignments;
        }

        // get name of entity 
        params={};        
        params.id = id;
        let getname = await call_aurora("getName",params);

        // was data retrieved successfully?
        if (getname.err == 0) {
            // save users
            name = getname.name;            
        }

        // get computers
        params={};
        let getcomps = await call_aurora("enumComputers",params);

        await getcomps;

        if (getcomps.err == 0) {
            // save computers
            computers=getcomps.computers;
        }

        params={};
        let gettasks = await call_aurora("enumTasks",params);

        await gettasks;

        if (gettasks.err == 0) {
            // save tasks
            tasks=gettasks.tasks;
        }
                
        if ((gettype.err == 0) && (getass.err == 0) && (getname.err == 0) &&
            (getcomps.err == 0 ) && (gettasks.err == 0)) {
            // show data
            show = true;
            // return success
            return 1;
        } else { return 0; }
    };

    const sendUpdated = () => {
        sendStatusMessage("Successfully updated assignments...","info");
        return "";
    }

    const addComp = () => {
       if (assigns == undefined) {assigns =  {};}
       if (assigns[compval] == undefined) {
            // computer does not exist already, add it  
            assigns[compval]=[];
            // rerender interface
            rerender++; 
            // remove computer from selection dialog
            compval = 0;
       }
    }

    const editComp = () => {
        if (assigns[curcomp] != undefined) {
            show_editcomp=true;
        }
    }

    const removeComp = () => {
        if (assigns[curcomp] != undefined) {
            // computer exists, remove it and its task assignments
            delete assigns[curcomp];
            // rerender
            rerender++;
            // reset curcomp
            curcomp=0;
        }
    }

    const closeEditComp = () => {
        show_editcomp =false;
        taskval = 0;
    }

    const addTask = () => {
        // ensure we have a valid taskval
        if ((taskval != undefined) && (taskval != 0)) {
            // ensure that we have an empty array if need be
            if (assigns[curcomp] == undefined) { assigns[curcomp] = []; }
            // add task
            assigns[curcomp].push(taskval);
            // rerender
            rerender++;
            // reset taskval
            taskval=0;
        }
    }

    const removeTask = (idx) => {
        // remove this array element
        assigns[curcomp].splice(idx,1);    
        // rerender
        rerender++; 
    }

    const moveTaskUp = (idx) => {
        if (idx > 0) {
            let el1=assigns[curcomp][idx-1]
            let el2=assigns[curcomp][idx];
            // move places
            assigns[curcomp].splice(idx-1,2,el2,el1);
            // rerender
            rerender++;
        }
    }

    const moveTaskDown = (idx) => {
        if (idx < assigns[curcomp].length-1) {
            let el1=assigns[curcomp][idx];
            let el2=assigns[curcomp][idx+1];
            // move places
            assigns[curcomp].splice(idx,2,el2,el1);
            // rerender
            rerender++;
        }
    }
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving task assignment data..." type="processing" />
        {/await}
    {/if}
    {#if updateass != undefined}
        {#await updateass}
            <Status message="Updating task assignments..." type="processing" />
        {:then result}
            {#if result}
                {sendUpdated()}
            {/if}    
        {/await}
    {/if}    
    {#if show}    
        {#key rerender}
            <!-- show title and table with entity metadata -->
            <div class="ui_title ui_center">Edit Task Assignments</div>            
            <div class="ui_center">
                <div class="ui_label">Name</div>
                <div class="ui_text_large ui_output">{name} ({id})</div>
                <div class="ui_label">Add Computer</div>
                <div class="ui_input">
                    <InputSearchList bind:value={compval} datalist={hash2SortedSelect(computers)} defaultValue={compval} />
                </div>
                <div class="ui_margin_top">
                    <button class="ui_button" on:click={() => { addComp() }}>Add</button>
                </div>
                <div class="ui_label">Current Computers</div>
                <div class="ui_select">
                    <select class="ui_margin_top" bind:value={curcomp} size=8>
                        {#each Object.keys(assigns) as cid}
                            <option value={cid}>{computers[cid]}</option>
                        {/each}
                    </select>
                </div>    
                 <div class="ui_margin_top ui_row">
                    <button class="ui_button" on:click={() => { editComp() }}>Edit</button>
                    <button class="ui_button" on:click={() => { removeComp() }}>Remove</button>
                </div>
                <div class="ui_margin_top">
                    <button class="ui_button" on:click={() => { updateass=setTaskAssignments(); }} >Update</button>
                </div>
                 {#if show_editcomp}
                    <Modal width="60" height="90" border={false} closeHandle={() => { closeEditComp() }}>                        
                        <div class="ui_title ui_center">Edit Computer Tasks</div>
                        <div class="ui_label">Computer</div>                            
                        <div class="ui_output">{computers[curcomp]}</div>
                        <div class="ui_label">Tasks</div>
                        <div class="ui_input ui_center">
                            <InputSearchList bind:value={taskval} datalist={hash2SortedSelect(tasks)} defaultValue={taskval} />
                        </div>
                        <div class="ui_margin_top">
                            <button class="ui_button" on:click={() => { addTask() }}>Add</button>
                        </div>
                        <div class="ui_label">Current Tasks</div>
                        <div class="ui_table">                                    
                            {#each assigns[curcomp] as tid,index}
                                <div class="ui_table_row">
                                    <div class="ui_table_cell">
                                        {tasks[tid]} ({tid})
                                    </div>
                                    <div class="ui_table_cell">
                                        <button on:click={() => { moveTaskUp(index) }} class="ui_button">&#8593</button>
                                    </div>
                                    <div class="ui_table_cell">
                                        <button on:click={() => { moveTaskDown(index) }} class="ui_button">&#8595</button>
                                    </div>
                                    <div class="ui_table_cell">
                                        <button on:click={() => { removeTask(index) }} class="ui_button">-</button>
                                    </div>
                                </div>
                            {/each}                                
                        </div>                        
                    </Modal>
                 {/if}
            </div>            
        {/key}
    {/if}        
{/if}
