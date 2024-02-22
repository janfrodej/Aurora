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

    Description: Handle viewing, changing and adding permissions of AURORA entities.
-->
<script context="module">
   // unique counter for instances of component
   let counter = 0;
</script>

<script> 
    // component name
    let compname="Permissions";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { hash2SortedSelect } from "./_tools.js";    
    import { call_aurora } from "./_aurora.js";    
    import InputSearchList from "./InputSearchList.svelte";
    import Status from "./Status.svelte";
    import { onMount } from 'svelte';

    let CFG={};

    let disabled=false;    

    // object entity id that we are working on
    export let id = 0;
    id=Number(id);
    // entity object type that we are editing on
    export let type="DATASET";
    type=type.toUpperCase();
    // subject types that one can select from to add permissions
    // on the given entity object
    export let types=["GROUP", "USER", "COMPUTER"];
    // selected subject that we are viewing permissions of on
    // object (id) we are working on
    export let subject = 0;
    $: subject && updatePermTable();

    // some internal variables
    let methodtype=type.substring(0,1).toUpperCase() + type.substring(1).toLowerCase();
    // promises promises...
    let getperms;
    let setperms;
    let getpermtypes;
    let getname;
    let getentities;
    let getdata;
    // data holders
    let perms={};
    let permtable=[];
    let permtableidx={};
    let blanktable=[];    
    let permtypes=[];
    let entities={};
    let includes={};
    types.map(function(typ) { includes[typ]=true; } );
    // set computer and user to false, so it is not selected by default
    includes["COMPUTER"] = false;
    includes["USER"] = false;
    $: includes && getEntities();
    let entityperms={}; // entities with perm set on object
    // settings    
    let showdata=false;
    let name="";
    // list of possible subjects to choose from when setting permissions
    let subjects=[];    
    // fill subject types with the types allowed to select from
    let subjecttypes=types;    

    // handles first time logon attempt
    onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // update disable
      disabled=CFG["www.maintenance"] || false;    
      // attempt an authentication automatically
      // and thereby check our credentials
      // we will be redirected to login-page if it fails
	  call_aurora("doAuth",undefined);
      // get the data for the first screen
      getdata=getData();
	});

    // update the permission types based on return from REST-call
    const setPermTypes = (t) => {   
        // do not show anything if we failed to retrieve metadata for an entity
        if (t["types"] == undefined) { return ""; }    
        // sort the array
        let tmp=t.types;
        tmp.sort();
        // construct the final array by prioritizing
        // the selected entity type on top.
        let typeind=type + "_";
        let top=[];
        let bottom=[];
        // go through each enumerated type and build final array
        tmp.forEach((elem) => {
            if (elem.substring(0,type.length+1).toUpperCase() == typeind) {
                // part of the selected type, add it
                top.push(elem);
            } else {
                // not part of the selected type, add to bottom
                bottom.push(elem);
            }
        });        
        // combine top and bottom together
        permtypes=[...top, ...bottom];
        // generate a blank permtable
        let tmptable=[];
        let idx={};
        permtypes.forEach((item) => {            
            // create hash object to store values on
            let o={};
            o["permname"]=item;
            o["inherit"]=false;
            o["grant"]=false;
            o["deny"]=false;
            o["perm"]=false;            
            // push object on tmptable array
            tmptable.push(o);
            // update index of permtype key
            idx[item]=tmptable.length-1;
        }); 
        // store it in blanktable
        blanktable=tmptable;        
        // set permtable to the blank table
        permtable=JSON.parse(JSON.stringify(blanktable));
        // update the permtable key-index overview
        permtableidx=idx;
        // update show        
        return "";
    };

    // update name with return from REST-call
    const setName = (result) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (result["name"] == undefined) { return ""; }    
        name = result.name +  "(" + id + ")";
        return "";
    };

    // update the entities we have found
    const updateEntities = (result) => {
        // do not show anything if we failed to retrieve metadata for an entity
        // set an empty subjects
        if (result["entities"] == undefined) { subjects=[]; return ""; }    
        // set the entities variable to result
        entities=result.entities;
        // make a new hash with only entity id => name.
        let selhash={};         
        for (let key in entities) {                
            selhash[key]=entities[key].name+" ("+entities[key].type+")";
        }
        // create an array usable by a select-input of subjects
        subjects=hash2SortedSelect(selhash);        
        return "";
    };

    const getEntities = () => {
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
            getentities=call_aurora("getEntities",params);
        }    
    }

    // get permissions set on object that we are editing
    // permissions on
    const getPerms = () => {        
        let params={};
        params["id"]=id;
        getperms=call_aurora("get" + methodtype + "Perms",params);      
        return "";  
    };

    // update the perms we have for given object we are editing
    const updatePerms = (p) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (p["perms"] == undefined) { entityperms=[]; return ""; }    
        // update component state perms, go through and only pick 
        // inherit, grant, deny and perm
        let tmpperm={};
        let e={};
        for (let entity in p.perms) {
            // add entity to tmp entity hash
            e[entity]=(p.perms[entity].name != undefined ? p.perms[entity].name : "N/A");
            if (tmpperm[entity] == undefined) { tmpperm[entity]={}; }
            for (let key in p.perms[entity]) {
                if ((key == "inherit") || (key == "grant") || (key == "deny") || (key == "perm")) {
                    tmpperm[entity][key]=p.perms[entity][key];
                }
            }
        }
        perms=tmpperm;
        // update permtable
        updatePermTable();
        // update entity select       
        entityperms=hash2SortedSelect(e);
        // update show      
        return "";
    };

    // update permtable based upon selected entity one is working on
    const updatePermTable = () => {
        // ensure that subject is other than 0 and it is a number
        if ((subject != 0) && (String(subject).match(/^[\d]+$/))) {                     
            // start with a blank table
            let tmptable=JSON.parse(JSON.stringify(blanktable));
            // get entity permissions, if any
            let permuser=(perms[subject] != undefined ? JSON.parse(JSON.stringify(perms[subject])) : {});            
            // go through each permission that entity has, if any
            for (let permcat in permuser) {    
                permuser[permcat].forEach((item) => {
                    // update permtable (item = PERM TYPE, permcat = perm, grant, deny etc.)
                    tmptable[permtableidx[item]][permcat]=true;
                });
            }            
            // update permtable
            permtable=tmptable;
        } else { permtable = JSON.parse(JSON.stringify(blanktable)); }      
    };

    // set new permissions in AURORA for given object we are working on
    const setPerms = () => {           
        // construct grant and deny to REST-call by
        // iterating over the whole permtable and selecting all
        // checked values
        let grant=[];
        let deny=[];
        for (let i=0; i < permtable.length; i++) {
            let permname = permtable[i]["permname"];
            if (permtable[i]["grant"]) { grant.push(permname); }
            if (permtable[i]["deny"]) { deny.push(permname); }            
        }
        // construct the REST-call parameters
        let params={};
        params["id"] = id;
        params["user"] = subject;
        params["grant"]=grant;
        params["deny"]=deny;
        params["operation"] = "REPLACE";

        setperms=call_aurora("set" + methodtype + "Perm",params);        
        return "";
    };        

    // get all data needed to edit permissions
    async function getData () {        
        getpermtypes=await call_aurora("enumPermTypes"); 
    
        await getpermtypes;

        if (getpermtypes.err == 0) { setPermTypes(getpermtypes); }

        let params={};
        params["id"]=id;
        getname=await call_aurora("getName",params);

        await getname;

        if (getname.err == 0) { setName(getname); }
        
        params={};
        params["id"]=id;
        getperms=await call_aurora("get" + methodtype + "Perms",params);      

        await getperms;        

        // map includes to array
        let incl=[];
        for (let key in includes) {
            // only include types that are selected
            // in checkboxes
            if (includes[key]) { incl.push(key); }
        }
        params={};
        params["name"]="*";
        params["include"]=incl;
        let getent=await call_aurora("getEntities",params);

        await getent;
        
        if (getent.err == 0 ) { updateEntities(getent); }
        
        if ((getpermtypes.err == 0) || (getname.err == 0) || (getperms.err == 0) || (getent.err == 0)) { showdata = true; return 1; }
        else { return 0; }
    };
