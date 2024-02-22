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

    Description: View, Add or Remove members of a GROUP-entity.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="Members";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";
    import { hash2SortedSelect } from "./_tools";
    import Status from "./Status.svelte";
    import InputSearchList from "./InputSearchList.svelte";
    import { onMount } from 'svelte';

    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);
    // subject types that one can select from to add permissions
    // on the given entity object
    export let types=["GROUP", "USER", "COMPUTER"];

    // promises
    let data;
    let updategroup;
    
    // some variables    
    let show = false;
    let updated = 0;
    let updatesuccess=false;
    let started = false;
    let name = "";
    let entities={};
    let includes={};
    // list of possible subjects to choose from when setting permissions
    let subjects=[];
    let subject=0;
    // list of possible members of a group
    let members={};
    let member=0;    
    // list of members before editing by user, used for comparison
    let orgmembers=[];    

    types.map(function(typ) { includes[typ]=true; } );
    // set computer and user to false, so it is not selected by default
    includes["COMPUTER"] = false;
    includes["USER"] = false;
    $: includes && started && (data=getEntities());
    
    onMount(async () => {        
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        // get data
        data = getData();
    });        

     // update the entities we have found
     const updateEntities = (result) => {
        // do not show anything if we failed to retrieve metadata for an entity
        // set an empty subjects
        if (result["entities"] == undefined) { subjects=[]; return ""; }    
        // set the entities variable to result
        entities = result.entities;
        // make a new hash with only entity id => name.
        let selhash={};         
        for (let key in entities) {                
            selhash[key]=entities[key].name+" ("+entities[key].type+")";
        }
        // create an array usable by a select-input of subjects
        subjects=hash2SortedSelect(selhash);        
        return "";
    };


    async function getEntities () {
        // map includes to array
        let incl=[];
        for (let key in includes) {
            // only include types that are selected
            // in checkboxes
            if (includes[key]) { incl.push(key); }
        }
        // only ask REST-server if any categories have been included
        if (incl.length == 0) {
            // make an empty entities hash object
            let result={};
            result.entities={};
            // give empty entities hash and update list
            updateEntities(result);
        } else {
            let params={};
            params["name"]="*";
            params["include"]=incl;
            let result=await call_aurora("getEntities",params);
            if (result.err == 0) { updateEntities(result); }
        }    
    }    

    // get all data needed to edit permissions
    async function getData () {        
        // get name of id        
        let params={};
        params["id"]=id;
        let getname=await call_aurora("getName",params);

        await getname;

        if (getname.err == 0) { name = getname.name; }
                
        // map includes to array
        let incl=[];
        for (let key in includes) {
            // only include types that are selected
            // in checkboxes
            if (includes[key]) { incl.push(key); }
        }
        // get entities
        params={};
        params["name"]="*";
        params["include"]=incl;
        let getent=await call_aurora("getEntities",params);

        await getent;
        
        if (getent.err == 0 ) { updateEntities(getent); }

        // get members
        params={};
        params["id"]=id;
        let getmem=await call_aurora("getGroupMembers",params);

        await getmem;
        if (getmem.err == 0) { 
            members=hash2SortedSelect(getmem.members); 
            // add members to orgmembers
            orgmembers=[];
            for (let key in getmem.members) {
                orgmembers.push(key);
            }
        }
        
        // started is true
        started = true;

        if ((getname.err == 0) && (getent.err == 0) && (getmem.err == 0)) { show = true; return 1; }
        else { return 0; }
    };    

    const setMember = (ev) => {
        // set the member id
        member = ev.target.value;
    };

    const removeMember = () => {
        // locate entity in members list
        let pos=-1;
        for (let i=0; i < members.length; i++) {
            if (members[i].id == member) {
                pos=i;
                break;
            }
        }       
        if (pos != -1) {
            // entity found, remove it
            members.splice(pos,1);
            // set member to zero since it was removed from list
            member=0;
            // list was updated, render again
            updated++;     
        }        
    };

    const addMember = () => {
        // locate subject in members list, if at all
        let pos=-1;
        for (let i=0; i < members.length; i++) {
            // subject exists in member list already
            if (members[i].id == subject) {
                pos=i;
                break;
            }
        }       
        // only if subject does not exist in member list already are we to add it
        if (pos == -1) {
            // we need to locate subject in subjects list
            let subpos=-1;
            for (let i=0; i < subjects.length; i++) {
                if (subjects[i].id == subject) {
                    subpos=i;
                    break;
                }
            }    
            if (subpos != -1) {
                // member not found in members and we located him in the subjects list
                // we can add it
                members.push(subjects[subpos]);
                // list was updated, render again
                updated++;
            }
        }        
    };  

    async function updateGroup() {        
        // make a list from members
        let newmembers=[];
        for (let i=0; i < members.length; i++) {
            newmembers.push(members[i].id);
        }
        // compare original members list with new list
        let remove=[];            
        for (let i=0; i < orgmembers.length; i++) {
            if (!newmembers.includes(orgmembers[i])) {
                // to be removed
                remove.push(orgmembers[i]);
            } else {
                // if its there - remove it from newmembers, because
                // we do not need to add it again
                let pos=newmembers.indexOf(orgmembers[i]);
                if (pos > -1) {
                    newmembers.splice(pos,1);
                }
            }
        }

        // we do a remove first, but only if list contains members
        let prm;
        let padd;
        let pget;

        if (remove.length > 0) {
            let params={};
            params["id"]=id;
            params["member"]=remove;
            prm=await call_aurora("removeGroupMember",params);                        
        }

        // add all relevant members, if any
        if (newmembers.length > 0) {
            let params={};
            params["id"]=id;
            params["member"]=newmembers;
            padd=await call_aurora("addGroupMember",params);
        }    

        if (((padd != undefined) && (padd.err == 0)) ||
            ((prm != undefined) && (prm.err == 0))) {
            // we now need to read out how the group looks like
            // get members
            let params={};
            params["id"]=id;
            pget=await call_aurora("getGroupMembers",params);

            // await pget;
            if (pget.err == 0) { 
                members=hash2SortedSelect(pget.members); 
                // update orgmembers
                orgmembers=[];
                for (let key in pget.members) {
                    orgmembers.push(key);
                }             
            }
        }    
     
        if ((pget != undefined) && (pget.err == 0)) { updated++; updatesuccess=true; }                
    };
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving member data..." type="processing" />
        {/await}
    {/if}       
    {#if updategroup != undefined}
        {#await updategroup}
            <Status message="Updating group members..." type="processing" />
        {/await}
    {/if}
    {#if show}
        {#key updated}
            <div class="ui_center">      
                <div class="ui_title">Edit Members</div>
                <div class="ui_output">{id} ({name})</div>         
                
                <!-- show the member selection pool and option to include/exclude entity types -->
                <div class="ui_center_row ui_margin_top">
                    {#each types as item}
                        <label>
                            <input type="checkbox" name="{item}_checkbox" bind:checked={includes[item]} key="{item}_checkbox">
                            {item}
                        </label>
                    {/each}            
                </div>
                <div class="ui_input ui_center">
                    <InputSearchList bind:value={subject} datalist={subjects} defaultValue={subject} />                    
                    <button class="ui_button" on:click={() => { addMember(); }} disabled={!/^\d+$/.test(subject || subject == 0)}>Add</button>
                </div>                

                <!-- show the member list of the given entity (id) -->
                <div class="ui_center ui_margin_top">
                    <div class="ui_select">
                        <select on:change={(ev) => { setMember(ev); }} size=8>
                            {#each members as membr}    
                                <option value={membr.id}>{membr.text}</option>
                            {/each}
                        </select>
                    </div>
                    <button class="ui_button" on:click={() => { removeMember(); }} disabled={member == 0}>Remove</button>
                </div>
                
                <button class="ui_button" on:click={() => { updategroup=updateGroup(); }}>Update</button>
            </div>
        {/key}
    {/if}    
{/if}
