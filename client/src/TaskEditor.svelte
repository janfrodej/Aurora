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

    Description: View and edit a Task in the AURORA entity tree.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="TaskEditor";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";   
    import Status from "./Status.svelte";
    import Tabs from "./Tabs.svelte";
    import { onMount } from 'svelte';
    import { sortArray, sendStatusMessage } from "./_tools";    
    import Modal from "./Modal.svelte";    

    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);

    // some promises
    let data;
    let updateent;
    let reqdata;
    
    // some variables    
    let show = false;
    let show_operation = false;
    let name = "";
    let stores = {};
    let computers = {};
    let task = {};    
    let opno = -1;        
    let classvalue = "";
    let genvalue = "";
    let storeparams = {};

    // rerender trigger
    let rerender = 0;

    // tab control
    let activeItem="Get";

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        data = getData();
    });      

    // call REST-server to set task    
    const setTask = () => {
        let params={};
        params["id"]=id;
        params["name"]=name;
        params["task"]=task;   
        updateent=call_aurora("setTask",params);
    };

    // get all data needed 
    async function getData () {    
        show = false;
       
        // enum stores
        let params={};
        let getstores = await call_aurora("enumStores",params);

        if (getstores.err == 0) {
            // get the flags
            stores = getstores.stores;
        }

        // enum computers
        params={};        
        let getcomputers = await call_aurora("enumComputers",params);

        // was data retrieved successfully?
        if (getcomputers.err == 0) {
            computers = getcomputers.computers;
            // add none-selected choice
            computers["0"] = "NONE SELECTED";
        }

        // get task info        
        params={};
        // set dataset id
        params["id"] = id;
        let gettask = await call_aurora("getTask",params);

        // was data retrieved successfully?
        if (gettask.err == 0) {
            // get task info
            task = gettask.task;
            // get task name
            name = gettask.name;            
        }

        if ((getstores.err == 0) && (getcomputers.err == 0) && (gettask.err == 0)) {
            // show data
            show = true;
            // return success
            return 1;
        } else { return 0; }
    };

    const sendUpdated = () => {
        sendStatusMessage("Successfully updated task...","info");
        return "";
    }

    const editOperation = (no) => {
        opno = no;
        show_operation = true;
        reqdata = getRequiredParameters(no);
    }

    const closeOperation = () => {
        show_operation = false;
    }

    const addOperation = () => {
        let optype = String(activeItem).toLowerCase();
        if (task[optype] == undefined) { task[optype] = {} }
        let pos = Object.keys(task[optype]).length + 1;
        task[optype][pos]={};
        task[optype][pos].name="";
        task[optype][pos].store=0;
        task[optype][pos].computer=0;
        task[optype][pos].classparam={};
        task[optype][pos].param={};
        // set operation no
        opno = pos;
        show_operation = true;
        // reset store-params. We have not selected any store id yet
        storeparams = {};
    }

    const addClassParam = () => {
        let optype = String(activeItem).toLowerCase();


        // check that value is not blank/empty
        if (/^\s*$/.test(classvalue)) {
            // give a warning
            sendStatusMessage("Cannot add a class-parameter that is blank...","error");
        } else if (!Object.keys(task[optype][opno].classparam).includes(classvalue)) {
            // key does not exist already - add it
            task[optype][opno].classparam[classvalue] = "";
            // reset add-field
            classvalue = "";
        } else {
            // give a warning
            sendStatusMessage("Cannot add a class-parameter \""+classvalue+"\" that already exists...","error");
        }
    };

    const addParam = () => {
        let optype = String(activeItem).toLowerCase();

        // check that value is not blank/empty
        if (/^\s*$/.test(genvalue)) {
            // give a warning
            sendStatusMessage("Cannot add a class-parameter that is blank...","error");
        } else if (!Object.keys(task[optype][opno].param).includes(genvalue)) {
            // key does not exist already - add it
            task[optype][opno].param[genvalue] = "";
            // reset add-field
            genvalue = "";
        } else {
            // give a warning
            sendStatusMessage("Cannot add a parameter \""+genvalue+"\" that already exists...","error");
        }
    };

    const removeClassParam = (name) => {
        let optype = String(activeItem).toLowerCase();

        // remove the given paramtere
        delete task[optype][opno].classparam[name];
        // rerender 
        rerender++;
    };

    const removeParam = (name) => {
        let optype = String(activeItem).toLowerCase();

        // remove the given paramtere
        delete task[optype][opno].param[name];
        // rerender 
        rerender++;
    };

    const removeOperation = (no) => {
        let optype = String(activeItem).toLowerCase();

        // remove operation in question
        delete task[optype][no];
        // rerender
        rerender++;
    }

    const moveUp = (no) => {
        let optype = String(activeItem).toLowerCase();
        
        // move it up if possible
        if (no > 1) {
            let a = task[optype][Number(no)-1];
            let b = task[optype][Number(no)];
            task[optype][Number(no)-1] = b;
            task[optype][Number(no)] = a;
            // rerender
            rerender++;
        }
    };

    const moveDown = (no) => {
        let optype = String(activeItem).toLowerCase();

        // move it down if possible
        if (no < Object.keys(task[optype]).length) {
            let a = task[optype][Number(no)+1];
            let b = task[optype][Number(no)];
            task[optype][Number(no)+1] = b;
            task[optype][Number(no)] = a;            
            // rerender
            rerender++;
        }
    };

    async function getRequiredParameters(no) {
        let optype = String(activeItem).toLowerCase();

        // get required parameters
        let params = {};
        // set necessary info to retrieve required params
        params["id"] = task[optype][no].store;
        params["classparam"] = task[optype][no].classparam;
        let getreqparm = await call_aurora("enumStoreRequiredParameters",params);

        await getreqparm;

        if (getreqparm.err == 0) {
            // get the parameters
            storeparams = getreqparm.parameters;
            // remove local, because it will be controlled ny AURORA
            delete storeparams.local;
            // success
            return 1;
        } else {
            return 0;
        }
    }    
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving task data..." type="processing" />
        {/await}
    {/if}
    {#if updateent != undefined}
        {#await updateent}
            <Status message="Updating task..." type="processing" />
        {:then result}
            {#if result.err == 0}
                {sendUpdated()}
            {/if}
        {/await}
    {/if}
    {#if reqdata != undefined}
        {#await reqdata}
            <Status message="Retrieving transfer-method parameters data..." type="processing" />
        {/await}
    {/if}
    {#if show}    
        {#key rerender}
            <!-- show title and table with entity metadata -->
            <div class="ui_title ui_center">Edit Task</div>
            <div class="ui_center">
                <div class="ui_output">Task Name</div>
                <div class="ui_margin_top">
                    <input class="ui_input" type="text" bind:value={name} default={name}>
                </div>
            </div>
            <!-- show tabs -->
            <Tabs tabItems = {["Get","Put","Del"]} bind:activeItem = {activeItem} />
            
            <!-- show add operation  -->
            <button on:click={() => { addOperation() } } class="ui_button">+</button>
                        
            <!-- show each operation -->            
            <div class="ui_table">    
                {#if task[String(activeItem).toLowerCase()] != undefined}
                    {#each sortArray(Object.keys(task[String(activeItem).toLowerCase()],undefined,0)) as no,index}                                                
                        <div class="ui_table_row">
                            <div class="ui_table_cell">
                                <button class="ui_button" on:click={() => { editOperation(no)}}>{task[String(activeItem).toLowerCase()][no].name} ({stores[task[String(activeItem).toLowerCase()][no].store]})</button>
                            </div>
                            <div class="ui_table_cell">
                                <button on:click={() => { moveUp(no) }} class="ui_button">&#8593</button>
                            </div>
                            <div class="ui_table_cell">
                                <button on:click={() => { moveDown(no) }} class="ui_button">&#8595</button>
                            </div>
                            <div class="ui_table_cell">
                                <button on:click={() => { removeOperation(no)  }} class="ui_button">-</button>
                            </div>
                        </div>
                    {/each}
                {/if}
            </div>

            <!-- show specific operation -->
            {#if show_operation}
                <Modal width="60" height="90" border={false} closeHandle={() => { closeOperation() }}>
                    <div class="ui_center ui_title">Edit Operation</div>
                    <div class="ui_margin_left ui_margin_top">
                    <div class="ui_label">Name</div>
                    <input type="text" class="ui_input" bind:value={task[String(activeItem).toLowerCase()][opno].name}>
                    <!-- show computer-selection -->
                    <div class="ui_label">Computer</div>
                    <select bind:value={task[String(activeItem).toLowerCase()][opno].computer}>
                        {#each Object.keys(computers) as compno}
                            <option value={compno} selected={(compno == task[String(activeItem).toLowerCase()][opno].computers ? true : false)}>
                                {computers[compno]}
                            </option>
                        {/each}
                    </select>

                    <!-- show store-class/transfer-method selection -->
                    <div class="ui_label">Transfer-method</div>
                    <select bind:value={task[String(activeItem).toLowerCase()][opno].store} 
                        on:change={() => { reqdata = getRequiredParameters(opno) }}>
                        {#each Object.keys(stores) as storeno}
                            <option value={storeno} selected={(storeno == task[String(activeItem).toLowerCase()][opno].store ? true : false)}>
                                {stores[storeno]}
                            </option>
                        {/each}
                    </select>

                    <!-- show class-parameters -->
                    <div class="ui_label">Class-param (specific to transfer-method)</div>
                    <div class="ui_margin_left ui_margin_top">
                        Add <input class="ui_input" type="text" bind:value={classvalue}><button class="ui_button" on:click={() => { addClassParam(); }}>+</button>
                        {#each sortArray(Object.keys(task[String(activeItem).toLowerCase()][opno].classparam)) as cparname}
                            <div class="ui_label">{cparname}</div>
                            <input type="text" bind:value={task[String(activeItem).toLowerCase()][opno].classparam[cparname]}>
                            <button on:click={() => { removeClassParam(cparname) }} class="ui_button">-</button>
                        {/each}
                    </div>    

                    <!-- show general parameters -->
                    <div class="ui_label">Param (general/common)</div>
                    <div class="ui_margin_left ui_margin_top">
                        Add <input class="ui_input" type="text" bind:value={genvalue}><button class="ui_button" on:click={() => { addParam(); }}>+</button>
                        <details>
                            <summary>Required parameters</summary>
                            <ul>
                                {#each sortArray(Object.keys(storeparams)) as name}
                                    <li>
                                        {name} (default: {storeparams[name].value}, regex: {storeparams[name].regex})
                                    </li>
                                {/each}
                            </ul>
                        </details>
                        {#each sortArray(Object.keys(task[String(activeItem).toLowerCase()][opno].param)) as parname}
                            <div class="ui_label">{parname}</div>
                            <input type="text" bind:value={task[String(activeItem).toLowerCase()][opno].param[parname]}>
                            <button on:click={() => { removeParam(parname) }} class="ui_button">-</button>
                        {/each}
                    </div>    
                    </div>
                </Modal>    
            {/if}

            <!-- show update button -->
            <div class="ui_center">
                <button class="ui_button ui_margin_top" on:click={() => { setTask() }}>Update</button>
            </div>        
        {/key}
    {/if}        
{/if}
