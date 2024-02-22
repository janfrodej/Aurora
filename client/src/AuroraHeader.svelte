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

    Description: Show the AURORA header visible throughout the entire application.
-->
<script type="ts">
  import { onMount } from 'svelte';
  import Privacy from './Privacy.svelte';
  import { getConfig } from "./_config.js";
  import { VERSION } from "./_version.js";

  let CFG = {};
  let showprivacy = false;

  onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig()      
  });   

  const closePrivacy = () => {
    showprivacy=false;
  };
   
</script>

<div class="header">
  <div class="header_frame_left">
    <div class="header_logo"><img src={CFG["www.base"]+"/media/ntnu_bredde_eng.png"} height="30" alt="NTNU Logo"/></div>
    <div class="header_systemname">AURORA Web Client</div>
   </div>
  <div class="header_frame_right">
    <div class="header_systemversion">Version: {VERSION}</div>  
    <!-- svelte-ignore a11y-click-events-have-key-events -->
    <div class="header_privacy"><div on:click={() => { showprivacy = true }}>Privacy</div></div>  
    <div class="header_helppages"><a href={CFG["www.helppages"]} target="_aurorahelppages">Help Pages</a></div>  
  </div>
</div>

{#if showprivacy}
   <Privacy show={true} showbanner={false} closeHandler={() => { closePrivacy() }}/>
{/if}
