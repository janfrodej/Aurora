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
    import InputSearchList from "./InputSearchList.svelte";      
    import { onMount } from 'svelte';
    import { call_aurora } from "./_aurora.js";
    import { hash2SortedSelect } from "./_tools.js";    
    import Status from "./Status.svelte";
    import { sendStatusMessage } from "./_tools";
    
    let CFG={};
    let disabled=false;        
    let name="Auth";
    let authtypeval="AuroraID";
    let authtypeprom;
    let authtypes=[];
    let authhash={};       
    let authstr1="";
    let authstr2="";    
    let changeauth;
    // id of user to change his authentication
    export let id=0;
    // users email
    let email="";

    const sendUpdated = () => {
        sendStatusMessage("Successfully updated authentication...","info");
        return "";
    }

    // handles first time logon attempt
    onMount(async () => {        
        // fetch configuration and wait
        CFG = await getConfig();
        // set disabled
        disabled = CFG["www.maintenance"]||false;
        // attempt an authentication automatically
        // and thereby check our credentials
        // we will be redirected to login-page if it fails
	    call_aurora("doAuth",undefined);    
        // get computers    
        authtypeprom=getAuthTypes();              
	});
       
    async function getAuthTypes () {
        // attempt to get computers that user have access to
        // get computers
        let params={};             
        let auth=await call_aurora("enumAuthTypes");

        await auth;

        // get user email at the same time
        params={};
        if (id != 0) {            
            params["id"]=id;
        }
        let em=await call_aurora("getUserEmail",params);

        await em;

        if (em.err == 0) {
            // save email address of user
            email=em.email;
        }

        if (auth.err == 0) {
            // sort result
            authhash={};
            for (let key in auth.authtypes) {           
                // only include auth types that can be updated     
                if (auth.authtypes[key].change == 1) {
                    authhash[key]=key;                    
                }
            }

            authtypes=hash2SortedSelect(authhash);            
        }
        if ((auth.err == 0) && (em.err == 0)) { return 1; } else { return 0; }       
    }    

    const changeAuth = () => {
        let params={};             
        params["type"]=authtypeval;
        params["auth"]=email+","+authstr1;
        changeauth=call_aurora("changeAuth",params);    
    }
</script>

{#if !disabled}
    <div class="ui_center">            
        <div class="ui_title ui_margin_top">Change Authentication</div>    
    </div>
    {#if changeauth != undefined}
        {#await changeauth}
            <Status message="Updating authentication..." type="processing" />
        {:then result}
            {#if result.err == 0}
                {sendUpdated()}
            {/if}
        {/await}
    {/if}
    {#if authtypeprom != undefined}
        {#await authtypeprom}
            <Status message="Retrieving authentication types..." type="processing" />            
        {:then result}               
            <div class="ui_center">            
                <div class="ui_label ui_margin_top">User Email</div>
                <div class="ui_output">
                    {email}
                </div>                            
            </div>    
            <div class="ui_center">            
                <div class="ui_label ui_margin_top">Authentication Type</div>
                <div class="ui_input">
                    <InputSearchList bind:value={authtypeval} datalist={authtypes} defaultValue={authtypeval} size=30 />
                </div>                            
            </div>    
            {#if authtypeval != "" && authhash[authtypeval] !== undefined}    
                <div class="ui_center">            
                    <div class="ui_label ui_margin_top">Authentication code</div> 
                    <div class="ui_input">
                        <input type="password" bind:value={authstr1} size=64 maxlength=4096>
                    </div>    
                </div>    
                <div class="ui_center">            
                    <div class="ui_label ui_margin_top">Repeat Authentication code</div> 
                    <div class="ui_input">
                        <input type="password" bind:value={authstr2} size=64 maxlength=4096>
                    </div>    
                </div>
                {#if authstr1 == authstr2}
                    <div class="ui_center ui_margin_top">
                        <button class="ui_button" on:click={() => { changeAuth() }}>Change</button>                    
                    </div>   
                {/if}    
            {/if}
        {:catch error}   
            <div class="ui_center">Unable to retrieve authentication types...</div>
        {/await}   
    {/if}    
{:else}
    {window.location.href=CFG["www.base"]}
{/if}




    
