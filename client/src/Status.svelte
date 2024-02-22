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
<script>    
    import { onMount } from 'svelte';
    import { getConfig } from "./_config";    

    export let type = "processing";
    export let message = "";

    let CFG={};
    let show=false;

    onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      show = true;
    });  
</script>

{#if show}
    <div class="status_overlay {(type == "processing" ? "status_progress" : "")}">
        <div class="status_box">
            <div class="status_message">{message}</div>
            <div class="status_icon">                
            </div>        
        </div>
    </div>
{/if}

<style>
    .status_progress {
        cursor: wait;
    }

    .status_overlay {
        position: fixed;
        display: block;        
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(128,128,128,0.5);
        z-index: 10000;    
    }

    .status_box {
        display: flex;
        justify-content: center;
        align-items:center;
        flex-direction: column;
        text-align: center;        
        z-index:10001;
        height: 100%;
        width: 100%;
    }

    .status_icon {
        margin-top: 20px;
    }

    .status_message {
        font-weight: bolder;
        font-size: 1.5em;
    }
</style>
