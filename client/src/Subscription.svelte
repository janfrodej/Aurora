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

    Description: View and set notification-subscriptions and votes on the AURORA entity tree.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="Subscription";
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
    let updatesubs;
    
    // some variables    
    let show = false;
    let show_editsub = false;
    let users = {};
    let subs = {};
    let votes = {};
    let notices = {};
    let name = "";

    let voteno = 0;
    let userval = 0;
    let subuser = 0;

    let pcounter = 0;

    // rerender trigger
    let rerender = 0;

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        data = getData();
    });      

    // call REST-server to set task    
    async function setSubscriptions() {
        let params={};
        // first set subscriptions
        params["id"]=id;
        params["subscriptions"]=subs;        
        let updatesubs=await call_aurora("setGroupNoticeSubscriptions",params);

        await updatesubs;

        if (updatesubs.err == 0) { subs = updatesubs.subscriptions; }

        // then set votes
        params={};
        params["id"]=id;
        params["votes"]=votes;
        let updatevotes=call_aurora("setGroupUsersVotes",params);        

        await updatevotes;

        if (updatevotes.err == 0) { votes = updatevotes.votes; }

        if ((updatesubs.err == 0) && (updatevotes == 0)) { return 1; } else { return 0; }
    };

    // get all data needed 
    async function getData () {    
        show = false;
       
        // get name of entity to edit subscriptions of
        let params={};
        params.id = id;
        let getname = await call_aurora("getName",params);

        if (getname.err == 0) {
            // get data
            name = getname.name;
        }


        // get users votes on given group
        params={};
        params.id = id;
        let getvotes = await call_aurora("getGroupUsersVotes",params);

        if (getvotes.err == 0) {
            // get data
            votes = getvotes.votes;
        }

        // get subscriptions
        params={};      
        params.id = id;  
        let getsubs = await call_aurora("getGroupNoticeSubscriptions",params);

        // was data retrieved successfully?
        if (getsubs.err == 0) {
            // get subscriptions
            subs = getsubs.subscriptions;            
        }

        // enum users    
        params={};        
        let getusers = await call_aurora("enumUsers",params);

        // was data retrieved successfully?
        if (getusers.err == 0) {
            // save users
            users = getusers.users;            
        }

        // enum notices
        params={};        
        let getnotices = await call_aurora("enumNotices",params);

        // was data retrieved successfully?
        if (getnotices.err == 0) {
            // save notices
            notices = getnotices.notices;      
            // add the ALL notice
            notices[0] = "ALL";            
        }

        if ((getvotes.err == 0) && (getsubs.err == 0) && 
            (getname.err == 0) && (getusers.err == 0) && (getnotices.err == 0)) {
            // show data
            show = true;
            // return success
            return 1;
        } else { return 0; }
    };

    const sendUpdated = () => {
        sendStatusMessage("Successfully updated subscriptions...","info");
        return "";
    }

    // update which subscriptions user is subscribing to.
    const updateSubs = (ev,notice) => {
        let checked = Boolean(ev.target.checked);
        // check if subuser-hash is empty or not...
        if (subs[subuser] == undefined) { subs[subuser] = {}; }
        // just set the value, either true 1 or 0 false
        subs[subuser][notice] = (checked ? 1 : 0);
    };

    const editSub = () => {
        if ((subuser != undefined) && (subuser != 0)) {
            show_editsub=true;
        }        
    };

    const removeSub = () => {
        let updated=false;
        if ((subuser != undefined) && (subuser != 0)) {            
            if (Object.keys(subs).includes(subuser)) {
                // user exists in hash - remove...
                delete subs[subuser];
                updated=true;
            }
            if (Object.keys(votes).includes(subuser)) {
                // user exists in votes - remove
                delete votes[subuser];
                updated=true;
            }
        }
        // rerender component if user was removed
        if (updated) { rerender++; }
    };

    const closeEditSub = () => {
        show_editsub=false;
    }

    const addUser = () => {
        let added=false;
        if (userval == 0) { return; }
        // add a new user to the subs and votes-hash
        if (subs[userval] == undefined) {
            // automatically add "ALL"-subscription
            subs[userval] = {};
            subs[userval]["0"] = 1;
            added=true;
        }
        if (votes[userval] == undefined) {
            // add users votes
            votes[userval] = Number(voteno);
            added=true;
        }
        if (added) { userval=0; rerender++; }
    };

    // increment counter
    const incCounter = () => {
        pcounter++;
        return "";
    }

    // get current counter without increment
    const getCounter = () => {      
        return pcounter;
    }
