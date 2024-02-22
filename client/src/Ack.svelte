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

    Description: Acknowledge notifications that have a voting-process running.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
 </script>

<script>
    // component name
    let compname="Ack";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";   
    import Status from "./Status.svelte";    
    import { onMount } from 'svelte';
    import { sendStatusMessage } from "./_tools";    
    
    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;    
    export let rid = "";    
    export let closeHandle;

    // some promises
    let data;    
    let updateack;
    
    // some variables    
    let show = false;        
    let acked = false;

    // rerender trigger
    let rerender = 0;

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        // show window
        show = true;
    });      

    // call REST-server to acknowledge notification
    async function acknowledge() {
        let params={};
        // attempt to ack notification      
        params["id"]=id;
        params["rid"]=rid;        
        let ack=await call_aurora("ackNotification",params);

        await ack;

        if (ack.err == 0) { acked = true; }

        if (ack.err == 0) { return 1; } else { return 0; }
    };
    
    const sendUpdated = () => {
        sendStatusMessage("Successfully acknowledged notification...","info");
        return "";
    }

</script>

<!-- Rendering -->
{#if !disabled}
    {#if updateack != undefined}
        {#await updateack}
            <Status message="Attempting to acknowledge notification..." type="processing" />
        {:then result}
            {#if result}
                {sendUpdated()}
            {/if}
        {/await}
    {/if}
    {#if show}    
        {#key rerender}
            <!-- show title and table with entity metadata -->
            <div class="ui_title ui_center">Acknowledge Notification</div>
            <div class="ui_center">
                <div class="ui_label">Notification</div>
                <div class="ui_text_large ui_output">{id}</div>
                {#if !acked}
                    <div class="ui_text_large ui_margin_top ui_center">
                        Are you sure you want to acknowledge notification {id}?
                    </div>
                    <div class="ui_margin_top">
                        <button class="ui_button" on:click={() => { updateack=acknowledge(); }} >Acknowledge</button>
                    </div>
                {/if}
                {#if acked}
                    <div class="ui_text_large ui_center ui_margin_top">
                        Successfully cast your votes on notification with ID {id}...                        
                    </div>
                    <div class="ui_text_large ui_center ui_margin_top">
                        Please note that it might not be enough to fully confirm the notification, as more votes might be needed 
                        (from other users or on higher escalation levels). The notification will be automatically sent to other 
                        pertinent users and escalated if needed.
                    </div>
                    <div class="ui_margin_top ui_center">
                        <button class="ui_button" on:click={() => { if (closeHandle != undefined) { closeHandle() }}}>Close</button>
                    </div>
                {/if}
            </div>
        {/key}
    {/if}        
{/if}
