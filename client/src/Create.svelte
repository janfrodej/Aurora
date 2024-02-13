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
    import { getConfig } from "./_config";    
    import MetadataEditor from "./MetadataEditor.svelte";
    import InputSearchList from "./InputSearchList.svelte";   
    import ComputerBrowser from "./ComputerBrowser.svelte";
    import { onMount } from 'svelte';
    import { call_aurora } from "./_aurora.js";
    import { hash2SortedSelect } from "./_tools.js";
    import { date2ISO } from "./_iso8601";
    import Status from "./Status.svelte";
    import { getCookieValue, setCookieValue } from "./_cookies";

    let disabled=false;
    let name="Create";
    let mode="";
    let types=[];
    let typeval="AUTOMATED";    
    let groups=[];
    let groupval="";
    let computers=[];
    let computerval="";
    let options;
    let selection="";
    let createfin=false;
    let id=0;
    let remove=false;
    let fullname="";
    let cmpshow=false;
    let CFG={};

    // handles first time logon attempt
    onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // set disabled
      disabled = CFG["www.maintenance"]||false;
      // update disabled value
      disabled=CFG["www.maintenance"]||false;    
      // attempt an authentication automatically
      // and thereby check our credentials
      // we will be redirected to login-page if it fails
		call_aurora("doAuth",undefined);
      // get the data for the first screen
      options=getOptions();
      // get cookie settings for type, computer and group
      let tval=getCookieValue(CFG["www.cookiename"],"createtype");
      let gval=getCookieValue(CFG["www.cookiename"],"creategroup");
      let cval=getCookieValue(CFG["www.cookiename"],"createcomputer");
      typeval=(tval != undefined && tval != "" ? tval : "AUTOMATED");
      groupval=(gval != undefined && gval != "" ? gval : "");
      computerval=(cval != undefined && cval != "" ? cval : "");
	 });

    const updateCookie = () => {
      // save create type to cookie
      setCookieValue(CFG["www.cookiename"],"createtype",typeval,CFG["www.domain"],CFG["www.cookie.timeout"],"/");
      // save create group to cookie
      setCookieValue(CFG["www.cookiename"],"creategroup",groupval,CFG["www.domain"],CFG["www.cookie.timeout"],"/");
      // save create computer to cookie
      setCookieValue(CFG["www.cookiename"],"createcomputer",computerval,CFG["www.domain"],CFG["www.cookie.timeout"],"/");
    }
   
    async function getOptions () {
       // attempt to get data for type, group and computer

       // types we just define
       types=[
          { id: "AUTOMATED", text: "Automated Acquire (data fetched by AURORA)" },
          { id: "MANUAL", text: "Manual Acquire (data put in place by user)" }
       ];

       // get groups
       let params={};
       params["perm"]=["DATASET_CREATE"];
       let grp=await call_aurora("getGroupsByPerm",params);
       
       await grp;       

       // get computers
       params={};
       params["perm"]=["COMPUTER_READ"];              
       let cmp=await call_aurora("getComputersByPerm",params);

       await cmp;

       // get user auth data (we want the fullname)
      params={};
      let authinfo=await call_aurora("getAuthData",params);

      await authinfo;

      // sort result into group if successful
      if (grp.err == 0) {
         // sort result
         groups=hash2SortedSelect(grp.groups);
      }

      if (cmp.err == 0) {
         // sort result
         computers=hash2SortedSelect(cmp.computers);
      }
      if (authinfo.err === 0) {
         // set fullname
         fullname=authinfo.fullname;
      }
      if ((grp.err == 0) && (cmp.err == 0)) { return 1; } else { return 0; }       
    }    

   const handleModeChange = (to) => {
      // save values to cookie
      updateCookie();
      if (to == "") { selection=""; }
      mode=to;      
   }
    
</script>

{#if !disabled}
   {#if mode == "" && options != undefined}
      {#await options}
         <Status message="Retrieving groups and computers..." type="processing" />     
      {:then result}      
         {#if result}
            <div class="ui_center">
               <div class="ui_label ui_margin_top">Type</div>
               <div class="ui_select">
                  <select bind:value={typeval}>
                     {#each types as typ}                        
                        <option value={typ.id} selected={(typ.id == typeval ? true : false)}}>
                           {typ.text}
                        </option>
                     {/each}
                  </select>
               </div>

               <div class="ui_label ui_margin_top">Group</div>
               <div class="ui_input">
                  <InputSearchList bind:value={groupval} datalist={groups} defaultValue={groupval} />
               </div>            

               <div class="ui_label ui_margin_top">Computer</div>
               <div class="ui_input">
                  <InputSearchList bind:value={computerval} datalist={computers} defaultValue={computerval} />                  
               </div>   
               
               {#if groupval != "" && computerval != "" && /^\d+$/.test(groupval) && /^\d+$/.test(computerval)}
                  <div class="ui_center ui_navigate"><button class="ui_button" on:click={() => handleModeChange("path")}>Next &#61;&#62;</button></div>
               {/if}
            </div>      
         {/if}   
      {:catch error}   
         <div class="ui_center">Unable to load form data for this page...please try again later...</div>
      {/await}
   {:else if mode == "path"}
      {#if typeval == "MANUAL"}
          <!-- skip selecting path if manual dataset -->
         {handleModeChange("metadata")}
      {:else}
         <div class="ui_center">
            <ComputerBrowser id={computerval} bind:selection={selection} bind:remove={remove} bind:showing={cmpshow} />
            {#if cmpshow}
               <div class="ui_center ui_navigate">
                  <button class="ui_button" on:click={() => handleModeChange("")}>&#60;&#61; Previous</button>
                  <button class="ui_button" on:click={() => handleModeChange("metadata")}>Next &#61;&#62;</button>
               </div>
            {/if}
         </div>
      {/if}
   {:else if mode == "metadata"}
      {#if createfin}
         <!-- finished creating dataset -->
         <div class="ui_text_large ui_center">Dataset {id} created successfully...</div>
      {:else}
         <!-- start metadata component and include group- and computer id -->
         <!-- and add current timedate as ISO 8601-formatted string -->
         <!-- and set which relative path to archive data from on the remote computer -->
         {#if typeval == "AUTOMATED"}
            <MetadataEditor parent={groupval} computer={computerval} remove={remove} type="dataset" path={selection} presets={{".Date": date2ISO(), ".Creator": fullname}} bind:finished={createfin} bind:id={id} />
         {:else}         
            <MetadataEditor acquire="manual" parent={groupval} computer={computerval} type="dataset" path={selection} presets={{".Date": date2ISO(),".Creator": fullname}} bind:finished={createfin} bind:id={id} />
         {/if}   
      {/if}
   {/if}
{:else}
   {window.location.href=CFG["www.base"]}
{/if}




    