</script>    

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving subscription data..." type="processing" />
        {/await}
    {/if}
    {#if updatesubs != undefined}
        {#await updatesubs}
            <Status message="Updating subscriptions..." type="processing" />
        {:then result}
            {#if result.err == 0}
                {sendUpdated()}
            {/if}    
        {/await}
    {/if}    
    {#if show}    
        {#key rerender}
            <!-- show title and table with entity metadata -->
            <div class="ui_title ui_center">Edit Subscriptions</div>
            <div class="ui_center">
                <div class="ui_label">Name</div>
                <div class="ui_text_large ui_output">{name} ({id})</div>
                <div class="ui_label">Votes</div>
                <div class="ui_input"><input type="text" bind:value={voteno}></div>
                <div class="ui_label">Add User</div>
                <div class="ui_input">
                    <InputSearchList bind:value={userval} datalist={hash2SortedSelect(users)} defaultValue={userval} />
                </div>
                <div class="ui_margin_top">
                    <button class="ui_button" on:click={() => { addUser() }}>Add</button>
                </div>
                <div class="ui_label">Current Subscriptions</div>
                <div class="ui_select">
                    <select class="ui_margin_top" bind:value={subuser} size=8>
                        {#each Object.keys(subs) as uid}
                            <option value={uid}>{users[uid]} ({votes[uid]})</option>
                        {/each}
                    </select>
                </div>
                <div class="ui_margin_top ui_row">
                    <button class="ui_button" on:click={() => { editSub() }}>Edit</button>
                    <button class="ui_button" on:click={() => { removeSub() }}>Remove</button>
                </div>
                <div class="ui_margin_top">
                    <button class="ui_button" on:click={() => { updatesubs=setSubscriptions(); }} >Update</button>
                </div>
                 {#if show_editsub}
                    <Modal width="60" height="90" border={false} closeHandle={() => { closeEditSub() }}>
                        {#if subuser != undefined && subuser != 0 && subs[subuser] != undefined}
                            <div class="ui_title ui_center">Edit User Subscription</div>
                            <div class="ui_label">User</div>
                            <div class="ui_output">{users[subuser]}</div>
                            <div class="ui_label">Votes</div>
                            <div class="ui_input"><input type="text" bind:value={votes[subuser]}></div>

                            <div class="ui_center ui_margin_top">
                                <div class="ui_row">
                                    <checkbox
                                        name={compname+"_subs_"+myrand} 
                                    >
                                        {#each Object.keys(notices) as notice}
                                            {incCounter()}
                                            <label>
                                                <input
                                                    type="checkbox"
                                                    name={compname+"_subs_checkbox_"+getCounter()+"_"+myrand}
                                                    key={compname+"_subs_checkbox_"+getCounter()+"_"+myrand}
                                                    on:change={(ev) => { updateSubs(ev,notice); }}
                                                    value="1"
                                                    checked={(subs[subuser][notice] != undefined && subs[subuser][notice] == 1 ? true : false)}
                                                >
                                                {notices[notice]}
                                            </label>                     
                                        {/each}
                                    </checkbox>
                                </div>
                            </div>
                        {/if}
                    </Modal>
                 {/if}
            </div>            
        {/key}
    {/if}        
{/if}