</script>

{#if !disabled}
    {#if getdata !== undefined}
        {#await getdata}
            <Status message="Reading permissions data..." type="processing" />                         
        {/await}
    {/if}    
    {#if setperms != undefined}
        {#await setperms}
            <Status message="Updating permissions..." type="processing" />             
        {:then result}           
            {#if result.err == 0}
                {getPerms()}
            {/if}
        {/await}        
    {/if}    
    {#if getperms != undefined && showdata}
        {#await getperms}
            <Status message="Reading permissions..." type="processing" />             
        {:then result}
            {#if result.err == 0}
                {updatePerms(result)}
            {/if}    
        {/await}
    {/if}    
    {#if getentities != undefined && showdata}
        {#await getentities}
            <Status message="Updating entities list..." type="processing" />                         
        {:then result}
            {#if result.err == 0}
                {updateEntities(result)}
            {/if}    
        {/await}
    {/if}
    {#if showdata}
        <div class="ui_title ui_center">Assign Permission(s)</div>
        <div class="ui_label ui_center">Entity to assign on:</div>
        <div class="ui_label ui_center">{name} ({type})</div>
        <div class="ui_label ui_center">Add</div>
        <div class="ui_center_row">        
            {#each types as item}
                <label>
                    <input type="checkbox" name="{item}_checkbox" bind:checked={includes[item]} key="{item}_checkbox">
                    {item}
                </label>
            {/each}            
        </div>
        <div class="ui_input ui_center"><InputSearchList bind:value={subject} datalist={subjects} defaultValue={subject} /></div>        
        <div class="ui_label ui_center">Edit</div>        
        <div class="ui_input ui_center"><InputSearchList bind:value={subject} datalist={entityperms} defaultValue={subject} /></div>
        
        {#if /^\d+$/.test(subject) & subject !== 0}
            <div class="ui_input ui_center"><button class="ui_button" on:click={() => { setPerms(); }}>Update</button></div>
        {:else}
            <div class="ui_input ui_center"></div>            
        {/if}    
        
        <div class="ui_table">
            <div class="ui_table_header_cell">Permission</div>
            <div class="ui_table_header_cell">Inherited</div>
            <div class="ui_table_header_cell">Deny</div>
            <div class="ui_table_header_cell">Grant</div>
            <div class="ui_table_header_cell">Effective</div>

            {#each permtypes as item,index}                                
                    <div class="{(index % 2 == 0 ? "ui_table_row_even" : "ui_table_row_odd")}">
                    <div class="ui_table_cell">{item}</div>
                    <div class="ui_table_cell">
                        {#if permtable[permtableidx[item]]["inherit"]}
                            [&#10003]
                        {:else}
                            [&nbsp&nbsp]
                        {/if}
                    </div>
                    <div class="ui_table_cell">
                        [<input type="checkbox" name="{item}_deny_checkbox" key="{item}_deny_checkbox" bind:checked={permtable[permtableidx[item]]["deny"]} disabled={!/^\d+$/.test(subject)|| subject == 0}>]
                    </div>
                    <div class="ui_table_cell">
                        [<input type="checkbox" name="{item}_grant_checkbox" key="{item}_grant_checkbox" bind:checked={permtable[permtableidx[item]]["grant"]} disabled={!/^\d+$/.test(subject)|| subject == 0}>]
                    </div>

                    <div class="ui_table_cell">
                        {#if permtable[permtableidx[item]]["perm"]}
                            [&#10003]
                        {:else}
                            [&nbsp&nbsp]
                        {/if}
                    </div>
                </div>
            {/each}
        </div>

        {#if /^\d+$/.test(subject) & subject !== 0}
            <div class="ui_input ui_center"><button class="ui_button" on:click={() => { setPerms(); }}>Update</button></div>
        {:else}
            <div class="ui_input ui_center"></div>            
        {/if}    
    {/if}    
{:else}
    <div></div>
{/if}
