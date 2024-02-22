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

    Description: Display a status message on screen when a statusmessage-event triggers.
-->
<script>  
    // Remember to define class statusmessage_colors in your css-file and include background-color and color.  
    import { onMount } from 'svelte';
    // component to status messages
    let show = false;
    let message = "";    
    let level = "ERROR";

    const showMessage = (ev) => {
        // show message
        message = ev.message;
        if (ev.level !== undefined) {
            level = String(ev.level).toUpperCase();
        } else { level = "ERROR"; }
        show = true;            
    }

    const hideMessage = () => {
        // hide message
        show = false;
        message = "";
    }    

    // add event listener for statusmessage messages 
    document.addEventListener('statusmessage', (ev) => { showMessage(ev) });        
</script>

{#if show}
    <div class="statusmessage_overlay">  
        <div class="statusmessage_container">
            <div class="statusmessage_box statusmessage_colors">            
                <div class="statusmessage_icon">
                    {#if level == "INFO"}
                        <svg xmlns="http://www.w3.org/2000/svg" height="40px" viewBox="0 0 48 48" width="40px" fill="#000000"><path d="M22.65 34h3V22h-3ZM24 18.3q.7 0 1.175-.45.475-.45.475-1.15t-.475-1.2Q24.7 15 24 15q-.7 0-1.175.5-.475.5-.475 1.2t.475 1.15q.475.45 1.175.45ZM24 44q-4.1 0-7.75-1.575-3.65-1.575-6.375-4.3-2.725-2.725-4.3-6.375Q4 28.1 4 23.95q0-4.1 1.575-7.75 1.575-3.65 4.3-6.35 2.725-2.7 6.375-4.275Q19.9 4 24.05 4q4.1 0 7.75 1.575 3.65 1.575 6.35 4.275 2.7 2.7 4.275 6.35Q44 19.85 44 24q0 4.1-1.575 7.75-1.575 3.65-4.275 6.375t-6.35 4.3Q28.15 44 24 44Zm.05-3q7.05 0 12-4.975T41 23.95q0-7.05-4.95-12T24 7q-7.05 0-12.025 4.95Q7 16.9 7 24q0 7.05 4.975 12.025Q16.95 41 24.05 41ZM24 24Z"/></svg>
                    {:else if level === "WARN" || level === "WARNING"}
                        <svg xmlns="http://www.w3.org/2000/svg" height="40px" viewBox="0 0 48 48" width="40px" fill="#000000"><path d="M2 42 24 4l22 38Zm5.2-3h33.6L24 10Zm17-2.85q.65 0 1.075-.425.425-.425.425-1.075 0-.65-.425-1.075-.425-.425-1.075-.425-.65 0-1.075.425Q22.7 34 22.7 34.65q0 .65.425 1.075.425.425 1.075.425Zm-1.5-5.55h3V19.4h-3Zm1.3-6.1Z"/></svg>
                    {:else}
                        <svg xmlns="http://www.w3.org/2000/svg" height="40px" viewBox="0 0 48 48" width="40px" fill="#000000"><path d="M24 34q.7 0 1.175-.475.475-.475.475-1.175 0-.7-.475-1.175Q24.7 30.7 24 30.7q-.7 0-1.175.475-.475.475-.475 1.175 0 .7.475 1.175Q23.3 34 24 34Zm-1.35-7.65h3V13.7h-3ZM24 44q-4.1 0-7.75-1.575-3.65-1.575-6.375-4.3-2.725-2.725-4.3-6.375Q4 28.1 4 23.95q0-4.1 1.575-7.75 1.575-3.65 4.3-6.35 2.725-2.7 6.375-4.275Q19.9 4 24.05 4q4.1 0 7.75 1.575 3.65 1.575 6.35 4.275 2.7 2.7 4.275 6.35Q44 19.85 44 24q0 4.1-1.575 7.75-1.575 3.65-4.275 6.375t-6.35 4.3Q28.15 44 24 44Zm.05-3q7.05 0 12-4.975T41 23.95q0-7.05-4.95-12T24 7q-7.05 0-12.025 4.95Q7 16.9 7 24q0 7.05 4.975 12.025Q16.95 41 24.05 41ZM24 24Z"/></svg>            
                    {/if}    
                </div>
                {#if level === "INFO"}
                    <div class="statusmessage_message">Info! {message}</div> 
                {:else if level === "WARN" || level === "WARNING"}
                    <div class="statusmessage_message">Warning! {message}</div> 
                {:else}                
                    <div class="statusmessage_message">Error! {message}</div> 
                {/if}                    
                <div class="statusmessage_close_button">
                    <!-- svelte-ignore a11y-autofocus -->
                    <button class="ui_button" id="statusmessage_button" on:click={() => { hideMessage() }} autofocus={true}>Close</button>
                </div>
                &nbsp;
            </div>
        </div> 
    </div>    
{/if}

<style>
    .statusmessage_overlay {
        position: fixed;
        display: block;        
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(128,128,128,0.5);
        z-index: 30000;
    }

    .statusmessage_container {        
        position: fixed;
        display: block;
        top: 40%;
        left: 25%;      
        height: 50%;
        width: 50%;       
    }

    .statusmessage_box {
        display: flex;
        justify-content: center;
        align-items: center;
        flex-direction: column;
        text-align: center;           
        z-index:30001;     
        border-radius: 8px;
        border: 1px;
    }

    .statusmessage_icon {
        margin-top: 20px;
        margin-bottom: 20px;
        width: 40px;
        height: 40px;
    }
    
    .statusmessage_message {
        font-weight: bolder;
        font-size: 1.2em;
        padding: 8px;
    }

    .statusmessage_close_button {
        float: right;
        clear: both;
        margin-right: 10px;
        margin-top: 5px;
    }    
</style>
