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

    Description: View for editing Lua script code, loading and saving it.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="ScriptEditor";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";   
    import Status from "./Status.svelte";
    import { onMount } from 'svelte';
    import { sendStatusMessage } from "./_tools";
    import CodeEditor from './CodeEditor.svelte';
    import Icon from './Icon.svelte';
    
    let CFG={};
    let disabled=false;

    // some input/output variables
    export let id = 0;
    id=Number(id);
    export let closeHandle;
    export let closebutton = true;
    export let showheader = true;
    // number to start the first code line on 
    export let startline = 1; 

    // some promises
    let data;
    let updateent;
    
    // some variables    
    let show = false;
    let name = "";
    let script = "";

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        // get the data/code
        data = getData();     
    });      


    // call REST-server to set script 
    const setScript = () => {
        let params={};
        params["id"]=id;
        params["name"]=name;
        params["script"]=script;
        updateent=call_aurora("setScript",params);
    };

    // get all data needed 
    async function getData () {    
        show = false;
       
        // get the script
        let params={};
        params["id"] = id;
        let getscript = await call_aurora("getScript",params);
        if (getscript.err == 0) {
            // get the script
            script = getscript.script;
            if (script == undefined) { script = ""; }           
            name = getscript.name;
            show = true;
            return 1;
        } else { return 0; }
    };

    const sendUpdated = () => {
        sendStatusMessage("Successfully saved script...","info");
        return "";
    }     
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving script..." type="processing" />   
        {/await}
    {/if}
    {#if updateent != undefined}
        {#await updateent}
            <Status message="Saving script..." type="processing" />
        {:then result}
            {#if result.err == 0}
                {sendUpdated()}
            {/if}    
        {/await}
    {/if}
    {#if show}  
        <!-- show title and table with entity metadata -->
        {#if showheader}
            <div class="ui_title ui_center">Edit Script</div>              
            <div class="ui_center">
                <div class="ui_output">Script Name</div>
                <div class="ui_input"><input type="text" bind:value={name} default={name}></div>
            </div>
        {/if}
        <div class="ui_row">
            <!-- show buttons -->        
            <div class="scripteditor_margin_top scripteditor_margin_left">
                <Icon name="save"
                    on:click={() => { setScript() }}
                    fill="#555"
                    margin="0.5rem"
                    size="40"
                    popuptext="Save" 
                />
                {#if closebutton}
                    <Icon name="close"
                        on:click={() => { closeHandle() }}
                        fill="#555"
                        margin="0.5rem"
                        size="40"
                        popuptext="Close"
                    />            
                {/if}
            </div>
        </div>
        <div class="ui_row ui_margin_top">            
            <CodeEditor bind:code={script} startnumber={startline} />          
        </div>
    {/if}    
{/if}

<style>
    .scripteditor_margin_left {
        margin-left: 40px;
    }

    .scripteditor_margin_top {
        margin-top: 8px;
    }

</style>
